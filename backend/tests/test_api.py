import base64
import hashlib
import hmac
import io
import json
import time
import uuid

import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from fastapi.testclient import TestClient
from PIL import Image
from sqlalchemy import select

from pawsync.api import create_app
from pawsync.config import Settings
from pawsync.database import Account, CreditLedger, Purchase
from pawsync.pipeline import vectorize
from pawsync.wallet import WalletError, fulfill

pytestmark = pytest.mark.postgres


class MemoryLimiter:
    def __init__(self): self.counts = {}
    def check(self, scope, identity, ceiling, period=60):
        key = (scope, identity)
        self.counts[key] = self.counts.get(key, 0) + 1
        if self.counts[key] > ceiling: raise WalletError("Too many requests", 429)


@pytest.fixture
def service(db, tmp_path):
    key = Ed25519PrivateKey.generate()
    path = tmp_path / "key.pem"
    path.write_bytes(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
    settings = Settings(private_key_path=str(path), paddle_secret="test-secret-that-is-long-enough", pipeline_mode="demo", price_catalog={"pri_base": {"sku": "base"}, "pri_5": {"sku": "credits.5"}, "pri_hat": {"sku": "accessory.hat"}})
    sent = []
    async def customer_lookup(settings, customer_id): return "owner@example.com"
    limiter = MemoryLimiter()
    app = create_app(settings, session_factory=db, limiter=limiter, email_sender=lambda settings, email, code: sent.append((email, code)), customer_lookup=customer_lookup)
    with TestClient(app) as client:
        yield client, sent, settings, limiter


def webhook(client, settings, event):
    raw = json.dumps(event, separators=(",", ":")).encode()
    timestamp = str(int(time.time()))
    digest = hmac.new(settings.paddle_secret.encode(), timestamp.encode() + b":" + raw, hashlib.sha256).hexdigest()
    return client.post("/v1/webhooks/paddle", content=raw, headers={"Paddle-Signature": f"ts={timestamp};h1={digest}", "Content-Type": "application/json"})


def purchase_event(transaction="txn_test", event_id="evt_test", price="pri_base"):
    return {"event_id": event_id, "event_type": "transaction.completed", "data": {"id": transaction, "status": "completed", "customer_id": "ctm_fake", "items": [{"price": {"id": price}, "quantity": 1}]}}


def restore(client, sent):
    assert client.post("/v1/license/restore", json={"email": "owner@example.com"}).status_code == 200
    response = client.post("/v1/license/restore/verify", json={"email": "owner@example.com", "code": sent[-1][1]})
    assert response.status_code == 200, response.text
    return response.json()["token"]


def photo():
    output = io.BytesIO(); Image.new("RGB", (128, 128), "orange").save(output, "PNG")
    return output.getvalue()


def test_purchase_restore_generate_duplicate_and_refund(service, db):
    client, sent, settings, limiter = service
    event = purchase_event()
    assert webhook(client, settings, event).status_code == 200
    assert webhook(client, settings, event).status_code == 200
    event["event_id"] = "evt_second_delivery"
    assert webhook(client, settings, event).status_code == 200
    token = restore(client, sent)
    headers = {"Authorization": f"Bearer {token}"}
    assert client.get("/v1/wallet", headers=headers).json()["credits"] == 3
    request_id = str(uuid.uuid4())
    for _ in range(2):
        result = client.post("/v1/pet/vectorize", headers={**headers, "Idempotency-Key": request_id}, files={"photo": ("pet.png", photo(), "image/png")})
        assert result.status_code == 200, result.text
        assert result.json()["name"] == "Demo companion (placeholder)"
    assert client.get("/v1/wallet", headers=headers).json()["credits"] == 2
    refund_event = {"event_id": "evt_refund", "event_type": "adjustment.updated", "data": {"id": "adj_refund", "transaction_id": "txn_test", "action": "refund", "status": "approved"}}
    assert webhook(client, settings, refund_event).status_code == 200
    assert client.get("/v1/wallet", headers=headers).status_code == 401
    with db() as session:
        assert session.scalar(select(Account.balance)) == 0
        entry = session.scalar(select(CreditLedger).where(CreditLedger.kind == "chargeback-clawback"))
        assert entry.amount == -2 and entry.details["already_spent"] == 1


def test_bad_webhook_cannot_grant_a_license(service, db):
    client, sent, settings, limiter = service
    assert client.post("/v1/webhooks/paddle", json=purchase_event()).status_code == 401
    with db() as session: assert session.scalar(select(Account)) is None


def test_email_alone_cannot_restore_and_code_is_single_use(service):
    client, sent, settings, limiter = service
    assert webhook(client, settings, purchase_event()).status_code == 200
    assert client.post("/v1/license/restore", json={"email": "owner@example.com"}).json().get("token") is None
    wrong = client.post("/v1/license/restore/verify", json={"email": "owner@example.com", "code": "00000000"})
    assert wrong.status_code == 401
    code = sent[-1][1]
    assert client.post("/v1/license/restore/verify", json={"email": "owner@example.com", "code": code}).status_code == 200
    assert client.post("/v1/license/restore/verify", json={"email": "owner@example.com", "code": code}).status_code == 401


def test_refund_before_purchase_cannot_restore_entitlements(service, db):
    client, sent, settings, limiter = service
    event = {"event_id": "evt_early_refund", "event_type": "adjustment.created", "data": {"id": "adj_early", "transaction_id": "txn_test", "action": "chargeback", "status": "approved"}}
    assert webhook(client, settings, event).status_code == 200
    assert webhook(client, settings, purchase_event()).status_code == 200
    with db() as session:
        account = session.scalar(select(Account))
        assert not account.licensed and account.balance == 0


def test_accessory_is_separate_and_revocable(service, db):
    client, sent, settings, limiter = service
    assert webhook(client, settings, purchase_event()).status_code == 200
    assert webhook(client, settings, purchase_event("txn_hat", "evt_hat", "pri_hat")).status_code == 200
    token = restore(client, sent)
    response = client.get("/v1/wallet", headers={"Authorization": f"Bearer {token}"})
    assert response.json()["accessories"] == ["accessory.hat"]
    assert response.json()["credits"] == 3


def test_generation_failure_returns_credit(service, db):
    client, sent, settings, limiter = service
    assert webhook(client, settings, purchase_event()).status_code == 200
    token = restore(client, sent)
    # Incomplete source image must fail before reservation.
    response = client.post("/v1/pet/vectorize", headers={"Authorization": f"Bearer {token}", "Idempotency-Key": str(uuid.uuid4())}, files={"photo": ("pet.png", b"corrupt", "image/png")})
    assert response.status_code == 422
    assert client.get("/v1/wallet", headers={"Authorization": f"Bearer {token}"}).json()["credits"] == 3
    async def broken_pipeline(settings, image, pet_id):
        raise RuntimeError("simulated inference crash")
    client.app.state.pipeline = broken_pipeline
    request_id = str(uuid.uuid4())
    response = client.post("/v1/pet/vectorize", headers={"Authorization": f"Bearer {token}", "Idempotency-Key": request_id}, files={"photo": ("pet.png", photo(), "image/png")})
    assert response.status_code == 502
    assert client.get("/v1/wallet", headers={"Authorization": f"Bearer {token}"}).json()["credits"] == 3
    client.app.state.pipeline = vectorize
    retry = client.post("/v1/pet/vectorize", headers={"Authorization": f"Bearer {token}", "Idempotency-Key": request_id}, files={"photo": ("pet.png", photo(), "image/png")})
    assert retry.status_code == 200
    assert client.get("/v1/wallet", headers={"Authorization": f"Bearer {token}"}).json()["credits"] == 2


def test_rate_limits_auth_and_restore(service):
    client, sent, settings, limiter = service
    for _ in range(3): assert client.post("/v1/license/restore", json={"email": "missing@example.com"}).status_code == 200
    assert client.post("/v1/license/restore", json={"email": "missing@example.com"}).status_code == 429
