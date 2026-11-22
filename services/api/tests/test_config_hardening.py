"""Fail-closed configuration checks for hosted deployments.

Local development keeps its permissive defaults. Staging and production must
be explicit about database driver, cookies, media backend, seed/schema
creation and host allowlists before the app is allowed to start.
"""

from __future__ import annotations

import os

import pytest

from app.core.config import Settings

_STRUCTURAL_ENV_KEYS = {
    "DATABASE_URL",
    "ENVIRONMENT",
    "SECRET_KEY",
    "CORS_ORIGINS",
    "TRUSTED_HOSTS",
    "COOKIE_SECURE",
    "COOKIE_SAMESITE",
    "COOKIE_DOMAIN",
    "ENABLE_API_DOCS",
    "TRUST_PROXY_HEADERS",
    "SAFAR_SEED",
    "SAFAR_CREATE_SCHEMA",
    "SAFAR_MEDIA_BACKEND",
    "SAFAR_STORAGE_DIR",
    "ACCESS_TOKEN_EXPIRE_MINUTES",
    "REFRESH_TOKEN_EXPIRE_DAYS",
}

BASE_HOSTED_ENV = {
    "ENVIRONMENT": "staging",
    "DATABASE_URL": "postgresql+psycopg://safar:secret@db:5432/safar",
    "SECRET_KEY": "a-unique-staging-secret-with-more-than-32-characters",
    "CORS_ORIGINS": "https://staging.example.com",
    "TRUSTED_HOSTS": "staging.example.com,localhost",
    "COOKIE_SECURE": "true",
    "SAFAR_MEDIA_BACKEND": "local",
}


def _settings(monkeypatch, **overrides) -> Settings:
    """Build Settings from a clean environment plus explicit overrides."""
    for key in list(os.environ):
        if key in _STRUCTURAL_ENV_KEYS or key.startswith("SAFAR_"):
            monkeypatch.delenv(key, raising=False)
    for key, value in {**BASE_HOSTED_ENV, **overrides}.items():
        monkeypatch.setenv(key, str(value))
    return Settings()


def test_development_keeps_local_defaults(monkeypatch):
    for key in list(os.environ):
        if key in _STRUCTURAL_ENV_KEYS or key.startswith("SAFAR_"):
            monkeypatch.delenv(key, raising=False)

    config = Settings()

    assert config.environment == "development"
    assert config.database_url.startswith("sqlite:///")
    assert config.cookie_secure is False
    assert config.auto_seed is True
    assert config.create_schema is True
    assert config.api_docs_enabled is True
    assert "testserver" in config.trusted_hosts


def test_staging_accepts_an_explicit_hardened_configuration(monkeypatch):
    config = _settings(monkeypatch)

    assert config.environment == "staging"
    assert config.database_url.startswith("postgresql+psycopg://")
    assert config.cookie_secure is True
    assert config.media_backend == "local"
    assert config.auto_seed is False
    assert config.create_schema is False
    assert config.api_docs_enabled is False
    assert "staging.example.com" in config.trusted_hosts


@pytest.mark.parametrize("environment", ["staging", "production"])
def test_hosted_environments_require_postgres_psycopg(monkeypatch, environment):
    with pytest.raises(RuntimeError, match="postgresql\\+psycopg"):
        _settings(
            monkeypatch,
            ENVIRONMENT=environment,
            DATABASE_URL="sqlite:///./safar.db",
        )


@pytest.mark.parametrize("environment", ["staging", "production"])
@pytest.mark.parametrize("forbidden_host", ["*", "testserver", "10.0.2.2"])
def test_hosted_environments_reject_test_hosts(monkeypatch, environment, forbidden_host):
    with pytest.raises(RuntimeError, match="development-only values"):
        _settings(
            monkeypatch,
            ENVIRONMENT=environment,
            TRUSTED_HOSTS=f"{forbidden_host},staging.example.com",
        )


@pytest.mark.parametrize("environment", ["staging", "production"])
def test_hosted_environments_reject_insecure_cookies(monkeypatch, environment):
    with pytest.raises(RuntimeError, match="COOKIE_SECURE"):
        _settings(
            monkeypatch,
            ENVIRONMENT=environment,
            COOKIE_SECURE="false",
        )


@pytest.mark.parametrize("environment", ["staging", "production"])
def test_hosted_environments_reject_memory_media_backend(monkeypatch, environment):
    with pytest.raises(RuntimeError, match="SAFAR_MEDIA_BACKEND=memory"):
        _settings(
            monkeypatch,
            ENVIRONMENT=environment,
            SAFAR_MEDIA_BACKEND="memory",
        )


@pytest.mark.parametrize("environment", ["staging", "production"])
@pytest.mark.parametrize("flag", ["SAFAR_SEED", "SAFAR_CREATE_SCHEMA"])
def test_hosted_environments_reject_seed_or_schema_creation(monkeypatch, environment, flag):
    with pytest.raises(RuntimeError, match="must be false"):
        _settings(monkeypatch, ENVIRONMENT=environment, **{flag: "true"})


def test_hosted_environments_reject_malformed_cors_origins(monkeypatch):
    with pytest.raises(RuntimeError, match="bare http\\(s\\) origins"):
        _settings(monkeypatch, CORS_ORIGINS="https://staging.example.com/callback")


def test_hosted_environments_reject_wildcard_cors(monkeypatch):
    with pytest.raises(RuntimeError, match="CORS_ORIGINS"):
        _settings(monkeypatch, CORS_ORIGINS="*")


def test_api_docs_can_be_explicitly_enabled_in_staging(monkeypatch):
    config = _settings(monkeypatch, ENABLE_API_DOCS="true")
    assert config.api_docs_enabled is True
