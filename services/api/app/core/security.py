import hashlib
import hmac
import secrets
from datetime import datetime, timedelta, timezone

import jwt

from .config import settings

_SCRYPT_N = 2**14
_SCRYPT_R = 8
_SCRYPT_P = 1
_SCRYPT_LEN = 32


def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    digest = hashlib.scrypt(
        password.encode("utf-8"),
        salt=salt,
        n=_SCRYPT_N,
        r=_SCRYPT_R,
        p=_SCRYPT_P,
        dklen=_SCRYPT_LEN,
    )
    return f"scrypt${_SCRYPT_N}${_SCRYPT_R}${_SCRYPT_P}${salt.hex()}${digest.hex()}"


def verify_password(password: str, stored: str) -> bool:
    try:
        algorithm, n, r, p, salt_hex, digest_hex = stored.split("$")
        if algorithm != "scrypt":
            return False
        digest = hashlib.scrypt(
            password.encode("utf-8"),
            salt=bytes.fromhex(salt_hex),
            n=int(n),
            r=int(r),
            p=int(p),
            dklen=len(bytes.fromhex(digest_hex)),
        )
        return hmac.compare_digest(digest, bytes.fromhex(digest_hex))
    except (ValueError, TypeError):
        return False


def create_access_token(
    user_id: str,
    email: str,
    session_id: str | None = None,
    token_type: str = "access",
    expires_minutes: int | None = None,
) -> str:
    now = datetime.now(timezone.utc)
    payload = {
        "sub": user_id,
        "email": email,
        "iat": now,
        "exp": now
        + timedelta(minutes=expires_minutes or settings.access_token_expire_minutes),
        "iss": "safar",
        "typ": token_type,
    }
    if session_id:
        payload["sid"] = session_id
    return jwt.encode(payload, settings.secret_key, algorithm="HS256")


def create_ws_ticket(user_id: str, session_id: str) -> str:
    return create_access_token(
        user_id, "", session_id=session_id, token_type="ws", expires_minutes=2
    )


def decode_token(token: str, token_type: str = "access") -> dict | None:
    try:
        payload = jwt.decode(
            token, settings.secret_key, algorithms=["HS256"], issuer="safar"
        )
    except jwt.PyJWTError:
        return None
    if token_type and payload.get("typ", "access") != token_type:
        return None
    return payload


def decode_access_token(token: str) -> dict | None:
    return decode_token(token, "access")


def new_refresh_secret() -> str:
    return secrets.token_urlsafe(48)


def hash_refresh_secret(secret: str) -> str:
    return hashlib.sha256(secret.encode("utf-8")).hexdigest()


def new_csrf_token() -> str:
    return secrets.token_urlsafe(32)


def hash_client_ip(ip: str | None) -> str:
    """Store a keyed digest rather than a raw IP address."""
    if not ip:
        return ""
    return hmac.new(
        settings.secret_key.encode("utf-8"), ip.encode("utf-8"), hashlib.sha256
    ).hexdigest()
