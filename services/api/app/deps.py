from __future__ import annotations

from fastapi import Header
from fastapi import HTTPException

from app.auth import AccessTokenPayload, verify_bearer_token
from app.settings import load_settings

_settings = load_settings()


def require_access_token_payload(
    authorization: str | None = Header(default=None, alias="Authorization"),
) -> AccessTokenPayload:
    if authorization is None:
        raise HTTPException(status_code=401, detail="Missing Authorization")
    return verify_bearer_token(secret=_settings.auth_secret, authorization_header=authorization)
