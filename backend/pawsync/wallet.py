"""All balances and purchase lots mutate under an account row lock in one transaction."""
import datetime as dt

from sqlalchemy import select

from .database import Account, AccessoryOwnership, CreditLedger, Generation, Purchase, Revocation, now


class WalletError(Exception):
    def __init__(self, message, status=409):
        self.message, self.status = message, status
        super().__init__(message)


def lock_account(session, account_id):
    account = session.scalar(select(Account).where(Account.id == account_id).with_for_update())
    if not account:
        raise WalletError("Account not found", 401)
    return account


def ledger(session, account, kind, amount, purchase=None, generation=None, **details):
    session.add(CreditLedger(account_id=account.id, kind=kind, amount=amount,
                             purchase_id=purchase.id if purchase else None,
                             generation_id=generation.id if generation else None, details=details))


def fulfill(session, account, transaction_id, items):
    """Caller holds account lock. Transaction id protects against distinct duplicate events."""
    existing = session.get(Purchase, transaction_id)
    if existing:
        return existing
    credits = sum(item["credits"] * item["quantity"] for item in items)
    is_base = any(item["sku"] == "base" for item in items)
    revoked = session.get(Revocation, transaction_id) is not None
    purchase = Purchase(id=transaction_id, account_id=account.id, base=is_base,
                        remaining=0 if revoked else credits, granted=credits, revoked=revoked,
                        skus=[item["sku"] for item in items])
    session.add(purchase); session.flush()
    if revoked:
        account.licensed = False; account.token_epoch += 1
        ledger(session, account, "chargeback-clawback", 0, purchase, requested=credits, reclaimed=0, already_spent=0, reason="refund_before_fulfillment")
        return purchase
    account.balance += credits
    ledger(session, account, "purchase", credits, purchase)
    if is_base:
        account.licensed = True
    for item in items:
        if item["sku"].startswith(("accessory.","collection.")):
            session.add(AccessoryOwnership(account_id=account.id, purchase_id=transaction_id, sku=item["sku"]))
    return purchase


def revoke(session, account, purchase, adjustment_id):
    if purchase.revoked:
        return
    reclaimed = purchase.remaining
    purchase.remaining = 0; purchase.revoked = True
    account.balance -= reclaimed
    account.licensed = False; account.token_epoch += 1
    # Pending reservations from this lot are cancelled, so late inference results cannot spend.
    pending = session.scalars(select(Generation).where(Generation.purchase_id == purchase.id, Generation.state == "pending").with_for_update()).all()
    for generation in pending:
        generation.state = "refunded"
        ledger(session, account, "refund", 0, purchase, generation, reason="purchase_revoked")
    ledger(session, account, "chargeback-clawback", -reclaimed, purchase,
           requested=purchase.granted, reclaimed=reclaimed,
           already_spent=purchase.granted - reclaimed - len(pending), cancelled_reservations=len(pending), adjustment_id=adjustment_id)


def reserve(session, account_id, request_id):
    account = lock_account(session, account_id)
    generation = session.scalar(select(Generation).where(Generation.account_id == account_id, Generation.request_id == request_id).with_for_update())
    if generation and generation.state == "succeeded":
        return generation
    if not account.licensed:
        raise WalletError("An active base license is required", 403)
    if generation and generation.state == "pending":
        raise WalletError("This generation is still processing. Retry shortly with the same request ID.")
    if account.balance < 1:
        raise WalletError("No credits remaining. Buy a top-up to continue.", 402)
    lot = session.scalar(select(Purchase).where(Purchase.account_id == account_id, Purchase.revoked.is_(False), Purchase.remaining > 0).order_by(Purchase.created_at, Purchase.id).with_for_update().limit(1))
    if not lot:
        raise WalletError("Credit ledger invariant failed", 500)
    account.balance -= 1; lot.remaining -= 1
    if generation:
        generation.state = "pending"; generation.purchase_id = lot.id
        generation.attempt += 1; generation.result = None
        generation.lease_until = now() + dt.timedelta(seconds=90)
    else:
        generation = Generation(account_id=account_id, request_id=request_id, purchase_id=lot.id,
                                state="pending", lease_until=now() + dt.timedelta(seconds=90))
        session.add(generation)
    session.flush()
    ledger(session, account, "reserve", -1, lot, generation, attempt=generation.attempt)
    return generation


def refund(session, generation_id, attempt, reason):
    candidate = session.get(Generation, generation_id)
    if not candidate:
        return False
    account = lock_account(session, candidate.account_id)
    generation = session.scalar(select(Generation).where(Generation.id == generation_id).with_for_update().execution_options(populate_existing=True))
    if generation.state != "pending" or generation.attempt != attempt:
        return False
    lot = session.get(Purchase, generation.purchase_id)
    amount = 0 if lot.revoked else 1
    account.balance += amount; lot.remaining += amount
    generation.state = "refunded"
    ledger(session, account, "refund", amount, lot, generation, reason=reason, attempt=attempt)
    return True


def commit(session, generation_id, attempt, result):
    candidate = session.get(Generation, generation_id)
    account = lock_account(session, candidate.account_id)
    generation = session.scalar(select(Generation).where(Generation.id == generation_id).with_for_update().execution_options(populate_existing=True))
    if generation.state != "pending" or generation.attempt != attempt or generation.lease_until < now():
        raise WalletError("Generation lease expired or was revoked. Retry with the same request ID.")
    lot = session.get(Purchase, generation.purchase_id)
    if lot.revoked or not account.licensed:
        raise WalletError("Purchase was revoked", 403)
    generation.state = "succeeded"; generation.result = result
    # Balance was deducted by reserve; commit is a zero-delta spend audit entry.
    ledger(session, account, "spend", 0, lot, generation, attempt=attempt)


def recover_expired(session_factory):
    with session_factory() as session:
        pending = [(g.id, g.attempt) for g in session.scalars(select(Generation).where(Generation.state == "pending", Generation.lease_until < now())).all()]
    recovered = 0
    for generation_id, attempt in pending:
        with session_factory.begin() as session:
            recovered += int(refund(session, generation_id, attempt, "expired_lease"))
    return recovered


def owned_accessories(session, account_id):
    return sorted(set(session.scalars(select(AccessoryOwnership.sku).join(Purchase, Purchase.id == AccessoryOwnership.purchase_id).where(AccessoryOwnership.account_id == account_id, Purchase.revoked.is_(False))).all()))
