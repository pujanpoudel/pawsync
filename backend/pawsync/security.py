import hashlib
import hmac
import pathlib
import time
import uuid

import jwt
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from sqlalchemy import select

from .database import Account, LicenseSession
from .wallet import WalletError, owned_accessories


class LicenseAuthority:
    def __init__(self, private_key_path):
        key = serialization.load_pem_private_key(pathlib.Path(private_key_path).read_bytes(), password=None)
        if not isinstance(key, Ed25519PrivateKey):
            raise RuntimeError("License signing requires Ed25519")
        self.key = key
        self.public_key = key.public_key()
        self.pepper = hashlib.sha256(key.private_bytes(serialization.Encoding.Raw, serialization.PrivateFormat.Raw, serialization.NoEncryption())).digest()

    def issue(self, session, account):
        token = jwt.encode({"sub": account.id, "iss": "pawsync", "aud": "pawsync-desktop", "iat": int(time.time()), "jti": str(uuid.uuid4()), "epoch": account.token_epoch, "licensed": account.licensed, "accessories": owned_accessories(session, account.id)}, self.key, algorithm="EdDSA")
        session.add(LicenseSession(token_hash=hashlib.sha256(token.encode()).hexdigest(), account_id=account.id, epoch=account.token_epoch))
        return token

    def verify(self, session, token):
        try:
            claims = jwt.decode(token, self.public_key, algorithms=["EdDSA"], audience="pawsync-desktop", issuer="pawsync", options={"require": ["sub", "iat", "jti", "epoch", "licensed"]})
        except jwt.InvalidTokenError:
            raise WalletError("Invalid license", 401) from None
        account = session.get(Account, claims["sub"])
        stored = session.get(LicenseSession, hashlib.sha256(token.encode()).hexdigest())
        if not account or not stored or stored.account_id != account.id or not account.licensed or account.token_epoch != claims["epoch"] or stored.epoch != account.token_epoch:
            raise WalletError("License revoked or unrecognized", 401)
        return account

    def code_hash(self, email, code):
        return hmac.new(self.pepper, f"{email}:{code}".encode(), hashlib.sha256).hexdigest()


def verify_paddle(raw, header, secret, current_time=None):
    if not secret:
        raise WalletError("Payments are not configured", 503)
    try:
        pairs = [piece.strip().split("=", 1) for piece in header.split(";")]
        timestamp = next(value for key, value in pairs if key == "ts")
        signatures = [value for key, value in pairs if key == "h1"]
        if abs((time.time() if current_time is None else current_time) - int(timestamp)) > 5:
            raise ValueError()
        expected = hmac.new(secret.encode(), timestamp.encode() + b":" + raw, hashlib.sha256).hexdigest()
        if not any(hmac.compare_digest(expected, signature) for signature in signatures):
            raise ValueError()
    except (ValueError, StopIteration):
        raise WalletError("Invalid Paddle signature", 401) from None
