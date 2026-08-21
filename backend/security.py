import base64
import hashlib
import hmac
import json
import os
import secrets

from datetime import datetime, timedelta, timezone

from fastapi import HTTPException, status

_SECRET = os.getenv("JWT_SECRET") or secrets.token_urlsafe(48)
# Set JWT_SECRET in the deployment environment so access tokens survive restarts.
_ALGORITHM = "HS256"
_ACCESS_TOKEN_EXPIRES_MINUTES = int(os.getenv("ACCESS_TOKEN_EXPIRES_MINUTES", "15"))
_REFRESH_TOKEN_EXPIRES_DAYS = int(os.getenv("REFRESH_TOKEN_EXPIRES_DAYS", "30"))


def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, 310_000)
    return f"pbkdf2_sha256${salt.hex()}${digest.hex()}"


def verify_password(password: str, password_hash: str) -> bool:
    try:
        scheme, salt_hex, digest_hex = password_hash.split("$", 2)
        if scheme != "pbkdf2_sha256":
            return False
        calculated = hashlib.pbkdf2_hmac(
            "sha256", password.encode(), bytes.fromhex(salt_hex), 310_000
        )
        return hmac.compare_digest(calculated.hex(), digest_hex)
    except (TypeError, ValueError):
        return False


def _encode(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode()


def _decode(value: str) -> bytes:
    return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))


def create_access_token(user_id: str, email: str) -> str:
    header = _encode(json.dumps({"alg": _ALGORITHM, "typ": "JWT"}, separators=(",", ":")).encode())
    expires = datetime.now(timezone.utc) + timedelta(minutes=_ACCESS_TOKEN_EXPIRES_MINUTES)
    payload = _encode(json.dumps({"sub": user_id, "email": email, "exp": int(expires.timestamp())}, separators=(",", ":")).encode())
    signature = _encode(hmac.new(_SECRET.encode(), f"{header}.{payload}".encode(), hashlib.sha256).digest())
    return f"{header}.{payload}.{signature}"


def create_refresh_token() -> tuple[str, int]:
    """Create an opaque refresh token and its Unix expiry timestamp."""
    token = secrets.token_urlsafe(48)
    expires = datetime.now(timezone.utc) + timedelta(days=_REFRESH_TOKEN_EXPIRES_DAYS)
    return token, int(expires.timestamp())


def hash_refresh_token(token: str) -> str:
    """Store only a keyed digest, never the usable refresh token itself."""
    return hmac.new(_SECRET.encode(), token.encode(), hashlib.sha256).hexdigest()


def decode_access_token(token: str) -> dict:
    try:
        header, payload, signature = token.split(".")
        expected = _encode(hmac.new(_SECRET.encode(), f"{header}.{payload}".encode(), hashlib.sha256).digest())
        data = json.loads(_decode(payload))
        if not hmac.compare_digest(signature, expected) or data["exp"] < datetime.now(timezone.utc).timestamp():
            raise ValueError("Invalid token")
        return data
    except (ValueError, KeyError, json.JSONDecodeError, UnicodeDecodeError):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid or expired access token.")
