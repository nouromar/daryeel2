from __future__ import annotations

import os
import shutil
import uuid
from decimal import Decimal
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
from app.events import record_request_event
from app.events.types import ATTACHMENT_ADDED
from app.events.types import REQUEST_CREATED
from app.ids import new_uuid7
from app.models import (
    Attachment,
    Organization,
    Pharmacy,
    PharmacyProduct,
    Product,
    RequestAttachment,
    ServiceRequest,
    User,
)

router = APIRouter(prefix="/v1/pharmacy", tags=["pharmacy"])


def _upload_dir() -> Path:
    raw = os.getenv("API_UPLOAD_DIR") or os.getenv("UPLOAD_DIR") or "/tmp/daryeel_uploads"
    p = Path(raw).expanduser().resolve()
    p.mkdir(parents=True, exist_ok=True)
    return p


_SEED_ORGANIZATION_ID = uuid.UUID("018f2f20-0000-7000-8000-000000000001")
_SEED_PHARMACY_ID = uuid.UUID("018f2f20-0000-7000-8000-000000000002")
_SEED_CATALOG_PRODUCTS = [
    {
        "id": uuid.UUID("018f2f20-0000-7000-8000-000000000101"),
        "name": "Amoxicillin 500mg",
        "generic_name": "Amoxicillin",
        "form": "capsule",
        "strength": "500mg",
        "rx_required": True,
        "price_amount": Decimal("3.50"),
    },
    {
        "id": uuid.UUID("018f2f20-0000-7000-8000-000000000102"),
        "name": "Cetirizine 10mg",
        "generic_name": "Cetirizine",
        "form": "tablet",
        "strength": "10mg",
        "rx_required": False,
        "price_amount": Decimal("2.00"),
    },
    {
        "id": uuid.UUID("018f2f20-0000-7000-8000-000000000103"),
        "name": "Omeprazole 20mg",
        "generic_name": "Omeprazole",
        "form": "capsule",
        "strength": "20mg",
        "rx_required": True,
        "price_amount": Decimal("4.20"),
    },
    {
        "id": uuid.UUID("018f2f20-0000-7000-8000-000000000104"),
        "name": "Paracetamol 500mg",
        "generic_name": "Paracetamol",
        "form": "tablet",
        "strength": "500mg",
        "rx_required": False,
        "price_amount": Decimal("1.00"),
    },
]

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


def _initial_pharmacy_sub_status(
    *,
    cart_lines: list[dict[str, Any]],
    prescription_upload_ids: list[str],
) -> str:
    if prescription_upload_ids:
        return "awaiting_branch_review"

    for line in cart_lines:
        if bool(line.get("rx_required")):
            return "awaiting_prescription"

    return "awaiting_branch_review"


def _normalize_attachment_ids(values: list[str]) -> list[uuid.UUID]:
    normalized: list[uuid.UUID] = []
    seen: set[uuid.UUID] = set()
    for raw_id in values:
        if not isinstance(raw_id, str):
            continue
        candidate = raw_id.strip()
        if not candidate:
            continue
        try:
            parsed = uuid.UUID(candidate)
        except ValueError:
            continue
        if parsed in seen:
            continue
        seen.add(parsed)
        normalized.append(parsed)
    return normalized


def _load_attachments_by_id(
    db: Session,
    *,
    attachment_ids: list[uuid.UUID],
) -> list[Attachment]:
    if not attachment_ids:
        return []

    rows = list(
        db.scalars(
            select(Attachment).where(Attachment.id.in_(attachment_ids))
        )
    )
    rows_by_id = {row.id: row for row in rows}
    missing = [attachment_id for attachment_id in attachment_ids if attachment_id not in rows_by_id]
    if missing:
        raise HTTPException(status_code=400, detail="Unknown prescription attachment id")
    return [rows_by_id[attachment_id] for attachment_id in attachment_ids]


def _ensure_catalog_seed_data(db: Session) -> None:
    if db.scalar(select(Product.id).limit(1)) is not None:
        return

    organization = Organization(
        id=_SEED_ORGANIZATION_ID,
        name="Daryeel Pharmacy Network",
        status="active",
        address_text="Hodan, Mogadishu",
        country_code="SO",
        city_name="Mogadishu",
    )
    pharmacy = Pharmacy(
        id=_SEED_PHARMACY_ID,
        organization_id=organization.id,
        name="Hodan Pharmacy Branch",
        branch_code="hodan-main",
        status="active",
        address_text="Hodan, Mogadishu",
        country_code="SO",
        city_name="Mogadishu",
        zone_code="hodan",
    )
    db.add(organization)
    db.add(pharmacy)

    for seed_product in _SEED_CATALOG_PRODUCTS:
        product = Product(
            id=seed_product["id"],
            name=str(seed_product["name"]),
            generic_name=str(seed_product["generic_name"]),
            form=str(seed_product["form"]),
            strength=str(seed_product["strength"]),
            rx_required=bool(seed_product["rx_required"]),
            status="active",
        )
        offer = PharmacyProduct(
            pharmacy_id=pharmacy.id,
            product_id=product.id,
            price_amount=seed_product["price_amount"],
            currency_code="USD",
            stock_status="in_stock",
            status="active",
        )
        db.add(product)
        db.add(offer)

    db.commit()


def _format_catalog_price(
    *,
    amount: Decimal | float | int,
    currency_code: str,
) -> tuple[float, str]:
    normalized = amount if isinstance(amount, Decimal) else Decimal(str(amount))
    price = float(normalized)
    if currency_code.upper() == "USD":
        return price, f"${normalized:.2f}"
    return price, f"{currency_code.upper()} {normalized:.2f}"


def _serialize_catalog_item(
    *,
    product: Product,
    offer: PharmacyProduct,
) -> dict[str, Any]:
    price, subtitle = _format_catalog_price(
        amount=offer.price_amount,
        currency_code=offer.currency_code,
    )
    return {
        "id": str(product.id),
        "name": product.name,
        "rx_required": product.rx_required,
        "price": price,
        "subtitle": subtitle,
        "icon": "pharmacy",
        "route": "",
    }


@router.get("/catalog")
def pharmacy_catalog(
    db: Session = Depends(get_db),
    cursor: str | None = Query(default=None),
    limit: int = Query(default=20, ge=1, le=50),
    q: str | None = Query(default=None, min_length=1, max_length=50),
) -> dict:
    _ensure_catalog_seed_data(db)

    rows = list(
        db.execute(
            select(Product, PharmacyProduct)
            .join(PharmacyProduct, PharmacyProduct.product_id == Product.id)
            .join(Pharmacy, Pharmacy.id == PharmacyProduct.pharmacy_id)
            .where(
                Product.status == "active",
                Pharmacy.status == "active",
                PharmacyProduct.status == "active",
                PharmacyProduct.stock_status.in_(("in_stock", "low_stock")),
            )
        )
    )

    cheapest_offer_by_product: dict[uuid.UUID, tuple[Product, PharmacyProduct]] = {}
    for product, offer in rows:
        current = cheapest_offer_by_product.get(product.id)
        if current is None or offer.price_amount < current[1].price_amount:
            cheapest_offer_by_product[product.id] = (product, offer)

    items_source = [
        _serialize_catalog_item(product=product, offer=offer)
        for product, offer in cheapest_offer_by_product.values()
    ]
    items_source.sort(key=lambda item: (str(item["name"]).lower(), str(item["id"])))

    if q:
        query = q.strip().lower()
        if query:
            items_source = [
                item
                for item in items_source
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

    attachment_ids = _normalize_attachment_ids(ids)
    if ids and not attachment_ids:
        raise HTTPException(status_code=400, detail="Unknown prescription attachment id")
    attachments = _load_attachments_by_id(
        db,
        attachment_ids=attachment_ids,
    )

    if not payload.payload.cart_lines and not attachments:
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
        sub_status=_initial_pharmacy_sub_status(
            cart_lines=cart_lines,
            prescription_upload_ids=[str(item.id) for item in attachments],
        ),
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
            "prescription_upload_ids": [str(item.id) for item in attachments],
        },
    )
    db.add(order)
    db.flush()

    record_request_event(
        db,
        request=order,
        event_type=REQUEST_CREATED,
        actor_type="customer",
        actor_id=user.id,
        from_status=None,
        to_status=order.status,
        sub_status=order.sub_status,
        metadata={"service": "pharmacy"},
    )

    for attachment in attachments:
        request_attachment = RequestAttachment(
            request_id=order.id,
            attachment_id=attachment.id,
            attachment_type="prescription",
            status="active",
            uploaded_by_actor_type="customer",
            uploaded_by_actor_id=user.id,
        )
        db.add(request_attachment)
        record_request_event(
            db,
            request=order,
            event_type=ATTACHMENT_ADDED,
            actor_type="customer",
            actor_id=user.id,
            related_entity_type="attachment",
            related_entity_id=str(attachment.id),
            metadata={"attachmentType": "prescription"},
        )
    db.commit()
    db.refresh(order)

    return {
        "order": {
            "id": str(order.id),
            "service_id": order.service_id,
            "status": order.status,
            "sub_status": order.sub_status,
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

    attachment_id = new_uuid7()
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
    dest = _upload_dir() / f"{attachment_id}_{safe_name}"

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

    rec = Attachment(
        id=attachment_id,
        storage_key=str(dest),
        filename=safe_name,
        content_type=(content_type or None),
        size_bytes=size_bytes,
    )
    db.add(rec)
    db.commit()

    return {
        "ok": True,
        "id": str(attachment_id),
        "filename": safe_name,
        "content_type": (content_type or None),
        "size_bytes": size_bytes,
    }
