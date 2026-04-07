from __future__ import annotations

import os
import shutil
import uuid
from pathlib import Path
from typing import Any

from fastapi import APIRouter
from fastapi import Body
from fastapi import Depends
from fastapi import File
from fastapi import HTTPException
from fastapi import Query
from fastapi import UploadFile
from pydantic import BaseModel
from pydantic import Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import get_db
from app.deps import require_access_token_payload
from app.models import PrescriptionUpload, RequestEvent, ServiceRequest, User

router = APIRouter(prefix="/v1/pharmacy", tags=["pharmacy"])


def _upload_dir() -> Path:
    raw = os.getenv("API_UPLOAD_DIR") or os.getenv("UPLOAD_DIR") or "/tmp/daryeel_uploads"
    p = Path(raw).expanduser().resolve()
    p.mkdir(parents=True, exist_ok=True)
    return p


_PHARMACY_CATALOG = [
    {
        "id": "prod_paracetamol_500mg",
        "name": "Paracetamol 500mg",
        "rx_required": False,
        "subtitle": "$1.00",
        "icon": "pharmacy",
        "route": "",
    },
    {
        "id": "prod_amoxicillin_500mg",
        "name": "Amoxicillin 500mg",
        "rx_required": True,
        "subtitle": "$3.50",
        "icon": "pharmacy",
        "route": "",
    },
    {
        "id": "prod_cetirizine_10mg",
        "name": "Cetirizine 10mg",
        "rx_required": False,
        "subtitle": "$2.00",
        "icon": "pharmacy",
        "route": "",
    },
    {
        "id": "prod_omeprazole_20mg",
        "name": "Omeprazole 20mg",
        "rx_required": True,
        "subtitle": "$4.20",
        "icon": "pharmacy",
        "route": "",
    },
]


@router.get("/catalog")
def pharmacy_catalog(
    cursor: str | None = Query(default=None),
    limit: int = Query(default=20, ge=1, le=50),
    q: str | None = Query(default=None, min_length=1, max_length=50),
) -> dict:
    # Temporary fixture endpoint to unblock schema-driven pharmacy UI.
    # Cursor is a stringified offset.
    items_source = _PHARMACY_CATALOG
    if q:
        query = q.strip().lower()
        if query:
            items_source = [
                item
                for item in _PHARMACY_CATALOG
                if query in str(item.get("name", "")).lower()
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


class Location(BaseModel):
    text: str = Field(min_length=1, max_length=200)
    lat: float
    lng: float
    accuracy_m: float | None = None
    place_id: str | None = None
    region_id: str | None = None


class PaymentChoice(BaseModel):
    method: str = Field(pattern=r"^(cash|mobile_money)$")
    timing: str = Field(pattern=r"^(before_delivery|after_delivery)$")


class CartLine(BaseModel):
    product_id: str = Field(min_length=1, max_length=128)
    quantity: int = Field(ge=1, le=999)


class CreatePharmacyOrderRequest(BaseModel):
    cart_lines: list[CartLine] = Field(default_factory=list)
    delivery_location: Location | None = None
    payment: PaymentChoice | None = None
    notes: str | None = Field(default=None, max_length=500)
    prescription_upload_id: str | None = Field(default=None, max_length=128)
    prescription_upload_ids: list[str] = Field(default_factory=list)


@router.post("/orders")
def create_pharmacy_order(
    payload: CreatePharmacyOrderRequest = Body(...),
    db: Session = Depends(get_db),
    token_payload=Depends(require_access_token_payload),
) -> dict[str, Any]:
    # Auth
    user_id = int(token_payload.sub)
    user = db.scalar(select(User).where(User.id == user_id))
    if user is None:
        raise HTTPException(status_code=401, detail="Unknown user")

    ids: list[str] = []
    if payload.prescription_upload_id is not None:
        p = payload.prescription_upload_id.strip()
        if p:
            ids.append(p)

    for raw_id in payload.prescription_upload_ids:
        if not isinstance(raw_id, str):
            continue
        p = raw_id.strip()
        if not p:
            continue
        if len(p) > 128:
            continue
        ids.append(p)

    # Bound list size to keep payloads small.
    if len(ids) > 10:
        ids = ids[:10]

    if not payload.cart_lines and not ids:
        raise HTTPException(
            status_code=400,
            detail="Order must include cart_lines or prescription_upload_id",
        )

    order = ServiceRequest(
        service_id="pharmacy",
        customer_user_id=user.id,
        status="created",
        notes=payload.notes,
        delivery_location_json=(payload.delivery_location.model_dump() if payload.delivery_location else None),
        payment_json=(payload.payment.model_dump() if payload.payment else None),
        payload_json={
            "cart_lines": [x.model_dump() for x in payload.cart_lines],
            "prescription_upload_id": (ids[0] if ids else None),
            "prescription_upload_ids": ids,
        },
    )
    db.add(order)
    db.commit()
    db.refresh(order)

    event = RequestEvent(
        request_id=order.id,
        type="created",
        from_status=None,
        to_status=order.status,
        actor_type="customer",
        actor_id=user.id,
        metadata_json={"service": "pharmacy"},
    )
    db.add(event)
    db.commit()

    return {
        "order": {
            "id": str(order.id),
            "service_id": order.service_id,
            "status": order.status,
            "customer_user_id": str(order.customer_user_id),
            "notes": order.notes,
            "delivery_location": order.delivery_location_json,
            "payment": order.payment_json,
            "payload": order.payload_json,
        }
    }


@router.post("/prescriptions/upload")
def upload_prescription(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    token_payload=Depends(require_access_token_payload),
) -> dict[str, Any]:
    user_id = int(token_payload.sub)
    user = db.scalar(select(User).where(User.id == user_id))
    if user is None:
        raise HTTPException(status_code=401, detail="Unknown user")

    upload_id = uuid.uuid4().hex
    safe_name_raw = (file.filename or "prescription").strip() or "prescription"
    safe_name = Path(safe_name_raw).name
    if len(safe_name) > 200:
        safe_name = safe_name[-200:]

    # Minimal validation; allow common prescription formats.
    # Many clients (including Dart's MultipartFile.fromBytes) send
    # `application/octet-stream` unless an explicit content-type is provided,
    # so we fall back to validating by filename extension in that case.
    content_type = (file.content_type or "").strip().lower()
    ext = Path(safe_name).suffix.strip().lower()

    allowed_by_content_type = (
        content_type.startswith("image/")
        or content_type == "application/pdf"
    )

    allowed_by_extension = ext in {
        ".pdf",
        ".jpg",
        ".jpeg",
        ".png",
        ".webp",
        ".heic",
        ".heif",
    }

    is_generic_octet_stream = content_type in {
        "",
        "application/octet-stream",
        "binary/octet-stream",
    }

    if not allowed_by_content_type:
        if not (is_generic_octet_stream and allowed_by_extension):
            raise HTTPException(status_code=400, detail="Unsupported file type")
    dest = _upload_dir() / f"{upload_id}_{safe_name}"

    size_bytes: int | None = None
    try:
        with dest.open("wb") as out:
            shutil.copyfileobj(file.file, out)
        try:
            size_bytes = dest.stat().st_size
        except OSError:
            size_bytes = None
    finally:
        try:
            file.file.close()
        except Exception:
            pass

    rec = PrescriptionUpload(
        id=upload_id,
        service_id="pharmacy",
        customer_user_id=user.id,
        filename=safe_name,
        content_type=(content_type or None),
        size_bytes=size_bytes,
        storage_path=str(dest),
    )
    db.add(rec)
    db.commit()

    return {
        "ok": True,
        "id": upload_id,
        "filename": safe_name,
        "content_type": (content_type or None),
        "size_bytes": size_bytes,
    }
