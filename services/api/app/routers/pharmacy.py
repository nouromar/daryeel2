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
from pydantic import AliasChoices
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
    PharmacyOrderDetail,
    PharmacyOrderItem,
    PharmacyProduct,
    Product,
    RequestAttachment,
    ServiceRequest,
    User,
)
from app.settings import load_settings

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


def _parse_quantity(raw_quantity: Any) -> int:
    if isinstance(raw_quantity, int):
        return raw_quantity
    if isinstance(raw_quantity, float):
        return int(raw_quantity)
    if isinstance(raw_quantity, str):
        try:
            return int(raw_quantity.strip())
        except ValueError:
            return 0
    return 0


def _load_selected_pharmacy(*, db: Session, pharmacy_id: uuid.UUID) -> Pharmacy:
    pharmacy = db.scalar(
        select(Pharmacy).where(
            Pharmacy.id == pharmacy_id,
            Pharmacy.status == "active",
        )
    )
    if pharmacy is None:
        raise HTTPException(status_code=400, detail="Unknown selected pharmacy")
    return pharmacy


def _resolve_default_pharmacy(*, db: Session) -> Pharmacy:
    settings = load_settings()
    configured_id = settings.default_pharmacy_id.strip()
    if configured_id:
        try:
            pharmacy_id = uuid.UUID(configured_id)
        except ValueError as exc:
            raise HTTPException(
                status_code=500,
                detail="API_DEFAULT_PHARMACY_ID is invalid",
            ) from exc
        return _load_selected_pharmacy(db=db, pharmacy_id=pharmacy_id)

    pharmacy = db.scalar(
        select(Pharmacy)
        .where(Pharmacy.status == "active")
        .order_by(Pharmacy.created_at.asc(), Pharmacy.id.asc())
    )
    if pharmacy is None:
        raise HTTPException(status_code=503, detail="No active pharmacy is configured")
    return pharmacy


def _load_pharmacy_product_offers(
    *,
    db: Session,
    pharmacy_id: uuid.UUID,
    product_ids: list[uuid.UUID],
) -> dict[uuid.UUID, tuple[Product, PharmacyProduct]]:
    if not product_ids:
        return {}

    rows = list(
        db.execute(
            select(Product, PharmacyProduct)
            .join(PharmacyProduct, PharmacyProduct.product_id == Product.id)
            .where(
                Product.id.in_(product_ids),
                Product.status == "active",
                PharmacyProduct.pharmacy_id == pharmacy_id,
                PharmacyProduct.status == "active",
                PharmacyProduct.stock_status.in_(("in_stock", "low_stock")),
            )
        )
    )
    return {product.id: (product, offer) for product, offer in rows}


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


class PharmacyOrderItemInput(BaseModel):
    product_id: uuid.UUID = Field(
        alias="productId",
        validation_alias=AliasChoices("product_id", "productId"),
    )
    quantity: int = Field(ge=1)


class PharmacyOrderPayload(BaseModel):
    items: list[PharmacyOrderItemInput] = Field(default_factory=list)
    prescription_attachment_ids: list[str] = Field(
        default_factory=list,
        alias="prescriptionAttachmentIds",
        validation_alias=AliasChoices(
            "prescription_attachment_ids",
            "prescriptionAttachmentIds",
        ),
    )


class CreatePharmacyOrderRequest(BaseModel):
    service_id: Literal["pharmacy"] = "pharmacy"
    delivery_location: Location | None = None
    payment: PaymentChoice | None = None
    notes: str | None = Field(default=None, max_length=500)
    order: PharmacyOrderPayload = Field(default_factory=PharmacyOrderPayload)


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

    _ensure_catalog_seed_data(db)
    selected_pharmacy = _resolve_default_pharmacy(db=db)

    ids: list[str] = []
    for raw_id in payload.order.prescription_attachment_ids:
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

    if not payload.order.items and not attachments:
        raise HTTPException(
            status_code=400,
            detail="Order must include items or prescriptionAttachmentIds",
        )

    product_ids_in_order: list[uuid.UUID] = []
    normalized_items: list[PharmacyOrderItemInput] = []
    for item in payload.order.items:
        qty = _parse_quantity(item.quantity)
        if qty <= 0:
            continue
        normalized_item = PharmacyOrderItemInput(product_id=item.product_id, quantity=qty)
        normalized_items.append(normalized_item)
        product_id = normalized_item.product_id
        if product_id not in product_ids_in_order:
            product_ids_in_order.append(product_id)

    offer_by_product_id = _load_pharmacy_product_offers(
        db=db,
        pharmacy_id=selected_pharmacy.id,
        product_ids=product_ids_in_order,
    )
    missing_product_ids = [
        str(product_id)
        for product_id in product_ids_in_order
        if product_id not in offer_by_product_id
    ]
    if missing_product_ids:
        raise HTTPException(
            status_code=400,
            detail="Selected pharmacy does not offer one or more products",
        )

    currency_code = "USD"
    subtotal_amount = Decimal("0.00")
    discount_amount = Decimal("0.00")
    fee_amount = Decimal("0.00")
    tax_amount = Decimal("0.00")
    order_items: list[PharmacyOrderItem] = []
    for item in normalized_items:
        product_id = item.product_id
        quantity = item.quantity
        product, offer = offer_by_product_id[product_id]
        currency_code = offer.currency_code
        unit_price = offer.price_amount
        line_subtotal = unit_price * quantity
        subtotal_amount += line_subtotal
        order_items.append(
            PharmacyOrderItem(
                request_id=0,
                product_id=product.id,
                quantity=quantity,
                product_name=product.name,
                form=product.form,
                strength=product.strength,
                rx_required=product.rx_required,
                seller_sku=offer.seller_sku,
                unit_price_amount=unit_price,
                line_subtotal_amount=line_subtotal,
                line_discount_amount=None,
                line_tax_amount=None,
                line_total_amount=line_subtotal,
            )
        )

    total_amount = subtotal_amount - discount_amount + fee_amount + tax_amount

    order = ServiceRequest(
        service_id=payload.service_id,
        customer_user_id=user.id,
        status="created",
        sub_status=_initial_pharmacy_sub_status(
            cart_lines=[
                {"product_id": str(item.product_id), "rx_required": item.rx_required}
                for item in order_items
            ],
            prescription_upload_ids=[str(item.id) for item in attachments],
        ),
        notes=payload.notes,
        delivery_location_json=(payload.delivery_location.model_dump() if payload.delivery_location else None),
        payment_json=(payload.payment.model_dump() if payload.payment else None),
        payload_json=None,
    )
    db.add(order)
    db.flush()

    db.add(
        PharmacyOrderDetail(
            request_id=order.id,
            selected_pharmacy_id=selected_pharmacy.id,
            currency_code=currency_code,
            subtotal_amount=subtotal_amount,
            discount_amount=discount_amount,
            fee_amount=fee_amount,
            tax_amount=tax_amount,
            total_amount=total_amount,
        )
    )
    for order_item in order_items:
        order_item.request_id = order.id
        db.add(order_item)

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
