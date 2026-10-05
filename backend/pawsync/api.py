import asyncio
import contextlib
import datetime as dt
import hmac
import json
import logging
import pathlib
import copy
import re
import secrets
import uuid
from contextlib import asynccontextmanager

import sentry_sdk
from fastapi import Depends, FastAPI, File, Header, Request, UploadFile
from fastapi.responses import JSONResponse, FileResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError

from .config import Settings
from .database import LibraryProgressRecord, LibraryProgressBackup, Account, RestoreCode, Revocation, WebhookEvent, connect, now
from .progress import ProgressPayload, fresh, merge as merge_progress
from .limits import RateLimiter
from .mail import send_restore_code
from .payments import catalog_items, customer_email
from .pipeline import MAX_PHOTO, validate_photo, vectorize
from .security import LicenseAuthority, verify_paddle
from .wallet import WalletError, commit, fulfill, lock_account, owned_accessories, recover_expired, refund, reserve, revoke

log = logging.getLogger("pawsync")
bearer = HTTPBearer(auto_error=False)


def audit(event, **fields):
    log.info(json.dumps({"event": event, **fields}, separators=(",", ":")))


class PayloadTooLarge(Exception):
    pass


class BodyLimit:
    def __init__(self, app, maximum=MAX_PHOTO + 1024 * 1024):
        self.app, self.maximum = app, maximum

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            await self.app(scope, receive, send); return
        headers = dict(scope["headers"])
        maximum = self.maximum if scope.get("path") == "/v1/pet/vectorize" else (256 * 1024 if scope.get("path") in {"/v1/webhooks/paddle", "/v1/library/progress"} else 8192)
        try:
            length = int(headers.get(b"content-length", b"0"))
        except ValueError:
            await JSONResponse({"detail": "Invalid content length"}, 400)(scope, receive, send); return
        if length > maximum:
            await JSONResponse({"detail": "Request is too large"}, 413)(scope, receive, send); return
        seen = 0
        started = False

        async def bounded():
            nonlocal seen
            message = await receive()
            seen += len(message.get("body", b""))
            if seen > maximum:
                raise PayloadTooLarge()
            return message

        async def track(message):
            nonlocal started
            if message["type"] == "http.response.start": started = True
            await send(message)

        try:
            await self.app(scope, bounded, track)
        except PayloadTooLarge:
            if not started:
                await JSONResponse({"detail": "Request is too large"}, 413)(scope, receive, send)


class RestoreRequest(BaseModel):
    email: EmailStr


class RestoreVerification(RestoreRequest):
    code: str = Field(min_length=8, max_length=8, pattern=r"^[0-9]{8}$")


def create_app(settings=None, session_factory=None, limiter=None, pipeline=None, email_sender=None, customer_lookup=None):
    settings = settings or Settings()
    authority = None
    engine = None
    factory = session_factory
    limits = limiter

    async def recovery_loop():
        while True:
            try:
                count = await asyncio.to_thread(recover_expired, factory)
                if count: audit("generation_leases_recovered", count=count)
            except Exception as error:
                audit("lease_recovery_failed", error_type=type(error).__name__)
                sentry_sdk.capture_exception(error)
            await asyncio.sleep(30)

    def scrub(event, hint):
        event.pop("user", None); event.pop("request", None); event.pop("breadcrumbs", None)
        return event

    @asynccontextmanager
    async def lifespan(app):
        nonlocal authority, engine, factory, limits
        settings.validate()
        authority = LicenseAuthority(settings.private_key_path)
        if factory is None:
            engine, factory = connect(settings.database_url)
        if limits is None: limits = RateLimiter(settings.redis_url)
        if settings.sentry_dsn:
            sentry_sdk.init(dsn=settings.sentry_dsn, environment=settings.environment, send_default_pii=False,
                            traces_sample_rate=0, max_request_body_size="never", include_local_variables=False, before_send=scrub)
        await asyncio.to_thread(recover_expired, factory)
        task = asyncio.create_task(recovery_loop())
        yield
        task.cancel()
        with contextlib.suppress(asyncio.CancelledError): await task
        if engine: engine.dispose()

    app = FastAPI(title="PawSync", version="0.1.0", lifespan=lifespan,
                  docs_url="/docs" if settings.environment != "production" else None,
                  redoc_url=None, openapi_url="/openapi.json" if settings.environment != "production" else None)
    app.add_middleware(BodyLimit)
    app.state.pipeline = pipeline or vectorize

    @app.exception_handler(WalletError)
    async def domain_error(request, error):
        if error.status >= 500: audit("request_failed", status=error.status)
        return JSONResponse({"detail": error.message}, status_code=error.status)

    @app.exception_handler(Exception)
    async def unexpected_error(request, error):
        audit("request_rollback", error_type=type(error).__name__)
        sentry_sdk.capture_exception(error)
        return JSONResponse({"detail": "The service encountered an error. Please retry."}, status_code=503)

    def client_ip(request):
        return request.client.host if request.client else "unknown"

    def authenticated(request: Request, credentials: HTTPAuthorizationCredentials | None = Depends(bearer)):
        limits.check("auth-ip", client_ip(request), 60)
        if not credentials:
            raise WalletError("License token required", 401)
        with factory() as session:
            account = authority.verify(session, credentials.credentials)
            return account.id

    @app.get("/health")
    def health():
        return {"ok": True}

    def save_progress(session,account_id,state):
        existing=session.get(LibraryProgressRecord,account_id)
        if existing:
            session.add(LibraryProgressBackup(account_id=account_id,state=copy.deepcopy(existing.state)))
            existing.state=state;existing.updated_at=now()
        else: session.add(LibraryProgressRecord(account_id=account_id,state=state))
        session.flush()
        backups=session.scalars(select(LibraryProgressBackup).where(LibraryProgressBackup.account_id==account_id).order_by(LibraryProgressBackup.created_at.desc(),LibraryProgressBackup.id.desc())).all()
        for old in backups[20:]: session.delete(old)

    @app.post("/v1/library/progress")
    def sync_progress(payload:ProgressPayload,account_id=Depends(authenticated)):
        limits.check("progress-account",account_id,20)
        with factory.begin() as session:
            lock_account(session,account_id)
            existing=session.get(LibraryProgressRecord,account_id)
            state=merge_progress(existing.state if existing else None,payload.model_dump())
            save_progress(session,account_id,state)
            return state

    @app.post("/v1/library/progress/reset")
    def reset_progress(account_id=Depends(authenticated)):
        limits.check("progress-reset",account_id,3,600)
        with factory.begin() as session:
            lock_account(session,account_id)
            existing=session.get(LibraryProgressRecord,account_id)
            epoch=(existing.state['epoch'] if existing else 0)+1
            save_progress(session,account_id,fresh(epoch))
            return {"epoch":epoch}

    def read_library_content():
        path=pathlib.Path(settings.library_content_path) if settings.library_content_path else pathlib.Path(__file__).resolve().parents[2]/"macos/Resources/Library/catalog.json"
        if not path.is_file() or path.stat().st_size>1024*1024: raise WalletError("Library content is not configured",503)
        return json.loads(path.read_text())

    @app.get("/v1/library/catalog")
    def library_catalog(request:Request):
        limits.check("content-ip",client_ip(request),30)
        return read_library_content()

    @app.get("/v1/library/pets/{pet_id}")
    def library_pet(pet_id:str,request:Request,credentials:HTTPAuthorizationCredentials | None = Depends(bearer)):
        limits.check("content-pet-ip",client_ip(request),10)
        if not re.fullmatch(r"[a-z0-9][a-z0-9_-]{0,79}",pet_id): raise WalletError("Invalid pet ID",404)
        entry=next((p for p in read_library_content().get('pets',[]) if p['id']==pet_id),None)
        if entry is None: raise WalletError("Pet is not in this collection",404)
        if entry.get('requiresSKU'):
            if credentials is None: raise WalletError("Restore your purchase to download this collection",401)
            with factory() as session:
                account=authority.verify(session,credentials.credentials)
                if entry['requiresSKU'] not in owned_accessories(session,account.id): raise WalletError("Collection is not owned",403)
        if not settings.library_assets_dir: raise WalletError("Collection artwork is not configured",503)
        root=pathlib.Path(settings.library_assets_dir).resolve();path=(root/(pet_id+'.zip')).resolve()
        if not path.is_relative_to(root) or not path.is_file() or path.stat().st_size>10*1024*1024: raise WalletError("Collection artwork is unavailable",404)
        return FileResponse(path,media_type="application/zip")

    @app.get("/v1/wallet")
    def wallet_snapshot(account_id=Depends(authenticated)):
        with factory() as session:
            account = session.get(Account, account_id)
            return {"licensed": account.licensed, "credits": account.balance, "accessories": owned_accessories(session, account_id)}

    @app.post("/v1/license/renew")
    def renew(account_id=Depends(authenticated)):
        with factory.begin() as session:
            account = lock_account(session, account_id)
            if not account.licensed: raise WalletError("License revoked", 401)
            return {"token": authority.issue(session, account)}

    @app.post("/v1/license/restore")
    def restore(payload: RestoreRequest, request: Request):
        if email_sender is None and not settings.smtp_host:
            raise WalletError("Purchase restoration email is not configured", 503)
        email = str(payload.email).strip().lower()
        limits.check("restore-ip", client_ip(request), 5, 600)
        limits.check("restore-email", email, 3, 600)
        code = f"{secrets.randbelow(100_000_000):08d}"
        with factory.begin() as session:
            account = session.scalar(select(Account).where(Account.email == email).with_for_update())
            eligible = account is not None and account.licensed
            if eligible:
                old = session.get(RestoreCode, email)
                if old: session.delete(old); session.flush()
                session.add(RestoreCode(email=email, code_hash=authority.code_hash(email, code), expires_at=now() + dt.timedelta(minutes=10)))
        if eligible:
            try:
                (email_sender or send_restore_code)(settings, email, code)
            except Exception as error:
                audit("restore_delivery_failed", error_type=type(error).__name__)
                # Keep the public response identical to protect account existence.
        return {"message": "If this email has a purchase, a one-time code has been sent."}

    @app.post("/v1/license/restore/verify")
    def verify_restore(payload: RestoreVerification, request: Request):
        email = str(payload.email).strip().lower()
        limits.check("verify-ip", client_ip(request), 10, 600)
        limits.check("verify-email", email, 5, 600)
        token = None
        with factory.begin() as session:
            account = session.scalar(select(Account).where(Account.email == email).with_for_update())
            code = session.scalar(select(RestoreCode).where(RestoreCode.email == email).with_for_update())
            if code:
                code.attempts += 1
                if code.attempts <= 5 and code.expires_at > now() and hmac.compare_digest(code.code_hash, authority.code_hash(email, payload.code)) and account and account.licensed:
                    token = authority.issue(session, account); session.delete(code)
        # Attempts commit even on a wrong code.
        if token is None: raise WalletError("Code is invalid or expired", 401)
        return {"token": token}

    @app.post("/v1/pet/vectorize")
    async def generate(photo: UploadFile = File(...), request_id: str = Header(..., alias="Idempotency-Key"), account_id=Depends(authenticated)):
        try: request_id = str(uuid.UUID(request_id))
        except ValueError: raise WalletError("Idempotency-Key must be a UUID", 422) from None
        await asyncio.to_thread(limits.check, "generation", account_id, 3)
        raw = await photo.read(MAX_PHOTO + 1)
        normalized = await asyncio.to_thread(validate_photo, raw)

        def begin_generation():
            with factory.begin() as session: return reserve(session, account_id, request_id)

        generation = await asyncio.to_thread(begin_generation)
        if generation.state == "succeeded": return generation.result
        generation_id, attempt = generation.id, generation.attempt
        try:
            async with asyncio.timeout(25):
                result = await app.state.pipeline(settings, normalized, generation_id)

            def finish():
                with factory.begin() as session: commit(session, generation_id, attempt, result)

            await asyncio.to_thread(finish)
            audit("generation_succeeded", generation_id=generation_id)
            return result
        except BaseException as error:
            def return_credit():
                with factory.begin() as session: refund(session, generation_id, attempt, "pipeline_failed")
            try: await asyncio.shield(asyncio.to_thread(return_credit))
            except Exception as refund_error:
                audit("generation_refund_deferred", generation_id=generation_id, error_type=type(refund_error).__name__)
            audit("generation_failed", generation_id=generation_id, error_type=type(error).__name__)
            if isinstance(error, (WalletError, asyncio.CancelledError)): raise
            raise WalletError("Generation failed or timed out. Your credit has been returned.", 502) from None

    @app.post("/v1/webhooks/paddle")
    async def paddle_webhook(request: Request, signature: str = Header("", alias="Paddle-Signature")):
        raw = await request.body()
        if len(raw) > 256 * 1024: raise WalletError("Webhook too large", 413)
        verify_paddle(raw, signature, settings.paddle_secret)
        await asyncio.to_thread(limits.check, "webhook", client_ip(request), 300)
        try:
            event = json.loads(raw)
            event_id, event_type, data = event["event_id"], event["event_type"], event["data"]
            if not isinstance(event_id, str) or not event_id.startswith("evt_") or len(event_id) > 80 or not isinstance(event_type, str) or len(event_type) > 80: raise ValueError()
        except (ValueError, KeyError, TypeError): raise WalletError("Invalid webhook", 422) from None
        with factory() as session:
            if session.get(WebhookEvent, event_id): return {"ok": True}

        email, items = None, None
        if event_type == "transaction.completed":
            if data.get("status") != "completed": raise WalletError("Transaction is not completed", 422)
            items = catalog_items(data, settings.price_catalog)
            email = await (customer_lookup or customer_email)(settings, data.get("customer_id"))
        elif event_type in {"adjustment.created", "adjustment.updated"}:
            if data.get("action") not in {"refund", "chargeback", "chargeback_warning"} or data.get("status") != "approved":
                data = None

        def apply_event():
            from .database import Purchase
            with factory.begin() as session:
                # PostgreSQL transaction-scoped advisory lock serializes deliveries across workers,
                # including a refund that arrives before the corresponding completed transaction.
                from sqlalchemy import text
                import hashlib
                transaction = data.get("transaction_id", data.get("id", event_id)) if data else event_id
                lock_key = int.from_bytes(hashlib.sha256(transaction.encode()).digest()[:8], "big", signed=True)
                session.execute(text("SELECT pg_advisory_xact_lock(:key)"), {"key": lock_key})
                if session.get(WebhookEvent, event_id): return
                if email:
                    account = session.scalar(select(Account).where(Account.email == email).with_for_update())
                    if account is None:
                        # Serialize creation for two different transactions on the same new email.
                        email_key = int.from_bytes(hashlib.sha256(email.encode()).digest()[:8], "big", signed=True)
                        session.execute(text("SELECT pg_advisory_xact_lock(:key)"), {"key": email_key})
                        account = session.scalar(select(Account).where(Account.email == email).with_for_update())
                        if account is None: account = Account(email=email); session.add(account); session.flush()
                    fulfill(session, account, data["id"], items)
                elif data and event_type in {"adjustment.created", "adjustment.updated"}:
                    transaction_id = data["transaction_id"]
                    if session.get(Revocation, transaction_id) is None:
                        session.add(Revocation(transaction_id=transaction_id, adjustment_id=data["id"]))
                    purchase = session.get(Purchase, transaction_id)
                    if purchase:
                        account = lock_account(session, purchase.account_id)
                        revoke(session, account, purchase, data["id"])
                session.add(WebhookEvent(id=event_id, event_type=event_type))
        try:
            await asyncio.to_thread(apply_event)
        except Exception as error:
            audit("payment_webhook_rollback", event_id=event_id, error_type=type(error).__name__)
            raise
        audit("payment_webhook_processed", event_id=event_id, event_type=event_type)
        return {"ok": True}

    return app


app = create_app()
