from __future__ import annotations

from datetime import datetime, timezone
from decimal import Decimal
import uuid
from typing import Any, Sequence

from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.events import record_request_event
from app.events.types import ASSIGNMENT_CLOSED
from app.events.types import CUSTOMER_CONFIRMATION_RESOLVED
from app.models import (
    PharmacyOrderAssignment,
    PharmacyOrderDetail,
    PharmacyOrderItem,
    PharmacyProduct,
    Product,
    ServiceRequest,
)

BRANCH_ASSIGNMENT_KIND = "branch_fulfillment"
OPEN_ASSIGNMENT_STATUSES = {"active", "accepted"}
DERIVED_ORDER_CHANGE_CONFIRMATION_TYPE = "derived_order_change"

_PENDING_CONFIRMATION_KEY = "pendingConfirmation"
_SUBMITTED_ORDER_KEY = "submittedOrder"


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _format_money(*, amount: Decimal | float | int, currency_code: str) -> str:
    normalized = amount if isinstance(amount, Decimal) else Decimal(str(amount))
    if currency_code.upper() == "USD":
        return f"${normalized:.2f}"
    return f"{currency_code.upper()} {normalized:.2f}"


def _request_payload(request: ServiceRequest) -> dict[str, Any]:
    if isinstance(request.payload_json, dict):
        return dict(request.payload_json)
    return {}


def _set_request_payload(request: ServiceRequest, payload: dict[str, Any]) -> None:
    request.payload_json = payload or None


def _normalize_item_selections(
    item_selections: Sequence[tuple[uuid.UUID, int]],
) -> list[tuple[uuid.UUID, int]]:
    ordered: list[tuple[uuid.UUID, int]] = []
    by_product_id: dict[uuid.UUID, int] = {}
    for product_id, quantity in item_selections:
        if quantity <= 0:
            continue
        if product_id not in by_product_id:
            ordered.append((product_id, quantity))
            by_product_id[product_id] = len(ordered) - 1
            continue
        index = by_product_id[product_id]
        existing_product_id, existing_quantity = ordered[index]
        ordered[index] = (existing_product_id, existing_quantity + quantity)
    return ordered


def set_submitted_order_snapshot(
    request: ServiceRequest,
    *,
    item_selections: Sequence[tuple[uuid.UUID, int]],
) -> None:
    payload = _request_payload(request)
    payload[_SUBMITTED_ORDER_KEY] = {
        "items": [
            {
                "productId": str(product_id),
                "quantity": quantity,
            }
            for product_id, quantity in _normalize_item_selections(item_selections)
        ]
    }
    _set_request_payload(request, payload)


def get_pharmacy_pending_confirmation(
    request: ServiceRequest,
) -> dict[str, Any] | None:
    payload = _request_payload(request)
    pending = payload.get(_PENDING_CONFIRMATION_KEY)
    return pending if isinstance(pending, dict) else None


def serialize_pharmacy_pending_confirmation(
    request: ServiceRequest,
) -> dict[str, Any] | None:
    pending = get_pharmacy_pending_confirmation(request)
    if pending is None:
        return None

    proposed_items_raw = pending.get("proposedItems")
    proposed_items = proposed_items_raw if isinstance(proposed_items_raw, list) else []
    proposed_pricing = (
        pending.get("proposedPricing")
        if isinstance(pending.get("proposedPricing"), dict)
        else None
    )

    return {
        "confirmationType": str(
            pending.get("confirmationType") or DERIVED_ORDER_CHANGE_CONFIRMATION_TYPE
        ),
        "channel": str(pending.get("channel") or "phone_call"),
        "reasonCode": pending.get("reasonCode"),
        "message": pending.get("message"),
        "proposedItems": proposed_items,
        "proposedPricing": proposed_pricing,
    }


def clear_pharmacy_pending_confirmation(request: ServiceRequest) -> None:
    payload = _request_payload(request)
    payload.pop(_PENDING_CONFIRMATION_KEY, None)
    _set_request_payload(request, payload)


def create_pharmacy_pending_confirmation(
    request: ServiceRequest,
    *,
    snapshot: dict[str, Any],
    channel: str,
    message: str,
    reason_code: str | None,
) -> dict[str, Any]:
    payload = _request_payload(request)
    pending = {
        "confirmationType": DERIVED_ORDER_CHANGE_CONFIRMATION_TYPE,
        "channel": channel,
        "reasonCode": reason_code,
        "message": message,
        "proposedItems": snapshot["proposedItems"],
        "proposedPricing": snapshot["proposedPricing"],
    }
    payload[_PENDING_CONFIRMATION_KEY] = pending
    _set_request_payload(request, payload)
    return pending


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


def build_pharmacy_order_snapshot(
    *,
    db: Session,
    selected_pharmacy_id: uuid.UUID,
    item_selections: Sequence[tuple[uuid.UUID, int]],
) -> dict[str, Any]:
    normalized_selections = _normalize_item_selections(item_selections)
    if not normalized_selections:
        raise HTTPException(status_code=400, detail="Review must include one or more order items")

    product_ids = [product_id for product_id, _ in normalized_selections]
    offer_by_product_id = _load_pharmacy_product_offers(
        db=db,
        pharmacy_id=selected_pharmacy_id,
        product_ids=product_ids,
    )
    missing_product_ids = [
        str(product_id)
        for product_id in product_ids
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
    proposed_items: list[dict[str, Any]] = []
    for product_id, quantity in normalized_selections:
        product, offer = offer_by_product_id[product_id]
        currency_code = offer.currency_code
        unit_price_amount = offer.price_amount
        line_subtotal_amount = unit_price_amount * quantity
        line_total_amount = line_subtotal_amount
        subtotal_amount += line_subtotal_amount
        proposed_items.append(
            {
                "productId": str(product.id),
                "quantity": quantity,
                "productName": product.name,
                "form": product.form,
                "strength": product.strength,
                "rxRequired": product.rx_required,
                "sellerSku": offer.seller_sku,
                "unitPriceAmount": float(unit_price_amount),
                "lineSubtotalAmount": float(line_subtotal_amount),
                "lineDiscountAmount": None,
                "lineTaxAmount": None,
                "lineTotalAmount": float(line_total_amount),
            }
        )

    total_amount = subtotal_amount - discount_amount + fee_amount + tax_amount
    proposed_pricing = {
        "currencyCode": currency_code,
        "subtotalAmount": float(subtotal_amount),
        "discountAmount": float(discount_amount),
        "feeAmount": float(fee_amount),
        "taxAmount": float(tax_amount),
        "totalAmount": float(total_amount),
        "lines": [
            {
                "id": "subtotal",
                "label": "Subtotal",
                "amount": float(subtotal_amount),
                "amountText": _format_money(
                    amount=subtotal_amount,
                    currency_code=currency_code,
                ),
            }
        ],
        "total": {
            "label": "Total",
            "amount": float(total_amount),
            "amountText": _format_money(
                amount=total_amount,
                currency_code=currency_code,
            ),
        },
    }
    return {
        "proposedItems": proposed_items,
        "proposedPricing": proposed_pricing,
    }


def pending_confirmation_requires_customer_approval(
    request: ServiceRequest,
    *,
    proposed_items: Sequence[dict[str, Any]],
) -> bool:
    payload = _request_payload(request)
    submitted_order = payload.get(_SUBMITTED_ORDER_KEY)
    if not isinstance(submitted_order, dict):
        return False

    submitted_items = submitted_order.get("items")
    if not isinstance(submitted_items, list):
        return False

    submitted_quantities: dict[str, int] = {}
    for item in submitted_items:
        if not isinstance(item, dict):
            continue
        product_id = item.get("productId")
        quantity = item.get("quantity")
        if not isinstance(product_id, str):
            continue
        parsed_quantity = int(quantity) if isinstance(quantity, int) else 0
        if parsed_quantity <= 0:
            continue
        submitted_quantities[product_id] = parsed_quantity

    if not submitted_quantities:
        return False

    proposed_quantities: dict[str, int] = {}
    for item in proposed_items:
        if not isinstance(item, dict):
            continue
        product_id = item.get("productId")
        quantity = item.get("quantity")
        if not isinstance(product_id, str):
            continue
        parsed_quantity = int(quantity) if isinstance(quantity, int) else 0
        if parsed_quantity <= 0:
            continue
        proposed_quantities[product_id] = parsed_quantity

    for product_id, quantity in submitted_quantities.items():
        if proposed_quantities.get(product_id) != quantity:
            return True
    return False


def apply_pharmacy_order_snapshot(
    *,
    db: Session,
    request_id: int,
    snapshot: dict[str, Any],
) -> None:
    detail = db.scalar(
        select(PharmacyOrderDetail).where(PharmacyOrderDetail.request_id == request_id)
    )
    if detail is None:
        raise HTTPException(status_code=404, detail="Pharmacy order detail not found")

    proposed_pricing = snapshot.get("proposedPricing")
    proposed_items_raw = snapshot.get("proposedItems")
    if not isinstance(proposed_pricing, dict) or not isinstance(proposed_items_raw, list):
        raise HTTPException(status_code=409, detail="Pending confirmation snapshot is invalid")

    detail.currency_code = str(proposed_pricing.get("currencyCode") or detail.currency_code)
    detail.subtotal_amount = Decimal(str(proposed_pricing.get("subtotalAmount") or "0"))
    detail.discount_amount = Decimal(str(proposed_pricing.get("discountAmount") or "0"))
    detail.fee_amount = Decimal(str(proposed_pricing.get("feeAmount") or "0"))
    detail.tax_amount = Decimal(str(proposed_pricing.get("taxAmount") or "0"))
    detail.total_amount = Decimal(str(proposed_pricing.get("totalAmount") or "0"))
    db.add(detail)

    existing_items = list(
        db.scalars(
            select(PharmacyOrderItem).where(PharmacyOrderItem.request_id == request_id)
        )
    )
    for existing_item in existing_items:
        db.delete(existing_item)

    for item in proposed_items_raw:
        if not isinstance(item, dict):
            continue
        db.add(
            PharmacyOrderItem(
                request_id=request_id,
                product_id=uuid.UUID(str(item["productId"])),
                quantity=int(item["quantity"]),
                product_name=str(item["productName"]),
                form=(
                    str(item["form"])
                    if isinstance(item.get("form"), str) and item["form"]
                    else None
                ),
                strength=(
                    str(item["strength"])
                    if isinstance(item.get("strength"), str) and item["strength"]
                    else None
                ),
                rx_required=bool(item.get("rxRequired")),
                seller_sku=(
                    str(item["sellerSku"])
                    if isinstance(item.get("sellerSku"), str) and item["sellerSku"]
                    else None
                ),
                unit_price_amount=Decimal(str(item["unitPriceAmount"])),
                line_subtotal_amount=Decimal(str(item["lineSubtotalAmount"])),
                line_discount_amount=(
                    Decimal(str(item["lineDiscountAmount"]))
                    if item.get("lineDiscountAmount") is not None
                    else None
                ),
                line_tax_amount=(
                    Decimal(str(item["lineTaxAmount"]))
                    if item.get("lineTaxAmount") is not None
                    else None
                ),
                line_total_amount=Decimal(str(item["lineTotalAmount"])),
            )
        )


def _load_current_branch_assignment(
    *,
    db: Session,
    request_id: int,
) -> PharmacyOrderAssignment | None:
    rows = list(
        db.scalars(
            select(PharmacyOrderAssignment)
            .where(
                PharmacyOrderAssignment.request_id == request_id,
                PharmacyOrderAssignment.assignment_kind == BRANCH_ASSIGNMENT_KIND,
                PharmacyOrderAssignment.status.in_(tuple(OPEN_ASSIGNMENT_STATUSES)),
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


def _require_current_branch_assignment(
    *,
    db: Session,
    request_id: int,
) -> PharmacyOrderAssignment:
    assignment = _load_current_branch_assignment(db=db, request_id=request_id)
    if assignment is None:
        raise HTTPException(status_code=409, detail="No active assignment for this phase")
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
) -> None:
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


def resolve_pharmacy_pending_confirmation(
    *,
    db: Session,
    request: ServiceRequest,
    decision: str,
    actor_type: str,
    actor_id: int | None,
    channel: str,
    message: str | None = None,
) -> None:
    if decision not in {"approve", "reject"}:
        raise HTTPException(status_code=400, detail="Invalid decision")

    pending_confirmation = get_pharmacy_pending_confirmation(request)
    if pending_confirmation is None:
        raise HTTPException(status_code=409, detail="No pending customer confirmation exists")

    assignment = _require_current_branch_assignment(db=db, request_id=request.id)
    confirmation_type = str(
        pending_confirmation.get("confirmationType")
        or DERIVED_ORDER_CHANGE_CONFIRMATION_TYPE
    )
    pending_message = (
        pending_confirmation.get("message")
        if isinstance(pending_confirmation.get("message"), str)
        else None
    )
    reason_code = (
        pending_confirmation.get("reasonCode")
        if isinstance(pending_confirmation.get("reasonCode"), str)
        else None
    )

    if decision == "approve":
        apply_pharmacy_order_snapshot(
            db=db,
            request_id=request.id,
            snapshot=pending_confirmation,
        )
        clear_pharmacy_pending_confirmation(request)
        if assignment.status != "accepted":
            assignment.status = "accepted"
        if not assignment.assigned_role_code:
            assignment.assigned_role_code = "pharmacist"
        db.add(assignment)
        resolved_message = (
            message
            or pending_message
            or "Customer approved the updated pharmacy order."
        )
        record_request_event(
            db,
            request=request,
            event_type=CUSTOMER_CONFIRMATION_RESOLVED,
            actor_type=actor_type,
            actor_id=actor_id,
            to_status="accepted",
            sub_status="preparing",
            related_entity_type="assignment",
            related_entity_id=str(assignment.id),
            metadata={
                "confirmationType": confirmation_type,
                "decision": decision,
                "channel": channel,
                "reasonCode": reason_code,
                "message": resolved_message,
            },
        )
        return

    clear_pharmacy_pending_confirmation(request)
    _close_assignment(
        db=db,
        request=request,
        assignment=assignment,
        actor_type=actor_type,
        actor_id=actor_id,
        status="rejected",
        reason_code="customer_rejected_changes",
    )
    resolved_message = (
        message
        or pending_message
        or "Customer rejected the updated pharmacy order."
    )
    record_request_event(
        db,
        request=request,
        event_type=CUSTOMER_CONFIRMATION_RESOLVED,
        actor_type=actor_type,
        actor_id=actor_id,
        to_status="rejected",
        sub_status="customer_rejected_changes",
        related_entity_type="assignment",
        related_entity_id=str(assignment.id),
        metadata={
            "confirmationType": confirmation_type,
            "decision": decision,
            "channel": channel,
            "reasonCode": reason_code,
            "message": resolved_message,
        },
    )
