from __future__ import annotations

import os
import shutil
import uuid
from pathlib import Path
from typing import Any, Literal

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
        "price": 1.00,
        "subtitle": "$1.00",
        "icon": "pharmacy",
        "route": "",
    },
    {
        "id": "prod_amoxicillin_500mg",
        "name": "Amoxicillin 500mg",
        "rx_required": True,
        "price": 3.50,
        "subtitle": "$3.50",
        "icon": "pharmacy",
        "route": "",
    },
    {
        "id": "prod_cetirizine_10mg",
        "name": "Cetirizine 10mg",
        "rx_required": False,
        "price": 2.00,
        "subtitle": "$2.00",
        "icon": "pharmacy",
        "route": "",
    },
    {
        "id": "prod_omeprazole_20mg",
        "name": "Omeprazole 20mg",
        "rx_required": True,
        "price": 4.20,
        "subtitle": "$4.20",
        "icon": "pharmacy",
        "route": "",
    },
]


def _build_extra_catalog_items(count: int = 120) -> list[dict[str, Any]]:
    # Deterministic seed data for local development/infinite-scroll testing.
    # Keep IDs stable across restarts so itemKeyPath remains meaningful.
    bases = [
        ("Vitamin C", "1000mg"),
        ("Ibuprofen", "200mg"),
        ("Aspirin", "81mg"),
        ("Loratadine", "10mg"),
        ("Zinc", "50mg"),
        ("Magnesium", "250mg"),
        ("Saline Nasal Spray", "50ml"),
        ("Cough Syrup", "100ml"),
    ]

    items: list[dict[str, Any]] = []
    for i in range(1, max(0, count) + 1):
        base_name, dose = bases[(i - 1) % len(bases)]
        rx_required = i % 9 == 0
        price = 0.95 + (i % 25) * 0.15
        items.append(
            {
                "id": f"prod_fixture_{i:03d}",
                "name": f"{base_name} {dose} (Item {i:03d})",
                "rx_required": rx_required,
                "price": round(price, 2),
                "subtitle": f"${price:.2f}",
                "icon": "pharmacy",
                "route": "",
            }
        )
    return items


# Expand the fixture set to support multi-page scrolling.
_PHARMACY_CATALOG.extend(_build_extra_catalog_items(count=120))

_PHARMACY_CHECKOUT_OPTIONS = {
    "payment_options": {
        "methods": [
            {
                "id": "cash",
                "label": "Cash",
                "description": "Pay with cash when the order arrives.",
            },
            {
                "id": "mobile_money",
                "label": "Mobile money",
                "description": "Pay using EVC or Zaad.",
            },
        ],
        "timings": [
            {
                "id": "after_delivery",
                "label": "After delivery",
                "description": "Pay after you receive the order.",
            },
            {
                "id": "before_delivery",
                "label": "Before delivery",
                "description": "Pay before the order is dispatched.",
            },
        ],
    }
}


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


@router.get("/checkout_options")
def pharmacy_checkout_options() -> dict[str, Any]:
    return _PHARMACY_CHECKOUT_OPTIONS


class Location(BaseModel):
    text: str = Field(min_length=1, max_length=200)
    lat: float | None = None
    lng: float | None = None
    accuracy_m: float | None = None
    place_id: str | None = None
    region_id: str | None = None


class PaymentChoice(BaseModel):
    method: str = Field(pattern=r"^(cash|mobile_money)$")
    timing: str = Field(pattern=r"^(before_delivery|after_delivery)$")


class SummaryLine(BaseModel):
    id: str | None = Field(default=None, max_length=128)
    label: str = Field(min_length=1, max_length=128)
    amount: float | int = 0
    amountText: str | None = Field(default=None, max_length=128)
    kind: str | None = Field(default=None, max_length=64)
    emphasis: str | None = Field(default=None, max_length=64)


class SummaryTotal(BaseModel):
    label: str = Field(min_length=1, max_length=128)
    amount: float | int = 0
    amountText: str | None = Field(default=None, max_length=128)
    kind: str | None = Field(default=None, max_length=64)
    emphasis: str | None = Field(default=None, max_length=64)


class PharmacyOrderPayload(BaseModel):
    # Preserve the client-provided cart line record (same shape as catalog item + quantity).
    cart_lines: list[dict[str, Any]] = Field(default_factory=list)
    summary_lines: list[SummaryLine] = Field(default_factory=list)
    summary_total: SummaryTotal | None = None
    prescription_upload_ids: list[str] = Field(default_factory=list)


class CreatePharmacyOrderRequest(BaseModel):
    service_id: Literal["pharmacy"] = "pharmacy"
    delivery_location: Location | None = None
    payment: PaymentChoice | None = None
    notes: str | None = Field(default=None, max_length=500)
    payload: PharmacyOrderPayload = Field(default_factory=PharmacyOrderPayload)


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
    for raw_id in payload.payload.prescription_upload_ids:
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

    if not payload.payload.cart_lines and not ids:
        raise HTTPException(
            status_code=400,
            detail="Order must include cart_lines or prescription_upload_ids",
        )

    cart_lines: list[dict[str, Any]] = []
    for raw_line in payload.payload.cart_lines:
        if not isinstance(raw_line, dict):
            continue

        qty_raw = raw_line.get("quantity")
        if isinstance(qty_raw, int):
            qty = qty_raw
        elif isinstance(qty_raw, float):
            qty = int(qty_raw)
        elif isinstance(qty_raw, str):
            try:
                qty = int(qty_raw.strip())
            except ValueError:
                qty = 0
        else:
            qty = 0

        if qty <= 0:
            continue

        cart_lines.append({**raw_line, "quantity": qty})

    order = ServiceRequest(
        service_id=payload.service_id,
        customer_user_id=user.id,
        status="created",
        notes=payload.notes,
        delivery_location_json=(payload.delivery_location.model_dump() if payload.delivery_location else None),
        payment_json=(payload.payment.model_dump() if payload.payment else None),
        payload_json={
            "cart_lines": cart_lines,
            "summary_lines": [x.model_dump() for x in payload.payload.summary_lines],
            "summary_total": (
                payload.payload.summary_total.model_dump()
                if payload.payload.summary_total
                else None
            ),
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
