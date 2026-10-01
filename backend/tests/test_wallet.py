import datetime as dt
import threading
import uuid
from concurrent.futures import ThreadPoolExecutor

import pytest
from sqlalchemy import func, select

from pawsync.database import Account, CreditLedger, Generation, Purchase, now
from pawsync.wallet import WalletError, commit, fulfill, lock_account, recover_expired, refund, reserve, revoke

pytestmark = pytest.mark.postgres


def purchased(db, credits=3):
    with db.begin() as session:
        account = Account(email=f"{uuid.uuid4()}@example.com")
        session.add(account); session.flush()
        fulfill(session, account, "txn_" + uuid.uuid4().hex, [{"sku": "base", "credits": credits, "quantity": 1}])
        return account.id


def invariant(db, account_id):
    with db() as session:
        account = session.get(Account, account_id)
        total = session.scalar(select(func.coalesce(func.sum(CreditLedger.amount), 0)).where(CreditLedger.account_id == account_id))
        lots = session.scalar(select(func.coalesce(func.sum(Purchase.remaining), 0)).where(Purchase.account_id == account_id))
        assert account.balance == total == lots
        assert account.balance >= 0
        return account.balance


def test_reserve_commit_idempotent(db):
    account = purchased(db)
    request = str(uuid.uuid4())
    with db.begin() as session: generation = reserve(session, account, request)
    with db.begin() as session: commit(session, generation.id, generation.attempt, {"id": generation.id})
    with db.begin() as session: cached = reserve(session, account, request)
    assert cached.state == "succeeded" and cached.result == {"id": generation.id}
    assert invariant(db, account) == 2


def test_failure_refunds_once_and_retry_spends_once(db):
    account = purchased(db)
    request = str(uuid.uuid4())
    with db.begin() as session: first = reserve(session, account, request)
    with db.begin() as session: assert refund(session, first.id, 1, "test")
    with db.begin() as session: assert not refund(session, first.id, 1, "test")
    assert invariant(db, account) == 3
    with db.begin() as session: second = reserve(session, account, request)
    assert second.attempt == 2
    with db.begin() as session: assert not refund(session, first.id, 1, "late_old_attempt")
    with db.begin() as session: commit(session, second.id, 2, {"ok": True})
    assert invariant(db, account) == 2


def test_parallel_requests_cannot_double_spend_last_credit(db):
    account = purchased(db, credits=1)
    barrier = threading.Barrier(8)

    def attempt(_):
        barrier.wait()
        try:
            with db.begin() as session: reserve(session, account, str(uuid.uuid4()))
            return True
        except WalletError as error:
            assert error.status == 402
            return False

    with ThreadPoolExecutor(max_workers=8) as pool:
        assert sum(pool.map(attempt, range(8))) == 1
    assert invariant(db, account) == 0


def test_parallel_duplicate_generation_reserves_once(db):
    account = purchased(db)
    request = str(uuid.uuid4())
    barrier = threading.Barrier(4)

    def attempt(_):
        barrier.wait()
        try:
            with db.begin() as session: reserve(session, account, request)
            return True
        except WalletError as error:
            assert error.status == 409
            return False

    with ThreadPoolExecutor(max_workers=4) as pool: assert sum(pool.map(attempt, range(4))) == 1
    assert invariant(db, account) == 2


def test_crashed_request_lease_recovery(db):
    account = purchased(db)
    with db.begin() as session:
        generation = reserve(session, account, str(uuid.uuid4()))
        generation.lease_until = now() - dt.timedelta(seconds=1)
    assert recover_expired(db) == 1
    assert recover_expired(db) == 0
    assert invariant(db, account) == 3


def test_refund_floors_at_zero_and_does_not_claw_future_purchase(db):
    account_id = purchased(db)
    for _ in range(3):
        with db.begin() as session: generation = reserve(session, account_id, str(uuid.uuid4()))
        with db.begin() as session: commit(session, generation.id, 1, {})
    with db.begin() as session:
        account = lock_account(session, account_id)
        original = session.scalar(select(Purchase).where(Purchase.account_id == account_id))
        revoke(session, account, original, "adj_1")
    assert invariant(db, account_id) == 0
    with db.begin() as session:
        account = lock_account(session, account_id)
        fulfill(session, account, "txn_new", [{"sku": "base", "credits": 3, "quantity": 1}])
    assert invariant(db, account_id) == 3
    with db() as session:
        clawback = session.scalar(select(CreditLedger).where(CreditLedger.kind == "chargeback-clawback"))
        assert clawback.amount == 0 and clawback.details["already_spent"] == 3


def test_refund_cancels_inflight_generation_without_resurrecting_credits(db):
    account_id = purchased(db)
    with db.begin() as session: generation = reserve(session, account_id, str(uuid.uuid4()))
    with db.begin() as session:
        account = lock_account(session, account_id)
        purchase = session.get(Purchase, generation.purchase_id)
        revoke(session, account, purchase, "adj_2")
    with pytest.raises(WalletError):
        with db.begin() as session: commit(session, generation.id, 1, {})
    with db.begin() as session: assert not refund(session, generation.id, 1, "late_refund")
    assert invariant(db, account_id) == 0


def test_balance_rollback_is_atomic(db):
    account = purchased(db)
    with pytest.raises(RuntimeError):
        with db.begin() as session:
            reserve(session, account, str(uuid.uuid4()))
            raise RuntimeError("simulated database failure")
    assert invariant(db, account) == 3
    with db() as session: assert session.scalar(select(func.count()).select_from(Generation)) == 0
