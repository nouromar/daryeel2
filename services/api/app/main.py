from __future__ import annotations

import json
import logging
import os
import time
import uuid
from datetime import UTC, datetime, timedelta

from fastapi import Body
from fastapi import Depends
from fastapi import FastAPI
from fastapi import Header
from fastapi import HTTPException
from fastapi import Query
from fastapi import Request
from fastapi.responses import JSONResponse
from sqlalchemy import func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.auth import create_access_token, hash_token, verify_bearer_token
from app.db import get_db
from app.ids import new_uuid7
from app.models import AuthChallenge
from app.models import AuthFactor
from app.models import AuthIdentity
from app.models import AuthSession
from app.models import CustomerProfile
from app.models import Person
from app.models import ServiceDefinition
from app.models import User
from app.routers.pharmacy import router as pharmacy_router
from app.routers.requests import router as requests_router
from app.routers.notifications import router as notifications_router
from app.settings import load_settings

app = FastAPI(title="Daryeel2 API", version="0.1.0")

app.include_router(pharmacy_router)
app.include_router(requests_router)
app.include_router(notifications_router)

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


def _now_utc() -> datetime:
    return datetime.now(UTC)


def _ensure_customer_person_link(
    db: Session,
    user: User,
    *,
    status: str = "active",
) -> Person:
    if user.person_id is not None:
        person = db.get(Person, user.person_id)
        if person is None:
            raise HTTPException(status_code=500, detail="Broken user/person link")
        return person

    person = Person(
        primary_person_type="customer",
        status=status,
        phone_e164=user.phone,
    )
    db.add(person)
    db.flush()
    db.add(
        CustomerProfile(
            person_id=person.id,
            marketing_consent=False,
        )
    )
    user.person_id = person.id
    return person


def _ensure_customer_auth_records(
    db: Session,
    *,
    phone: str,
) -> tuple[User, Person, AuthIdentity, AuthFactor]:
    user = db.scalar(select(User).where(User.phone == phone))
    if user is None:
        user = User(phone=phone)
        db.add(user)
        db.flush()
        person = _ensure_customer_person_link(db, user, status="pending_verification")
    else:
        person = _ensure_customer_person_link(db, user)

    person.phone_e164 = phone

    identity = db.scalar(
        select(AuthIdentity).where(
            AuthIdentity.person_id == person.id,
            AuthIdentity.identity_type == "phone",
            AuthIdentity.identity_value_normalized == phone,
        )
    )
    if identity is None:
        has_primary_identity = db.scalar(
            select(AuthIdentity.id).where(
                AuthIdentity.person_id == person.id,
                AuthIdentity.status == "active",
                AuthIdentity.is_primary.is_(True),
            )
        )
        identity = AuthIdentity(
            person_id=person.id,
            identity_type="phone",
            identity_value=phone,
            identity_value_normalized=phone,
            is_primary=has_primary_identity is None,
            is_verified=False,
            status="active",
        )
        db.add(identity)
        db.flush()

    factor = db.scalar(
        select(AuthFactor).where(
            AuthFactor.person_id == person.id,
            AuthFactor.identity_id == identity.id,
            AuthFactor.factor_type == "phone_otp",
        )
    )
    if factor is None:
        has_primary_factor = db.scalar(
            select(AuthFactor.id).where(
                AuthFactor.person_id == person.id,
                AuthFactor.factor_type == "phone_otp",
                AuthFactor.status == "active",
                AuthFactor.is_primary.is_(True),
            )
        )
        factor = AuthFactor(
            person_id=person.id,
            identity_id=identity.id,
            factor_type="phone_otp",
            display_label="Phone OTP",
            is_primary=has_primary_factor is None,
            is_verified=identity.is_verified,
            verified_at=identity.verified_at,
            status="active",
        )
        db.add(factor)
        db.flush()

    return user, person, identity, factor


def _request_ip(request: Request | None) -> str | None:
    if request is None or request.client is None:
        return None
    return request.client.host


def _cancel_pending_phone_otp_challenges(db: Session, *, identity_id: uuid.UUID) -> None:
    pending_challenges = db.scalars(
        select(AuthChallenge).where(
            AuthChallenge.identity_id == identity_id,
            AuthChallenge.status == "pending",
        )
    ).all()
    for challenge in pending_challenges:
        challenge.status = "cancelled"


def _latest_pending_phone_otp_challenge(
    db: Session,
    *,
    identity_id: uuid.UUID,
) -> AuthChallenge | None:
    return db.scalar(
        select(AuthChallenge)
        .where(
            AuthChallenge.identity_id == identity_id,
            AuthChallenge.status == "pending",
        )
        .order_by(AuthChallenge.created_at.desc())
    )


def _create_auth_session(
    db: Session,
    *,
    user: User,
    person: Person,
    request: Request | None,
) -> str:
    now = _now_utc()
    session_id = new_uuid7()
    token = create_access_token(
        secret=_settings.auth_secret,
        user_id=user.id,
        phone=user.phone,
        ttl_seconds=_settings.access_token_ttl_seconds,
        session_id=str(session_id),
    )
    db.add(
        AuthSession(
            id=session_id,
            person_id=person.id,
            session_token_hash=hash_token(token),
            auth_strength="single_factor",
            issued_at=now,
            expires_at=now + timedelta(seconds=_settings.access_token_ttl_seconds),
            ip_address=_request_ip(request),
            user_agent=request.headers.get("user-agent") if request is not None else None,
            device_id=request.headers.get("x-device-id") if request is not None else None,
        )
    )
    return token


def _derive_dev_challenge_type(*, user_exists_before_start: bool, person_status: str) -> str:
    if not user_exists_before_start or person_status == "pending_verification":
        return "sign_up"
    return "sign_in"


def _mark_phone_auth_verified(
    *,
    person: Person,
    identity: AuthIdentity,
    factor: AuthFactor,
    challenge: AuthChallenge,
) -> bool:
    now = _now_utc()
    is_new_user = challenge.challenge_type == "sign_up"
    if person.status == "pending_verification":
        person.status = "active"
    identity.is_verified = True
    identity.status = "active"
    if identity.verified_at is None:
        identity.verified_at = now
    factor.is_verified = True
    factor.status = "active"
    if factor.verified_at is None:
        factor.verified_at = now
    factor.last_used_at = now
    challenge.attempt_count += 1
    challenge.status = "completed"
    challenge.completed_at = now
    return is_new_user


@app.post("/dev/auth/otp/start")
def dev_otp_start(
    request: Request,
    payload: dict = Body(...),
    db: Session = Depends(get_db),
) -> dict:
    _require_dev_otp_enabled()
    phone = _normalize_phone(str(payload.get("phone", "")))
    user_exists_before_start = db.scalar(select(User.id).where(User.phone == phone)) is not None
    try:
        _, person, identity, _ = _ensure_customer_auth_records(db, phone=phone)
        _cancel_pending_phone_otp_challenges(db, identity_id=identity.id)
        challenge = AuthChallenge(
            person_id=person.id,
            identity_id=identity.id,
            factor_type="phone_otp",
            challenge_type=_derive_dev_challenge_type(
                user_exists_before_start=user_exists_before_start,
                person_status=person.status,
            ),
            delivery_channel="app",
            max_attempts=5,
            expires_at=_now_utc() + timedelta(minutes=10),
            status="pending",
            ip_address=_request_ip(request),
            user_agent=request.headers.get("user-agent"),
        )
        db.add(challenge)
        db.commit()
        db.refresh(challenge)
    except IntegrityError:
        db.rollback()
        raise

    return {"ok": True, "phone": phone, "challengeId": str(challenge.id)}


@app.post("/dev/auth/otp/verify")
def dev_otp_verify(
    request: Request,
    payload: dict = Body(...),
    db: Session = Depends(get_db),
) -> dict:
    _require_dev_otp_enabled()
    phone = _normalize_phone(str(payload.get("phone", "")))
    otp = str(payload.get("otp", ""))
    _validate_otp(otp)

    user = db.scalar(select(User).where(User.phone == phone))
    if user is None:
        raise HTTPException(status_code=400, detail="otp challenge not found")

    try:
        user, person, identity, factor = _ensure_customer_auth_records(db, phone=phone)
        challenge = _latest_pending_phone_otp_challenge(db, identity_id=identity.id)
        if challenge is None:
            raise HTTPException(status_code=400, detail="otp challenge not found")

        now = _now_utc()
        challenge_expires_at = challenge.expires_at
        if challenge_expires_at.tzinfo is None:
            challenge_expires_at = challenge_expires_at.replace(tzinfo=UTC)
        if challenge_expires_at <= now:
            challenge.status = "expired"
            db.commit()
            raise HTTPException(status_code=401, detail="otp expired")

        if challenge.attempt_count >= challenge.max_attempts:
            challenge.status = "failed"
            challenge.failed_at = now
            db.commit()
            raise HTTPException(status_code=401, detail="otp attempts exceeded")

        is_new_user = _mark_phone_auth_verified(
            person=person,
            identity=identity,
            factor=factor,
            challenge=challenge,
        )
        token = _create_auth_session(
            db,
            user=user,
            person=person,
            request=request,
        )
        db.commit()
        db.refresh(user)
    except IntegrityError:
        db.rollback()
        raise

    return {
        "accessToken": token,
        "tokenType": "Bearer",
        "isNewUser": is_new_user,
        "user": {"id": user.id, "phone": user.phone},
    }


@app.get("/v1/me")
def me(
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
) -> dict:
    if authorization is None:
        raise HTTPException(status_code=401, detail="Missing Authorization")

    payload = verify_bearer_token(
        secret=_settings.auth_secret,
        authorization_header=authorization,
        db=db,
    )
    return {
        "user": {
            "id": payload.sub,
            "phone": payload.phone,
        },
        "exp": payload.exp,
    }


_SERVICE_DEFINITION_SEED_ROWS = [
    {
        "id": "ambulance",
        "title": "Ambulance",
        "subtitle": "Emergency transport",
        "icon": "ambulance",
        "status": "active",
    },
    {
        "id": "home_visit",
        "title": "Home visit",
        "subtitle": "Doctor comes to you",
        "icon": "house",
        "status": "active",
    },
    {
        "id": "pharmacy",
        "title": "Pharmacy",
        "subtitle": "Order medicine",
        "icon": "pill",
        "status": "active",
    },
]


def _ensure_service_definitions_seed_data(db: Session) -> None:
    if db.scalar(select(ServiceDefinition.id).limit(1)) is not None:
        return

    for seed_row in _SERVICE_DEFINITION_SEED_ROWS:
        db.add(
            ServiceDefinition(
                id=str(seed_row["id"]),
                title=str(seed_row["title"]),
                subtitle=(
                    str(seed_row["subtitle"])
                    if isinstance(seed_row.get("subtitle"), str)
                    else None
                ),
                icon=(
                    str(seed_row["icon"])
                    if isinstance(seed_row.get("icon"), str)
                    else None
                ),
                status=str(seed_row["status"]),
            )
        )
    db.commit()


def _service_route(service_id: str) -> dict[str, object]:
    if service_id == "ambulance":
        return {
            "route": "customer.schema_screen",
            "value": {
                "screenId": "customer_request_ambulance",
                "title": "Ambulance",
            },
        }
    if service_id == "home_visit":
        return {
            "route": "customer.schema_screen",
            "value": {
                "screenId": "customer_request_home_visit",
                "title": "Home Visit",
            },
        }
    if service_id == "pharmacy":
        return {
            "route": "customer.schema_screen",
            "value": {
                "screenId": "pharmacy_shop",
                "title": "Pharmacy",
                "chromePreset": "pharmacy_cart_badge",
            },
        }
    return {
        "route": "customer.schema_screen",
        "value": {
            "screenId": "customer_service_detail",
            "title": "Service",
            "params": {"id": service_id},
        },
    }


def _service_detail_route(service_id: str) -> dict[str, object]:
    return {
        "route": "customer.schema_screen",
        "value": {
            "screenId": "customer_service_detail",
            "title": "Service",
            "params": {"id": service_id},
        },
    }


def _serialize_service_definition(item: ServiceDefinition) -> dict[str, object]:
    return {
        "id": item.id,
        "title": item.title,
        "subtitle": item.subtitle,
        "icon": item.icon,
        "route": _service_route(item.id),
        "detailRoute": _service_detail_route(item.id),
    }


def _load_service_definitions(
    *,
    db: Session,
    q: str | None,
) -> list[ServiceDefinition]:
    _ensure_service_definitions_seed_data(db)

    stmt = select(ServiceDefinition).where(ServiceDefinition.status == "active")
    if q:
        query = q.strip().lower()
        if query:
            pattern = f"%{query}%"
            stmt = stmt.where(
                or_(
                    func.lower(ServiceDefinition.title).like(pattern),
                    func.lower(func.coalesce(ServiceDefinition.subtitle, "")).like(pattern),
                )
            )
    stmt = stmt.order_by(func.lower(ServiceDefinition.title).asc(), ServiceDefinition.id.asc())
    return list(db.scalars(stmt))


@app.get("/v1/service-definitions")
def list_service_definitions(
    q: str | None = Query(default=None, min_length=1, max_length=50),
    db: Session = Depends(get_db),
) -> dict:
    items = _load_service_definitions(db=db, q=q)
    return {"items": [_serialize_service_definition(item) for item in items]}


@app.get("/v1/service-definitions/paged")
def list_service_definitions_paged(
    cursor: str | None = Query(default=None),
    limit: int = Query(default=10, ge=1, le=50),
    q: str | None = Query(default=None, min_length=1, max_length=50),
    db: Session = Depends(get_db),
) -> dict:
    items_source = _load_service_definitions(db=db, q=q)

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
        "items": [_serialize_service_definition(item) for item in items],
        "next": {"cursor": next_cursor},
    }


@app.get("/v1/service-definitions/detail")
def get_service_definition_detail(
    id: str = Query(min_length=1, max_length=64),
    db: Session = Depends(get_db),
) -> dict:
    _ensure_service_definitions_seed_data(db)
    match = db.scalar(
        select(ServiceDefinition).where(
            ServiceDefinition.id == id,
            ServiceDefinition.status == "active",
        )
    )
    if match is None:
        return {"items": []}
    return {"items": [_serialize_service_definition(match)]}
