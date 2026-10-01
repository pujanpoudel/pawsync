import datetime as dt
import uuid

from sqlalchemy import Boolean, CheckConstraint, DateTime, ForeignKey, Integer, JSON, String, UniqueConstraint, create_engine
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker


def now():
    return dt.datetime.now(dt.timezone.utc)


def identifier():
    return str(uuid.uuid4())


class Base(DeclarativeBase):
    pass


class Account(Base):
    __tablename__ = "accounts"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=identifier)
    email: Mapped[str] = mapped_column(String(320), unique=True)
    licensed: Mapped[bool] = mapped_column(Boolean, default=False)
    balance: Mapped[int] = mapped_column(Integer, default=0)
    token_epoch: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True), default=now)
    __table_args__ = (CheckConstraint("balance >= 0"),)


class LicenseSession(Base):
    __tablename__ = "license_sessions"
    token_hash: Mapped[str] = mapped_column(String(64), primary_key=True)
    account_id: Mapped[str] = mapped_column(ForeignKey("accounts.id"), index=True)
    epoch: Mapped[int] = mapped_column(Integer)
    created_at: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True), default=now)


class Purchase(Base):
    __tablename__ = "purchases"
    id: Mapped[str] = mapped_column(String(80), primary_key=True)
    account_id: Mapped[str] = mapped_column(ForeignKey("accounts.id"), index=True)
    base: Mapped[bool] = mapped_column(Boolean, default=False)
    remaining: Mapped[int] = mapped_column(Integer, default=0)
    granted: Mapped[int] = mapped_column(Integer, default=0)
    revoked: Mapped[bool] = mapped_column(Boolean, default=False)
    skus: Mapped[list] = mapped_column(JSON, default=list)
    created_at: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True), default=now)
    __table_args__ = (CheckConstraint("remaining >= 0"),)


class CreditLedger(Base):
    __tablename__ = "credit_ledger"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=identifier)
    account_id: Mapped[str] = mapped_column(ForeignKey("accounts.id"), index=True)
    purchase_id: Mapped[str | None] = mapped_column(ForeignKey("purchases.id"))
    generation_id: Mapped[str | None] = mapped_column(String(36))
    kind: Mapped[str] = mapped_column(String(32))
    amount: Mapped[int] = mapped_column(Integer)
    details: Mapped[dict] = mapped_column(JSON, default=dict)
    created_at: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True), default=now)


class Generation(Base):
    __tablename__ = "generations"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=identifier)
    account_id: Mapped[str] = mapped_column(ForeignKey("accounts.id"), index=True)
    request_id: Mapped[str] = mapped_column(String(36))
    purchase_id: Mapped[str] = mapped_column(ForeignKey("purchases.id"))
    state: Mapped[str] = mapped_column(String(20))
    lease_until: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True), index=True)
    attempt: Mapped[int] = mapped_column(Integer, default=1)
    result: Mapped[dict | None] = mapped_column(JSON)
    __table_args__ = (UniqueConstraint("account_id", "request_id"),)


class AccessoryOwnership(Base):
    __tablename__ = "accessory_ownership"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=identifier)
    account_id: Mapped[str] = mapped_column(ForeignKey("accounts.id"), index=True)
    purchase_id: Mapped[str] = mapped_column(ForeignKey("purchases.id"))
    sku: Mapped[str] = mapped_column(String(100))
    purchased_at: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True), default=now)
    __table_args__ = (UniqueConstraint("purchase_id", "sku"),)


class WebhookEvent(Base):
    __tablename__ = "webhook_events"
    id: Mapped[str] = mapped_column(String(80), primary_key=True)
    event_type: Mapped[str] = mapped_column(String(80))
    created_at: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True), default=now)


class Revocation(Base):
    __tablename__ = "revocations"
    transaction_id: Mapped[str] = mapped_column(String(80), primary_key=True)
    adjustment_id: Mapped[str] = mapped_column(String(80))
    created_at: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True), default=now)


class RestoreCode(Base):
    __tablename__ = "restore_codes"
    email: Mapped[str] = mapped_column(String(320), primary_key=True)
    code_hash: Mapped[str] = mapped_column(String(64))
    expires_at: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True))
    attempts: Mapped[int] = mapped_column(Integer, default=0)


def connect(url):
    engine = create_engine(url, pool_pre_ping=True)
    return engine, sessionmaker(engine, expire_on_commit=False)
