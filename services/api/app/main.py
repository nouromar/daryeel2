from __future__ import annotations

import json
import logging
import os
import time
import uuid

from fastapi import Body
from fastapi import Depends
from fastapi import FastAPI
from fastapi import Header
from fastapi import HTTPException
from fastapi import Query
from fastapi import Request
from fastapi.responses import JSONResponse
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.auth import create_access_token, verify_bearer_token
from app.db import get_db
from app.models import User
from app.routers.pharmacy import router as pharmacy_router
from app.settings import load_settings

app = FastAPI(title="Daryeel2 API", version="0.1.0")

app.include_router(pharmacy_router)

_settings = load_settings()

if not logging.getLogger().handlers:
    logging.basicConfig(level=logging.INFO)

_request_logger = logging.getLogger("daryeel.request")


@app.middleware("http")
async def request_id_and_access_log(request: Request, call_next):
    start_time = time.perf_counter()

    request_id = request.headers.get("x-request-id") or uuid.uuid4().hex
    session_id = request.headers.get("x-daryeel-session-id")
    schema_version = request.headers.get("x-daryeel-schema-version")
    config_snapshot = request.headers.get("x-daryeel-config-snapshot")

    try:
        response = await call_next(request)
    except HTTPException as exc:
        response = JSONResponse(status_code=exc.status_code, content={"detail": exc.detail})
    except Exception as exc:
        latency_ms = int((time.perf_counter() - start_time) * 1000)
        _request_logger.error(
            json.dumps(
                {
                    "eventName": "backend.request.unhandled_exception",
                    "service": "api",
                    "requestId": request_id,
                    "sessionId": session_id,
                    "schemaVersion": schema_version,
                    "configSnapshot": config_snapshot,
                    "method": request.method,
                    "path": request.url.path,
                    "statusCode": 500,
                    "latencyMs": latency_ms,
                    "errorType": type(exc).__name__,
                }
            )
        )
        response = JSONResponse(status_code=500, content={"detail": "Internal Server Error"})

    response.headers["x-request-id"] = request_id

    latency_ms = int((time.perf_counter() - start_time) * 1000)
    _request_logger.info(
        json.dumps(
            {
                "eventName": "backend.request.completed",
                "service": "api",
                "requestId": request_id,
                "sessionId": session_id,
                "schemaVersion": schema_version,
                "configSnapshot": config_snapshot,
                "method": request.method,
                "path": request.url.path,
                "statusCode": response.status_code,
                "latencyMs": latency_ms,
            }
        )
    )

    return response


@app.get("/health")
def health() -> dict:
    return {
        "status": "ok",
        "env": os.getenv("API_APP_ENV", "local"),
    }


def _require_dev_otp_enabled() -> None:
    if not _settings.is_dev_env():
        # Hide in prod for now.
        raise HTTPException(status_code=404, detail="Not found")


def _normalize_phone(phone: str) -> str:
    raw = phone.strip()
    if not raw:
        raise HTTPException(status_code=400, detail="phone is required")

    # Accept E.164 with or without '+' prefix.
    p = raw
    if p.startswith("+"):
        digits = p[1:]
    else:
        digits = p

    if not digits.isdigit():
        raise HTTPException(
            status_code=400,
            detail="phone must be E.164 digits (with optional '+' prefix)",
        )

    # E.164 allows up to 15 digits after '+'.
    if len(digits) < 8 or len(digits) > 15:
        raise HTTPException(status_code=400, detail="phone must be E.164")

    return f"+{digits}"


def _validate_otp(code: str) -> None:
    c = code.strip()
    if len(c) != 6 or not c.isdigit():
        raise HTTPException(status_code=400, detail="otp must be a 6-digit code")


@app.post("/dev/auth/otp/start")
def dev_otp_start(
    payload: dict = Body(...),
) -> dict:
    _require_dev_otp_enabled()
    phone = _normalize_phone(str(payload.get("phone", "")))
    # No SMS integration yet; this just acknowledges the phone.
    return {"ok": True, "phone": phone}


@app.post("/dev/auth/otp/verify")
def dev_otp_verify(
    payload: dict = Body(...),
    db: Session = Depends(get_db),
) -> dict:
    _require_dev_otp_enabled()
    phone = _normalize_phone(str(payload.get("phone", "")))
    otp = str(payload.get("otp", ""))
    _validate_otp(otp)

    user = db.scalar(select(User).where(User.phone == phone))
    is_new_user = False
    if user is None:
        user = User(phone=phone)
        db.add(user)
        try:
            db.commit()
            db.refresh(user)
            is_new_user = True
        except IntegrityError:
            # Another request likely created the same phone concurrently.
            db.rollback()
            user = db.scalar(select(User).where(User.phone == phone))
            if user is None:
                raise

    token = create_access_token(
        secret=_settings.auth_secret,
        user_id=user.id,
        phone=user.phone,
        ttl_seconds=_settings.access_token_ttl_seconds,
    )
    return {
        "accessToken": token,
        "tokenType": "Bearer",
        "isNewUser": is_new_user,
        "user": {"id": user.id, "phone": user.phone},
    }


@app.get("/v1/me")
def me(
    authorization: str | None = Header(default=None, alias="Authorization"),
) -> dict:
    if authorization is None:
        raise HTTPException(status_code=401, detail="Missing Authorization")

    payload = verify_bearer_token(secret=_settings.auth_secret, authorization_header=authorization)
    return {
        "user": {
            "id": payload.sub,
            "phone": payload.phone,
        },
        "exp": payload.exp,
    }


_SERVICE_DEFINITIONS = [
    {
        "id": "ambulance",
        "title": "Ambulance",
        "subtitle": "Emergency transport",
        "icon": "ambulance",
        "route": {
            "route": "customer.schema_screen",
            "value": {
                "screenId": "customer_request_ambulance",
                "title": "Ambulance",
            },
        },
        "detailRoute": {
            "route": "customer.schema_screen",
            "value": {
                "screenId": "customer_service_detail",
                "title": "Service",
                "params": {"id": "ambulance"},
            },
        },
    },
    {
        "id": "home_visit",
        "title": "Home visit",
        "subtitle": "Doctor comes to you",
        "icon": "house",
        "route": {
            "route": "customer.schema_screen",
            "value": {
                "screenId": "customer_request_home_visit",
                "title": "Home Visit",
            },
        },
        "detailRoute": {
            "route": "customer.schema_screen",
            "value": {
                "screenId": "customer_service_detail",
                "title": "Service",
                "params": {"id": "home_visit"},
            },
        },
    },
    {
        "id": "pharmacy",
        "title": "Pharmacy",
        "subtitle": "Order medicine",
        "icon": "pill",
        "route": {
            "route": "customer.schema_screen",
            "value": {
                "screenId": "pharmacy_shop",
                "title": "Pharmacy",
                "chromePreset": "pharmacy_cart_badge",
            },
        },
        "detailRoute": {
            "route": "customer.schema_screen",
            "value": {
                "screenId": "customer_service_detail",
                "title": "Service",
                "params": {"id": "pharmacy"},
            },
        },
    },
]



@app.get("/v1/service-definitions")
def list_service_definitions(
    q: str | None = Query(default=None, min_length=1, max_length=50),
) -> dict:
    # Non-paginated variant for `RemoteQuery` demos.
    items = _SERVICE_DEFINITIONS
    if q:
        query = q.strip().lower()
        if query:
            items = [
                item
                for item in _SERVICE_DEFINITIONS
                if query in str(item.get("title", "")).lower()
                or query in str(item.get("subtitle", "")).lower()
            ]
    return {"items": items}


@app.get("/v1/service-definitions/paged")
def list_service_definitions_paged(
    cursor: str | None = Query(default=None),
    limit: int = Query(default=10, ge=1, le=50),
    q: str | None = Query(default=None, min_length=1, max_length=50),
) -> dict:
    # Cursor is a stringified offset.
    items_source = _SERVICE_DEFINITIONS
    if q:
        query = q.strip().lower()
        if query:
            items_source = [
                item
                for item in _SERVICE_DEFINITIONS
                if query in str(item.get("title", "")).lower()
                or query in str(item.get("subtitle", "")).lower()
            ]

    start = 0
    if cursor:
        try:
            start = max(0, int(cursor))
        except ValueError:
            start = 0

    end = start + limit
    items = items_source[start:end]
    next_cursor = str(end) if end < len(items_source) else None

    return {
        "items": items,
        "next": {"cursor": next_cursor},
    }


@app.get("/v1/service-definitions/detail")
def get_service_definition_detail(
    id: str = Query(min_length=1, max_length=64),
) -> dict:
    # Detail endpoint for list->detail demos.
    match = next((x for x in _SERVICE_DEFINITIONS if x.get("id") == id), None)
    if match is None:
        return {"items": []}
    return {"items": [match]}
