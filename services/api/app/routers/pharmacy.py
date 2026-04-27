from __future__ import annotations

from datetime import datetime, timezone
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
from app.deps import AuthorizedActor, require_access_token_payload, require_permission
from app.events import record_request_event
from app.events.types import ASSIGNMENT_CLOSED
from app.events.types import ASSIGNMENT_CREATED
from app.events.types import ATTACHMENT_ADDED
from app.events.types import CUSTOMER_CONFIRMATION_REQUESTED
from app.events.types import FULFILLMENT_COMPLETED
from app.events.types import FULFILLMENT_STARTED
from app.events.types import REQUEST_CREATED
from app.events.types import REQUEST_STATUS_CHANGED
from app.ids import new_uuid7
from app.models import (
    Attachment,
    Organization,
    Pharmacy,
    PharmacyOrderDetail,
    PharmacyOrderAssignment,
    PharmacyOrderItem,
    PharmacyProduct,
    Product,
    RequestAttachment,
    ServiceRequest,
    User,
)
from app.pharmacy_review import (
    DERIVED_ORDER_CHANGE_CONFIRMATION_TYPE,
    apply_pharmacy_order_snapshot,
    build_pharmacy_order_snapshot,
    clear_pharmacy_pending_confirmation,
    create_pharmacy_pending_confirmation,
    pending_confirmation_requires_customer_approval,
    resolve_pharmacy_pending_confirmation,
    serialize_pharmacy_pending_confirmation,
    set_submitted_order_snapshot,
)
from app.settings import load_settings

router = APIRouter(prefix="/v1/pharmacy", tags=["pharmacy"])

_MANAGE_PHARMACY_ORDERS_PERMISSION = "pharmacy.manage_orders"
_COMPLETE_PHARMACY_DELIVERY_PERMISSION = "pharmacy.complete_delivery"


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

_OPEN_ASSIGNMENT_STATUSES = {"active", "accepted"}
_BRANCH_ASSIGNMENT_KIND = "branch_fulfillment"
_DELIVERY_ASSIGNMENT_KIND = "delivery"


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


class AssignBranchRequest(BaseModel):
    pharmacy_id: uuid.UUID | None = Field(
        default=None,
        alias="pharmacyId",
        validation_alias=AliasChoices("pharmacy_id", "pharmacyId"),
    )
    assigned_role_code: str | None = Field(
        default=None,
        alias="assignedRoleCode",
        validation_alias=AliasChoices("assigned_role_code", "assignedRoleCode"),
    )


class BranchRejectRequest(BaseModel):
    reason_code: str = Field(
        min_length=1,
        max_length=64,
        alias="reasonCode",
        validation_alias=AliasChoices("reason_code", "reasonCode"),
    )


class RerouteBranchRequest(BaseModel):
    pharmacy_id: uuid.UUID = Field(
        alias="pharmacyId",
        validation_alias=AliasChoices("pharmacy_id", "pharmacyId"),
    )
    reason_code: str = Field(
        min_length=1,
        max_length=64,
        alias="reasonCode",
        validation_alias=AliasChoices("reason_code", "reasonCode"),
    )
    assigned_role_code: str | None = Field(
        default=None,
        alias="assignedRoleCode",
        validation_alias=AliasChoices("assigned_role_code", "assignedRoleCode"),
    )


class DispatchDeliveryRequest(BaseModel):
    assigned_role_code: str | None = Field(
        default=None,
        alias="assignedRoleCode",
        validation_alias=AliasChoices("assigned_role_code", "assignedRoleCode"),
    )


class DeliveryFailureRequest(BaseModel):
    reason_code: str = Field(
        min_length=1,
        max_length=64,
        alias="reasonCode",
        validation_alias=AliasChoices("reason_code", "reasonCode"),
    )


class ReviewBranchOrderRequest(BaseModel):
    items: list[PharmacyOrderItemInput] = Field(min_length=1)
    reason_code: str | None = Field(
        default=None,
        min_length=1,
        max_length=64,
        alias="reasonCode",
        validation_alias=AliasChoices("reason_code", "reasonCode"),
    )
    message: str | None = Field(default=None, max_length=500)
    confirmation_channel: str = Field(
        default="phone_call",
        pattern=r"^(phone_call|in_app)$",
        alias="confirmationChannel",
        validation_alias=AliasChoices("confirmation_channel", "confirmationChannel"),
    )


class ResolveCustomerConfirmationRequest(BaseModel):
    decision: Literal["approve", "reject"]
    channel: str = Field(
        default="phone_call",
        pattern=r"^(phone_call|in_app)$",
    )
    message: str | None = Field(default=None, max_length=500)


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _load_pharmacy_service_request(*, db: Session, request_id: int) -> ServiceRequest:
    request = db.scalar(
        select(ServiceRequest).where(
            ServiceRequest.id == request_id,
            ServiceRequest.service_id == "pharmacy",
        )
    )
    if request is None:
        raise HTTPException(status_code=404, detail="Pharmacy order not found")
    return request


def _load_pharmacy_order_detail(
    *,
    db: Session,
    request_id: int,
) -> PharmacyOrderDetail:
    detail = db.scalar(
        select(PharmacyOrderDetail).where(PharmacyOrderDetail.request_id == request_id)
    )
    if detail is None:
        raise HTTPException(status_code=404, detail="Pharmacy order detail not found")
    return detail


def _load_pharmacy_order_items(
    *,
    db: Session,
    request_id: int,
) -> list[PharmacyOrderItem]:
    return list(
        db.scalars(
            select(PharmacyOrderItem)
            .where(PharmacyOrderItem.request_id == request_id)
            .order_by(PharmacyOrderItem.created_at.asc(), PharmacyOrderItem.id.asc())
        )
    )


def _load_current_assignment(
    *,
    db: Session,
    request_id: int,
    assignment_kind: str,
) -> PharmacyOrderAssignment | None:
    rows = list(
        db.scalars(
            select(PharmacyOrderAssignment)
            .where(
                PharmacyOrderAssignment.request_id == request_id,
                PharmacyOrderAssignment.assignment_kind == assignment_kind,
                PharmacyOrderAssignment.status.in_(tuple(_OPEN_ASSIGNMENT_STATUSES)),
                PharmacyOrderAssignment.ended_at.is_(None),
            )
            .order_by(
                PharmacyOrderAssignment.started_at.desc(),
                PharmacyOrderAssignment.created_at.desc(),
            )
        )
    )
    if len(rows) > 1:
        raise HTTPException(
            status_code=500,
            detail="Multiple active assignments found for the same fulfillment phase",
        )
    return rows[0] if rows else None


def _require_current_assignment(
    *,
    db: Session,
    request_id: int,
    assignment_kind: str,
) -> PharmacyOrderAssignment:
    assignment = _load_current_assignment(
        db=db,
        request_id=request_id,
        assignment_kind=assignment_kind,
    )
    if assignment is None:
        raise HTTPException(status_code=409, detail="No active assignment for this phase")
    return assignment


def _next_assignment_attempt_no(
    *,
    db: Session,
    request_id: int,
    assignment_kind: str,
) -> int:
    attempts = list(
        db.scalars(
            select(PharmacyOrderAssignment.attempt_no)
            .where(
                PharmacyOrderAssignment.request_id == request_id,
                PharmacyOrderAssignment.assignment_kind == assignment_kind,
            )
            .order_by(PharmacyOrderAssignment.attempt_no.desc())
        )
    )
    if not attempts:
        return 1
    return int(attempts[0]) + 1


def _ensure_pharmacy_can_fulfill_order(
    *,
    db: Session,
    request_id: int,
    pharmacy_id: uuid.UUID,
) -> None:
    order_items = _load_pharmacy_order_items(db=db, request_id=request_id)
    if not order_items:
        return

    product_ids = list({item.product_id for item in order_items})
    offers = _load_pharmacy_product_offers(
        db=db,
        pharmacy_id=pharmacy_id,
        product_ids=product_ids,
    )
    missing = [str(product_id) for product_id in product_ids if product_id not in offers]
    if missing:
        raise HTTPException(
            status_code=400,
            detail="Selected pharmacy does not offer one or more order items",
        )


def _create_assignment(
    *,
    db: Session,
    request: ServiceRequest,
    assignment_kind: str,
    pharmacy_id: uuid.UUID | None,
    assigned_role_code: str | None,
    actor_type: str,
    actor_id: int | None,
    reason_code: str | None = None,
) -> PharmacyOrderAssignment:
    assignment = PharmacyOrderAssignment(
        request_id=request.id,
        pharmacy_id=pharmacy_id,
        assignment_kind=assignment_kind,
        assigned_role_code=assigned_role_code,
        status="active",
        attempt_no=_next_assignment_attempt_no(
            db=db,
            request_id=request.id,
            assignment_kind=assignment_kind,
        ),
        reason_code=reason_code,
        started_at=_utcnow(),
    )
    db.add(assignment)
    db.flush()
    record_request_event(
        db,
        request=request,
        event_type=ASSIGNMENT_CREATED,
        actor_type=actor_type,
        actor_id=actor_id,
        related_entity_type="assignment",
        related_entity_id=str(assignment.id),
        metadata={
            "assignmentKind": assignment.assignment_kind,
            "assignmentStatus": assignment.status,
            "attemptNo": assignment.attempt_no,
            "pharmacyId": str(assignment.pharmacy_id) if assignment.pharmacy_id else None,
            "assignedRoleCode": assignment.assigned_role_code,
            "reasonCode": reason_code,
        },
    )
    return assignment


def _close_assignment(
    *,
    db: Session,
    request: ServiceRequest,
    assignment: PharmacyOrderAssignment,
    actor_type: str,
    actor_id: int | None,
    status: str,
    reason_code: str | None = None,
) -> PharmacyOrderAssignment:
    assignment.status = status
    assignment.reason_code = reason_code
    assignment.ended_at = _utcnow()
    db.add(assignment)
    record_request_event(
        db,
        request=request,
        event_type=ASSIGNMENT_CLOSED,
        actor_type=actor_type,
        actor_id=actor_id,
        related_entity_type="assignment",
        related_entity_id=str(assignment.id),
        metadata={
            "assignmentKind": assignment.assignment_kind,
            "assignmentStatus": assignment.status,
            "attemptNo": assignment.attempt_no,
            "pharmacyId": str(assignment.pharmacy_id) if assignment.pharmacy_id else None,
            "assignedRoleCode": assignment.assigned_role_code,
            "reasonCode": reason_code,
        },
    )
    return assignment


def _workflow_state(request: ServiceRequest) -> tuple[str, str | None]:
    return request.status, request.sub_status


def _record_pharmacy_status_transition(
    *,
    db: Session,
    request: ServiceRequest,
    actor_type: str,
    actor_id: int | None,
    allowed_states: set[tuple[str, str | None]],
    next_status: str,
    next_sub_status: str | None,
    metadata: dict[str, Any],
    related_entity_id: str | None = None,
) -> None:
    if _workflow_state(request) not in allowed_states:
        raise HTTPException(status_code=409, detail="Order is not in a valid state for this action")
    record_request_event(
        db,
        request=request,
        event_type=REQUEST_STATUS_CHANGED,
        actor_type=actor_type,
        actor_id=actor_id,
        to_status=next_status,
        sub_status=next_sub_status,
        related_entity_type="assignment" if related_entity_id else None,
        related_entity_id=related_entity_id,
        metadata=metadata,
    )


def _serialize_assignment(assignment: PharmacyOrderAssignment | None) -> dict[str, Any] | None:
    if assignment is None:
        return None
    return {
        "id": str(assignment.id),
        "assignmentKind": assignment.assignment_kind,
        "status": assignment.status,
        "attemptNo": assignment.attempt_no,
        "pharmacyId": str(assignment.pharmacy_id) if assignment.pharmacy_id else None,
        "assignedRoleCode": assignment.assigned_role_code,
        "reasonCode": assignment.reason_code,
        "startedAt": assignment.started_at.isoformat() if assignment.started_at else None,
        "endedAt": assignment.ended_at.isoformat() if assignment.ended_at else None,
    }


def _serialize_fulfillment_response(
    *,
    db: Session,
    request: ServiceRequest,
) -> dict[str, Any]:
    detail = _load_pharmacy_order_detail(db=db, request_id=request.id)
    branch_assignment = _load_current_assignment(
        db=db,
        request_id=request.id,
        assignment_kind=_BRANCH_ASSIGNMENT_KIND,
    )
    delivery_assignment = _load_current_assignment(
        db=db,
        request_id=request.id,
        assignment_kind=_DELIVERY_ASSIGNMENT_KIND,
    )
    return {
        "request": {
            "id": str(request.id),
            "status": request.status,
            "subStatus": request.sub_status,
            "selectedPharmacyId": str(detail.selected_pharmacy_id),
        },
        "branchAssignment": _serialize_assignment(branch_assignment),
        "deliveryAssignment": _serialize_assignment(delivery_assignment),
        "pendingConfirmation": serialize_pharmacy_pending_confirmation(request),
    }


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
    set_submitted_order_snapshot(
        order,
        item_selections=[
            (item.product_id, item.quantity)
            for item in normalized_items
        ],
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
    _create_assignment(
        db=db,
        request=order,
        assignment_kind=_BRANCH_ASSIGNMENT_KIND,
        pharmacy_id=selected_pharmacy.id,
        assigned_role_code="branch_staff",
        actor_type="system",
        actor_id=None,
        reason_code="order_created",
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


@router.post("/orders/{request_id}/fulfillment/assign-branch")
def assign_branch_fulfillment(
    request_id: int,
    payload: AssignBranchRequest | None = Body(default=None),
    db: Session = Depends(get_db),
    actor: AuthorizedActor = Depends(
        require_permission(_MANAGE_PHARMACY_ORDERS_PERMISSION, service_id="pharmacy")
    ),
) -> dict[str, Any]:
    user_id = actor.user_id
    request = _load_pharmacy_service_request(db=db, request_id=request_id)
    detail = _load_pharmacy_order_detail(db=db, request_id=request.id)
    current_assignment = _load_current_assignment(
        db=db,
        request_id=request.id,
        assignment_kind=_BRANCH_ASSIGNMENT_KIND,
    )
    if current_assignment is not None:
        raise HTTPException(status_code=409, detail="An active branch assignment already exists")

    pharmacy_id = (
        payload.pharmacy_id
        if payload is not None and payload.pharmacy_id is not None
        else detail.selected_pharmacy_id
    )
    pharmacy = _load_selected_pharmacy(db=db, pharmacy_id=pharmacy_id)
    _ensure_pharmacy_can_fulfill_order(
        db=db,
        request_id=request.id,
        pharmacy_id=pharmacy.id,
    )
    detail.selected_pharmacy_id = pharmacy.id
    db.add(detail)

    _create_assignment(
        db=db,
        request=request,
        assignment_kind=_BRANCH_ASSIGNMENT_KIND,
        pharmacy_id=pharmacy.id,
        assigned_role_code=(
            payload.assigned_role_code
            if payload is not None and payload.assigned_role_code
            else "branch_staff"
        ),
        actor_type="staff",
        actor_id=user_id,
        reason_code="manual_assignment",
    )
    _record_pharmacy_status_transition(
        db=db,
        request=request,
        actor_type="staff",
        actor_id=user_id,
        allowed_states={
            ("created", "awaiting_branch_review"),
            ("created", "awaiting_prescription"),
        },
        next_status="created",
        next_sub_status=request.sub_status,
        metadata={"action": "assign_branch"},
    )
    db.commit()
    db.refresh(request)
    return _serialize_fulfillment_response(db=db, request=request)


@router.post("/orders/{request_id}/fulfillment/review")
def review_branch_order(
    request_id: int,
    payload: ReviewBranchOrderRequest = Body(...),
    db: Session = Depends(get_db),
    actor: AuthorizedActor = Depends(
        require_permission(_MANAGE_PHARMACY_ORDERS_PERMISSION, service_id="pharmacy")
    ),
) -> dict[str, Any]:
    user_id = actor.user_id
    request = _load_pharmacy_service_request(db=db, request_id=request_id)
    detail = _load_pharmacy_order_detail(db=db, request_id=request.id)
    assignment = _require_current_assignment(
        db=db,
        request_id=request.id,
        assignment_kind=_BRANCH_ASSIGNMENT_KIND,
    )
    if _workflow_state(request) != ("created", "awaiting_branch_review"):
        raise HTTPException(status_code=409, detail="Order is not in a valid state for branch review")

    snapshot = build_pharmacy_order_snapshot(
        db=db,
        selected_pharmacy_id=detail.selected_pharmacy_id,
        item_selections=[(item.product_id, item.quantity) for item in payload.items],
    )
    clear_pharmacy_pending_confirmation(request)
    if pending_confirmation_requires_customer_approval(
        request,
        proposed_items=snapshot["proposedItems"],
    ):
        message = payload.message or "The pharmacy reviewed the prescription and needs customer confirmation for the updated order."
        pending_confirmation = create_pharmacy_pending_confirmation(
            request,
            snapshot=snapshot,
            channel=payload.confirmation_channel,
            message=message,
            reason_code=payload.reason_code,
        )
        request.sub_status = "awaiting_customer_confirmation"
        db.add(request)
        proposed_pricing = pending_confirmation["proposedPricing"]
        record_request_event(
            db,
            request=request,
            event_type=CUSTOMER_CONFIRMATION_REQUESTED,
            actor_type="staff",
            actor_id=user_id,
            related_entity_type="assignment",
            related_entity_id=str(assignment.id),
            metadata={
                "confirmationType": DERIVED_ORDER_CHANGE_CONFIRMATION_TYPE,
                "channel": payload.confirmation_channel,
                "reasonCode": payload.reason_code,
                "message": message,
                "proposedTotalAmount": proposed_pricing.get("totalAmount"),
                "proposedTotalText": (
                    proposed_pricing.get("total", {}).get("amountText")
                    if isinstance(proposed_pricing.get("total"), dict)
                    else None
                ),
            },
        )
    else:
        apply_pharmacy_order_snapshot(
            db=db,
            request_id=request.id,
            snapshot=snapshot,
        )

    db.commit()
    db.refresh(request)
    return _serialize_fulfillment_response(db=db, request=request)


@router.post("/orders/{request_id}/fulfillment/branch-accept")
def accept_branch_fulfillment(
    request_id: int,
    payload: AssignBranchRequest | None = Body(default=None),
    db: Session = Depends(get_db),
    actor: AuthorizedActor = Depends(
        require_permission(_MANAGE_PHARMACY_ORDERS_PERMISSION, service_id="pharmacy")
    ),
) -> dict[str, Any]:
    user_id = actor.user_id
    request = _load_pharmacy_service_request(db=db, request_id=request_id)
    assignment = _require_current_assignment(
        db=db,
        request_id=request.id,
        assignment_kind=_BRANCH_ASSIGNMENT_KIND,
    )
    assignment.status = "accepted"
    if payload is not None and payload.assigned_role_code:
        assignment.assigned_role_code = payload.assigned_role_code
    elif not assignment.assigned_role_code:
        assignment.assigned_role_code = "pharmacist"
    db.add(assignment)
    _record_pharmacy_status_transition(
        db=db,
        request=request,
        actor_type="staff",
        actor_id=user_id,
        allowed_states={("created", "awaiting_branch_review")},
        next_status="accepted",
        next_sub_status="preparing",
        related_entity_id=str(assignment.id),
        metadata={
            "action": "branch_accept",
            "assignmentKind": assignment.assignment_kind,
            "assignedRoleCode": assignment.assigned_role_code,
        },
    )
    db.commit()
    db.refresh(request)
    return _serialize_fulfillment_response(db=db, request=request)


@router.post("/orders/{request_id}/fulfillment/resolve-confirmation")
def resolve_customer_confirmation(
    request_id: int,
    payload: ResolveCustomerConfirmationRequest = Body(...),
    db: Session = Depends(get_db),
    actor: AuthorizedActor = Depends(
        require_permission(_MANAGE_PHARMACY_ORDERS_PERMISSION, service_id="pharmacy")
    ),
) -> dict[str, Any]:
    user_id = actor.user_id
    request = _load_pharmacy_service_request(db=db, request_id=request_id)
    if _workflow_state(request) != ("created", "awaiting_customer_confirmation"):
        raise HTTPException(status_code=409, detail="Order is not awaiting customer confirmation")

    resolve_pharmacy_pending_confirmation(
        db=db,
        request=request,
        decision=payload.decision,
        actor_type="staff",
        actor_id=user_id,
        channel=payload.channel,
        message=payload.message,
    )
    db.commit()
    db.refresh(request)
    return _serialize_fulfillment_response(db=db, request=request)


@router.post("/orders/{request_id}/fulfillment/branch-reject")
def reject_branch_fulfillment(
    request_id: int,
    payload: BranchRejectRequest = Body(...),
    db: Session = Depends(get_db),
    actor: AuthorizedActor = Depends(
        require_permission(_MANAGE_PHARMACY_ORDERS_PERMISSION, service_id="pharmacy")
    ),
) -> dict[str, Any]:
    user_id = actor.user_id
    request = _load_pharmacy_service_request(db=db, request_id=request_id)
    assignment = _require_current_assignment(
        db=db,
        request_id=request.id,
        assignment_kind=_BRANCH_ASSIGNMENT_KIND,
    )
    _close_assignment(
        db=db,
        request=request,
        assignment=assignment,
        actor_type="staff",
        actor_id=user_id,
        status="failed" if request.status == "accepted" else "rejected",
        reason_code=payload.reason_code,
    )
    if request.status == "accepted":
        next_status = "failed"
        next_sub_status = "unable_to_fulfill"
    elif payload.reason_code == "invalid_prescription":
        next_status = "rejected"
        next_sub_status = "rejected_invalid_prescription"
    else:
        next_status = "rejected"
        next_sub_status = "rejected_unavailable"
    _record_pharmacy_status_transition(
        db=db,
        request=request,
        actor_type="staff",
        actor_id=user_id,
        allowed_states={
            ("created", "awaiting_branch_review"),
            ("accepted", "preparing"),
        },
        next_status=next_status,
        next_sub_status=next_sub_status,
        related_entity_id=str(assignment.id),
        metadata={
            "action": "branch_reject",
            "reasonCode": payload.reason_code,
            "assignmentKind": assignment.assignment_kind,
        },
    )
    db.commit()
    db.refresh(request)
    return _serialize_fulfillment_response(db=db, request=request)


@router.post("/orders/{request_id}/fulfillment/reroute")
def reroute_branch_fulfillment(
    request_id: int,
    payload: RerouteBranchRequest = Body(...),
    db: Session = Depends(get_db),
    actor: AuthorizedActor = Depends(
        require_permission(_MANAGE_PHARMACY_ORDERS_PERMISSION, service_id="pharmacy")
    ),
) -> dict[str, Any]:
    user_id = actor.user_id
    request = _load_pharmacy_service_request(db=db, request_id=request_id)
    detail = _load_pharmacy_order_detail(db=db, request_id=request.id)
    current_assignment = _require_current_assignment(
        db=db,
        request_id=request.id,
        assignment_kind=_BRANCH_ASSIGNMENT_KIND,
    )
    if current_assignment.pharmacy_id == payload.pharmacy_id:
        raise HTTPException(status_code=400, detail="Reroute pharmacy must be different")
    pharmacy = _load_selected_pharmacy(db=db, pharmacy_id=payload.pharmacy_id)
    _ensure_pharmacy_can_fulfill_order(
        db=db,
        request_id=request.id,
        pharmacy_id=pharmacy.id,
    )

    _close_assignment(
        db=db,
        request=request,
        assignment=current_assignment,
        actor_type="staff",
        actor_id=user_id,
        status="failed" if request.status == "accepted" else "rejected",
        reason_code=payload.reason_code,
    )
    detail.selected_pharmacy_id = pharmacy.id
    db.add(detail)
    new_assignment = _create_assignment(
        db=db,
        request=request,
        assignment_kind=_BRANCH_ASSIGNMENT_KIND,
        pharmacy_id=pharmacy.id,
        assigned_role_code=payload.assigned_role_code or "branch_staff",
        actor_type="staff",
        actor_id=user_id,
        reason_code=payload.reason_code,
    )
    _record_pharmacy_status_transition(
        db=db,
        request=request,
        actor_type="staff",
        actor_id=user_id,
        allowed_states={
            ("created", "awaiting_branch_review"),
            ("accepted", "preparing"),
        },
        next_status="created",
        next_sub_status="awaiting_branch_review",
        related_entity_id=str(new_assignment.id),
        metadata={
            "action": "reroute",
            "reasonCode": payload.reason_code,
            "pharmacyId": str(pharmacy.id),
        },
    )
    db.commit()
    db.refresh(request)
    return _serialize_fulfillment_response(db=db, request=request)


@router.post("/orders/{request_id}/fulfillment/dispatch")
def dispatch_order(
    request_id: int,
    payload: DispatchDeliveryRequest | None = Body(default=None),
    db: Session = Depends(get_db),
    actor: AuthorizedActor = Depends(
        require_permission(_MANAGE_PHARMACY_ORDERS_PERMISSION, service_id="pharmacy")
    ),
) -> dict[str, Any]:
    user_id = actor.user_id
    request = _load_pharmacy_service_request(db=db, request_id=request_id)
    detail = _load_pharmacy_order_detail(db=db, request_id=request.id)
    branch_assignment = _require_current_assignment(
        db=db,
        request_id=request.id,
        assignment_kind=_BRANCH_ASSIGNMENT_KIND,
    )
    if branch_assignment.status != "accepted":
        raise HTTPException(status_code=409, detail="Branch assignment must be accepted before dispatch")
    if _load_current_assignment(
        db=db,
        request_id=request.id,
        assignment_kind=_DELIVERY_ASSIGNMENT_KIND,
    ) is not None:
        raise HTTPException(status_code=409, detail="An active delivery assignment already exists")

    _close_assignment(
        db=db,
        request=request,
        assignment=branch_assignment,
        actor_type="staff",
        actor_id=user_id,
        status="completed",
        reason_code="handoff_to_delivery",
    )
    delivery_assignment = _create_assignment(
        db=db,
        request=request,
        assignment_kind=_DELIVERY_ASSIGNMENT_KIND,
        pharmacy_id=detail.selected_pharmacy_id,
        assigned_role_code=(
            payload.assigned_role_code
            if payload is not None and payload.assigned_role_code
            else "delivery_rider"
        ),
        actor_type="staff",
        actor_id=user_id,
        reason_code="dispatch",
    )
    _record_pharmacy_status_transition(
        db=db,
        request=request,
        actor_type="staff",
        actor_id=user_id,
        allowed_states={("accepted", "preparing")},
        next_status="in_progress",
        next_sub_status="out_for_delivery",
        related_entity_id=str(delivery_assignment.id),
        metadata={
            "action": "dispatch",
            "assignmentKind": delivery_assignment.assignment_kind,
        },
    )
    record_request_event(
        db,
        request=request,
        event_type=FULFILLMENT_STARTED,
        actor_type="staff",
        actor_id=user_id,
        related_entity_type="assignment",
        related_entity_id=str(delivery_assignment.id),
        metadata={
            "assignmentKind": delivery_assignment.assignment_kind,
            "pharmacyId": str(detail.selected_pharmacy_id),
        },
    )
    db.commit()
    db.refresh(request)
    return _serialize_fulfillment_response(db=db, request=request)


@router.post("/orders/{request_id}/fulfillment/deliver")
def deliver_order(
    request_id: int,
    db: Session = Depends(get_db),
    actor: AuthorizedActor = Depends(
        require_permission(_COMPLETE_PHARMACY_DELIVERY_PERMISSION, service_id="pharmacy")
    ),
) -> dict[str, Any]:
    user_id = actor.user_id
    request = _load_pharmacy_service_request(db=db, request_id=request_id)
    delivery_assignment = _require_current_assignment(
        db=db,
        request_id=request.id,
        assignment_kind=_DELIVERY_ASSIGNMENT_KIND,
    )
    _close_assignment(
        db=db,
        request=request,
        assignment=delivery_assignment,
        actor_type="staff",
        actor_id=user_id,
        status="completed",
        reason_code="delivered",
    )
    _record_pharmacy_status_transition(
        db=db,
        request=request,
        actor_type="staff",
        actor_id=user_id,
        allowed_states={("in_progress", "out_for_delivery")},
        next_status="completed",
        next_sub_status="delivered",
        related_entity_id=str(delivery_assignment.id),
        metadata={"action": "deliver"},
    )
    record_request_event(
        db,
        request=request,
        event_type=FULFILLMENT_COMPLETED,
        actor_type="staff",
        actor_id=user_id,
        related_entity_type="assignment",
        related_entity_id=str(delivery_assignment.id),
        metadata={"action": "deliver"},
    )
    db.commit()
    db.refresh(request)
    return _serialize_fulfillment_response(db=db, request=request)


@router.post("/orders/{request_id}/fulfillment/delivery-failed")
def fail_delivery(
    request_id: int,
    payload: DeliveryFailureRequest = Body(...),
    db: Session = Depends(get_db),
    actor: AuthorizedActor = Depends(
        require_permission(_COMPLETE_PHARMACY_DELIVERY_PERMISSION, service_id="pharmacy")
    ),
) -> dict[str, Any]:
    user_id = actor.user_id
    request = _load_pharmacy_service_request(db=db, request_id=request_id)
    delivery_assignment = _require_current_assignment(
        db=db,
        request_id=request.id,
        assignment_kind=_DELIVERY_ASSIGNMENT_KIND,
    )
    _close_assignment(
        db=db,
        request=request,
        assignment=delivery_assignment,
        actor_type="staff",
        actor_id=user_id,
        status="failed",
        reason_code=payload.reason_code,
    )
    _record_pharmacy_status_transition(
        db=db,
        request=request,
        actor_type="staff",
        actor_id=user_id,
        allowed_states={("in_progress", "out_for_delivery")},
        next_status="failed",
        next_sub_status="delivery_failed",
        related_entity_id=str(delivery_assignment.id),
        metadata={"action": "delivery_failed", "reasonCode": payload.reason_code},
    )
    db.commit()
    db.refresh(request)
    return _serialize_fulfillment_response(db=db, request=request)


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
