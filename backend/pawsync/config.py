import json
import os
from dataclasses import dataclass, field


@dataclass(frozen=True)
class Settings:
    database_url: str = field(default_factory=lambda: os.environ.get("DATABASE_URL", "postgresql+psycopg://pawsync:pawsync@127.0.0.1:15432/pawsync"))
    redis_url: str = field(default_factory=lambda: os.environ.get("REDIS_URL", "redis://127.0.0.1:16379/0"))
    private_key_path: str = field(default_factory=lambda: os.environ.get("LICENSE_PRIVATE_KEY_PATH", ""))
    paddle_secret: str = field(default_factory=lambda: os.environ.get("PADDLE_WEBHOOK_SECRET", ""))
    paddle_api_key: str = field(default_factory=lambda: os.environ.get("PADDLE_API_KEY", ""))
    paddle_environment: str = field(default_factory=lambda: os.environ.get("PADDLE_ENVIRONMENT", "sandbox"))
    price_catalog: dict = field(default_factory=lambda: json.loads(os.environ.get("PADDLE_PRICE_CATALOG", "{}")))
    pipeline_url: str = field(default_factory=lambda: os.environ.get("PIPELINE_URL", ""))
    pipeline_token: str = field(default_factory=lambda: os.environ.get("PIPELINE_TOKEN", ""))
    pipeline_mode: str = field(default_factory=lambda: os.environ.get("PIPELINE_MODE", "provider"))
    smtp_host: str = field(default_factory=lambda: os.environ.get("SMTP_HOST", ""))
    smtp_port: int = field(default_factory=lambda: int(os.environ.get("SMTP_PORT", "587")))
    smtp_username: str = field(default_factory=lambda: os.environ.get("SMTP_USERNAME", ""))
    smtp_password: str = field(default_factory=lambda: os.environ.get("SMTP_PASSWORD", ""))
    mail_from: str = field(default_factory=lambda: os.environ.get("MAIL_FROM", "PawSync <hello@example.com>"))
    library_assets_dir: str = field(default_factory=lambda: os.environ.get("LIBRARY_ASSETS_DIR", ""))
    library_content_path: str = field(default_factory=lambda: os.environ.get("LIBRARY_CONTENT_PATH", ""))
    sentry_dsn: str = field(default_factory=lambda: os.environ.get("SENTRY_DSN", ""))
    environment: str = field(default_factory=lambda: os.environ.get("ENVIRONMENT", "development"))

    def validate(self):
        if not self.private_key_path:
            raise RuntimeError("LICENSE_PRIVATE_KEY_PATH must point to an Ed25519 PEM private key")
        if self.pipeline_mode not in {"provider", "demo"}:
            raise RuntimeError("PIPELINE_MODE must be provider or demo")
        if self.environment == "production":
            if self.pipeline_mode != "provider" or not self.pipeline_url.startswith("https://"):
                raise RuntimeError("Production requires a real HTTPS inference provider")
            if not all([self.paddle_secret, self.paddle_api_key, self.smtp_host, self.smtp_username, self.smtp_password]):
                raise RuntimeError("Production requires payment and SMTP credentials")
            if len(self.paddle_secret) < 24:
                raise RuntimeError("Webhook secret is too short")
        if self.paddle_environment not in {"sandbox", "production"}:
            raise RuntimeError("Invalid Paddle environment")
