import os
from pathlib import Path
from urllib.parse import urlsplit

from dotenv import load_dotenv

API_DIR = Path(__file__).resolve().parents[2]
REPO_ROOT = API_DIR.parents[1]

env_file = os.getenv("SAFAR_ENV_FILE")
if env_file:
    p = Path(env_file)
    if p.is_absolute() and p.exists():
        env_path = p
    elif (REPO_ROOT / p).exists():
        env_path = (REPO_ROOT / p).resolve()
    elif (Path.cwd() / p).exists():
        env_path = (Path.cwd() / p).resolve()
    else:
        env_path = (REPO_ROOT / p).resolve()
    load_dotenv(env_path, override=True)
else:
    load_dotenv(API_DIR / ".env")
    load_dotenv(REPO_ROOT / ".env")


def _bool(name: str, default: bool) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


RESTRICTED_ENVIRONMENTS = {"production", "staging"}
# Localhost is permitted for in-container probe requests. Test/emulator hosts
# and wildcard allowlists must never reach a hosted deployment.
FORBIDDEN_HOSTS = {"*", "testserver", "10.0.2.2"}


class Settings:
    def __init__(self) -> None:
        default_db = f"sqlite:///{(API_DIR / 'safar.db').as_posix()}"
        self.database_url: str = os.getenv("DATABASE_URL", default_db)
        self.environment: str = os.getenv("ENVIRONMENT", "development")
        restricted = self.environment in RESTRICTED_ENVIRONMENTS
        if restricted and not self.database_url.startswith("postgresql+psycopg://"):
            raise RuntimeError(
                "DATABASE_URL must use postgresql+psycopg:// in production/staging; "
                "SQLite and other drivers are not supported there."
            )
        default_secret = "safar-dev-secret-change-me-in-production"
        self.secret_key: str = os.getenv("SECRET_KEY", default_secret)
        if restricted and (
            self.secret_key == default_secret or len(self.secret_key) < 32
        ):
            raise RuntimeError(
                "SECRET_KEY must be set to a unique value of at least 32 characters in production/staging."
            )
        raw_storage = os.getenv("SAFAR_STORAGE_DIR")
        if raw_storage:
            p = Path(raw_storage)
            self.storage_dir: Path = p if p.is_absolute() else (REPO_ROOT / p).resolve()
        else:
            self.storage_dir = API_DIR / "storage"
        self.media_backend: str = os.getenv("SAFAR_MEDIA_BACKEND", "local").strip().lower()
        if self.media_backend not in {"local", "memory"}:
            raise RuntimeError(
                "SAFAR_MEDIA_BACKEND must be 'local' or 'memory'; cloud adapters are not enabled."
            )
        if restricted and self.media_backend == "memory":
            raise RuntimeError(
                "SAFAR_MEDIA_BACKEND=memory is not allowed in production/staging"
            )
        self.email_provider: str = os.getenv("SAFAR_EMAIL_PROVIDER", "disabled").strip().lower()
        if self.email_provider != "disabled":
            raise RuntimeError(
                "SAFAR_EMAIL_PROVIDER must be 'disabled'; no transactional email provider is wired."
            )
        self.access_token_expire_minutes: int = int(
            os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", "15")
        )
        self.refresh_token_expire_days: int = int(
            os.getenv("REFRESH_TOKEN_EXPIRE_DAYS", "30")
        )
        self.cookie_secure: bool = _bool("COOKIE_SECURE", restricted)
        if restricted and not self.cookie_secure:
            raise RuntimeError(
                "COOKIE_SECURE must be true in production/staging; hosted deployments require HTTPS."
            )
        self.cookie_samesite: str = os.getenv("COOKIE_SAMESITE", "lax").strip().lower()
        if self.cookie_samesite not in {"lax", "strict", "none"}:
            raise RuntimeError("COOKIE_SAMESITE must be one of: lax, strict, none")
        if self.cookie_samesite == "none" and not self.cookie_secure:
            raise RuntimeError("COOKIE_SAMESITE=none requires COOKIE_SECURE=true")
        self.cookie_domain: str | None = os.getenv("COOKIE_DOMAIN") or None
        self.access_cookie = "safar_access"
        self.refresh_cookie = "safar_refresh"
        self.csrf_cookie = "safar_csrf"
        self.csrf_header = "X-CSRF-Token"
        self.request_id_header = "X-Request-Id"
        # 10.0.2.2 is the Android emulator's alias for the host machine.
        self.trusted_hosts = [
            host.strip()
            for host in os.getenv(
                "TRUSTED_HOSTS", "localhost,127.0.0.1,testserver,10.0.2.2"
            ).split(",")
            if host.strip()
        ]
        if restricted:
            if not self.trusted_hosts:
                raise RuntimeError("TRUSTED_HOSTS must not be empty in production/staging")
            forbidden = sorted(set(self.trusted_hosts) & FORBIDDEN_HOSTS)
            if forbidden:
                raise RuntimeError(
                    "TRUSTED_HOSTS contains development-only values in production/staging: "
                    + ", ".join(forbidden)
                )
        self.max_request_bytes: int = int(os.getenv("MAX_REQUEST_BYTES", "26214400"))
        self.log_level: str = os.getenv("LOG_LEVEL", "INFO").upper()
        self.release: str = os.getenv("RELEASE", "safar-1.0.0")
        self.sentry_dsn: str | None = os.getenv("SENTRY_DSN") or None
        self.slow_query_threshold_ms: float = float(os.getenv("SLOW_QUERY_THRESHOLD_MS", "500.0"))
        self.alert_webhook_url: str | None = os.getenv("ALERT_WEBHOOK_URL") or None
        self.trust_proxy_headers: bool = _bool("TRUST_PROXY_HEADERS", False)
        self.api_docs_enabled: bool = _bool("ENABLE_API_DOCS", not restricted)
        self.auth_rate_limit_per_minute: int = int(
            os.getenv("AUTH_RATE_LIMIT_PER_MINUTE", "10")
        )
        self.companion_rate_limit_per_minute: int = int(
            os.getenv("COMPANION_RATE_LIMIT_PER_MINUTE", "20")
        )
        self.upload_rate_limit_per_minute: int = int(
            os.getenv("UPLOAD_RATE_LIMIT_PER_MINUTE", "30")
        )
        origins = os.getenv("CORS_ORIGINS", "http://localhost:3000")
        self.cors_origins = [o.strip() for o in origins.split(",") if o.strip()]
        if restricted:
            if not self.cors_origins or "*" in self.cors_origins:
                raise RuntimeError(
                    "CORS_ORIGINS must list explicit origins in production/staging; '*' is not allowed "
                    "because cookie authentication requires credentials."
                )
            for origin in self.cors_origins:
                parts = urlsplit(origin)
                if (
                    parts.scheme not in {"http", "https"}
                    or not parts.netloc
                    or parts.path not in {"", "/"}
                    or parts.query
                    or parts.fragment
                ):
                    raise RuntimeError(
                        "CORS_ORIGINS entries must be bare http(s) origins without paths or wildcards."
                    )
        # The OpenAI settings are intentionally inert. No service reads them;
        # wiring an LLM requires a separate change and explicit approval.
        self.openai_api_key: str | None = os.getenv("OPENAI_API_KEY") or None
        self.openai_model: str = os.getenv("OPENAI_MODEL", "gpt-4o-mini")
        # Optional providers. Everything defaults to off or local so the
        # default deployment makes no outbound AI calls.
        self.weather_provider: str = os.getenv(
            "SAFAR_WEATHER_PROVIDER", "disabled"
        ).strip().lower()
        if self.weather_provider not in {"disabled", "open-meteo"}:
            raise RuntimeError(
                "SAFAR_WEATHER_PROVIDER must be 'disabled' or 'open-meteo'."
            )
        self.link_fetch_enabled: bool = _bool("SAFAR_LINK_FETCH_ENABLED", False)
        self.ocr_enabled: bool = _bool("SAFAR_OCR_ENABLED", True)
        self.provider_timeout_seconds: float = float(
            os.getenv("SAFAR_PROVIDER_TIMEOUT_SECONDS", "3")
        )
        self.link_cache_ttl_seconds: int = int(
            os.getenv("SAFAR_LINK_CACHE_TTL_SECONDS", "900")
        )
        self.weather_cache_ttl_seconds: int = int(
            os.getenv("SAFAR_WEATHER_CACHE_TTL_SECONDS", "1800")
        )
        self.link_rate_limit_per_minute: int = int(
            os.getenv("SAFAR_LINK_RATE_LIMIT_PER_MINUTE", "10")
        )
        self.weather_rate_limit_per_minute: int = int(
            os.getenv("SAFAR_WEATHER_RATE_LIMIT_PER_MINUTE", "60")
        )
        self.ocr_max_image_bytes: int = int(
            os.getenv("SAFAR_OCR_MAX_IMAGE_BYTES", "10485760")
        )
        self.auto_seed: bool = _bool("SAFAR_SEED", not restricted)
        self.create_schema: bool = _bool("SAFAR_CREATE_SCHEMA", not restricted)
        if restricted and (self.auto_seed or self.create_schema):
            raise RuntimeError(
                "SAFAR_SEED and SAFAR_CREATE_SCHEMA must be false in production/staging; "
                "run alembic upgrade head as a separate release step."
            )
        self.rate_limit_per_minute: int = int(os.getenv("RATE_LIMIT_PER_MINUTE", "240"))
        self.retention_session_days: int = int(os.getenv("RETENTION_SESSION_DAYS", "30"))
        self.retention_invitation_days: int = int(os.getenv("RETENTION_INVITATION_DAYS", "30"))
        self.retention_companion_days: int = int(os.getenv("RETENTION_COMPANION_DAYS", "30"))
        self.retention_notification_days: int = int(os.getenv("RETENTION_NOTIFICATION_DAYS", "180"))
        self.retention_audit_days: int = int(os.getenv("RETENTION_AUDIT_DAYS", "365"))
        self.retention_offline_days: int = int(os.getenv("RETENTION_OFFLINE_DAYS", "7"))
        self.policy_version: str = "2026-01"

    @property
    def is_production(self) -> bool:
        return self.environment == "production"

    @property
    def is_staging(self) -> bool:
        return self.environment == "staging"


settings = Settings()
