import argparse
import base64
import json
import pathlib

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from sqlalchemy import select, text

from .config import Settings
from .database import Account, Base, connect
from .security import LicenseAuthority
from .wallet import fulfill, recover_expired


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["init-db", "keygen", "recover", "dev-license"])
    parser.add_argument("--output", default="data/license-private.pem")
    parser.add_argument("--email", default="developer@example.com")
    args = parser.parse_args()
    if args.command == "keygen":
        path = pathlib.Path(args.output)
        path.parent.mkdir(parents=True, exist_ok=True)
        key = Ed25519PrivateKey.generate()
        # Exclusive create prevents accidental replacement of the signing identity.
        with path.open("xb") as output:
            output.write(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
        path.chmod(0o600)
        print("Public key (base64, raw Ed25519; bundle this in Config.json):")
        print(base64.b64encode(key.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)).decode())
        return
    settings = Settings()
    engine, factory = connect(settings.database_url)
    if args.command == "init-db":
        Base.metadata.create_all(engine)
        with engine.begin() as connection:
            connection.execute(text("""CREATE OR REPLACE FUNCTION prevent_ledger_mutation() RETURNS trigger AS $$
            BEGIN RAISE EXCEPTION 'credit_ledger is append-only'; END; $$ LANGUAGE plpgsql"""))
            connection.execute(text("DROP TRIGGER IF EXISTS ledger_append_only ON credit_ledger"))
            connection.execute(text("CREATE TRIGGER ledger_append_only BEFORE UPDATE OR DELETE ON credit_ledger FOR EACH ROW EXECUTE FUNCTION prevent_ledger_mutation()"))
        print("Initialized PostgreSQL schema and append-only ledger guard.")
    elif args.command == "recover":
        print(f"Recovered {recover_expired(factory)} expired generation reservations.")
    else:
        if settings.environment != "development": raise SystemExit("dev-license is forbidden outside development")
        authority = LicenseAuthority(settings.private_key_path)
        with factory.begin() as session:
            account = session.scalar(select(Account).where(Account.email == args.email).with_for_update())
            if account is None: account = Account(email=args.email); session.add(account); session.flush()
            fulfill(session, account, "dev-license-" + account.id, [{"sku": "base", "credits": 3, "quantity": 1}])
            token = authority.issue(session, account)
        # Write to a restricted file, never log bearer tokens to the terminal.
        destination = pathlib.Path("data/dev-license.json")
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(json.dumps({"token": token}) + "\n"); destination.chmod(0o600)
        print(f"Development license written to {destination}. Use the keychain import helper; do not commit it.")
    engine.dispose()


if __name__ == "__main__": main()
