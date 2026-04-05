from __future__ import annotations

import base64
import hashlib
import hmac
import json
import time
from dataclasses import dataclass

from fastapi import HTTPException


def _b64url_encode(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")


def _b64url_decode(raw: str) -> bytes:
    padded = raw + "=" * ((4 - len(raw) % 4) % 4)
    return base64.urlsafe_b64decode(padded.encode("ascii"))


@dataclass(frozen=True)
class AccessTokenPayload:
    sub: str
    phone: str
    exp: int


def create_access_token(*, secret: str, user_id: int, phone: str, ttl_seconds: int) -> str:
    now = int(time.time())
    payload = {
        "sub": str(user_id),
        "phone": phone,
        "exp": now + max(1, int(ttl_seconds)),
    }

    # Minimal JWT-like token: base64url(header).base64url(payload).base64url(signature)
    header = {"alg": "HS256", "typ": "JWT"}
    header_b64 = _b64url_encode(json.dumps(header, separators=(",", ":")).encode("utf-8"))
    payload_b64 = _b64url_encode(
        json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8")
    )

    signing_input = f"{header_b64}.{payload_b64}".encode("ascii")
    sig = hmac.new(secret.encode("utf-8"), signing_input, hashlib.sha256).digest()
    sig_b64 = _b64url_encode(sig)

    return f"{header_b64}.{payload_b64}.{sig_b64}"


def verify_bearer_token(*, secret: str, authorization_header: str) -> AccessTokenPayload:
    if not authorization_header:
        raise HTTPException(status_code=401, detail="Missing Authorization header")

    raw = authorization_header.strip()
    if raw.lower().startswith("bearer "):
        token = raw[7:].strip()
    else:
        token = raw

    parts = token.split(".")
    if len(parts) != 3:
        raise HTTPException(status_code=401, detail="Invalid token")

    header_b64, payload_b64, sig_b64 = parts
    signing_input = f"{header_b64}.{payload_b64}".encode("ascii")
    expected_sig = hmac.new(secret.encode("utf-8"), signing_input, hashlib.sha256).digest()

    try:
        provided_sig = _b64url_decode(sig_b64)
    except Exception as exc:
        raise HTTPException(status_code=401, detail="Invalid token") from exc

    if not hmac.compare_digest(expected_sig, provided_sig):
        raise HTTPException(status_code=401, detail="Invalid token")

    try:
        payload_raw = _b64url_decode(payload_b64)
        payload = json.loads(payload_raw.decode("utf-8"))
    except Exception as exc:
        raise HTTPException(status_code=401, detail="Invalid token") from exc

    sub = str(payload.get("sub", ""))
    phone = str(payload.get("phone", ""))
    exp = payload.get("exp")
    if not sub or not phone or not isinstance(exp, int):
        raise HTTPException(status_code=401, detail="Invalid token")

    now = int(time.time())
    if exp <= now:
        raise HTTPException(status_code=401, detail="Token expired")

    return AccessTokenPayload(sub=sub, phone=phone, exp=exp)
