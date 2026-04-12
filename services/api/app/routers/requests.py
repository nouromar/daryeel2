from __future__ import annotations

from decimal import Decimal
from decimal import ROUND_HALF_UP
from datetime import datetime
from typing import Any, Literal

from fastapi import APIRouter
from fastapi import Depends
from fastapi import HTTPException
from fastapi import Query
from pydantic import BaseModel
from pydantic import Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import get_db
from app.deps import require_access_token_payload
from app.models import RequestEvent
from app.models import ServiceRequest

router = APIRouter(prefix="/v1", tags=["requests"])

_TERMINAL_REQUEST_STATUSES = {"completed", "cancelled", "failed", "rejected"}
_CUSTOMER_ACTION_REQUIRED_STATUSES = {
    "awaiting_info",
    "awaiting_customer_confirmation",
    "awaiting_customer_info",
    "waiting_for_prescription",
    "waiting_price_change_confirmation",
    "waiting_substitution_confirmation",
}


class CompleteRequestActionRequest(BaseModel):
    decision: Literal["approve", "reject", "upload"]
    payload: dict[str, Any] = Field(default_factory=dict)


@router.get("/requests")
def list_customer_requests(
    db: Session = Depends(get_db),
    token_payload=Depends(require_access_token_payload),
) -> dict[str, Any]:
    user_id = int(token_payload.sub)

    rows = list(
        db.scalars(
            select(ServiceRequest)
            .where(ServiceRequest.customer_user_id == user_id)
            .order_by(ServiceRequest.created_at.desc(), ServiceRequest.id.desc())
        )
    )

    latest_events = _latest_events_by_request_id(db, [request.id for request in rows])

    attention: list[dict[str, Any]] = []
    active: list[dict[str, Any]] = []
    history: list[dict[str, Any]] = []

    for request in rows:
        item = _serialize_request_summary(
            request,
            latest_event=latest_events.get(request.id),
        )
        if request.status in _TERMINAL_REQUEST_STATUSES:
            history.append(item)
        elif item["isAttentionRequired"]:
            attention.append(item)
        else:
            active.append(item)

    return {
        "has_requests": bool(attention or active or history),
        "attention": attention,
        "active": active,
        "history": history,
    }


def _serialize_request_summary(
    request: ServiceRequest,
    *,
    latest_event: RequestEvent | None = None,
) -> dict[str, Any]:
    pending_actions = _derive_pending_actions(request=request, latest_event=latest_event)
    attention = _attention_metadata(
        status=request.status,
        latest_event=latest_event,
        pending_action_count=len(pending_actions),
    )
    service_label = _service_label(request.service_id)
    status_label = _status_label(request.status)
    created_label = _format_created_at(request.created_at)
    details_label = _request_details_label(request)

    subtitle_parts: list[str] = []
    if attention["summaryPrefixText"] is not None:
        subtitle_parts.append(attention["summaryPrefixText"])
    subtitle_parts.append(status_label)
    if details_label:
        subtitle_parts.append(details_label)
    if created_label:
        subtitle_parts.append(created_label)

    return {
        "id": str(request.id),
        "service_id": request.service_id,
        "status": request.status,
        "attentionState": attention["attentionState"],
        "isAttentionRequired": attention["isAttentionRequired"],
        "isUpdateAvailable": attention["isUpdateAvailable"],
        "hasUnreadUpdates": attention["hasUnreadUpdates"],
        "pendingActionCount": len(pending_actions),
        "title": service_label,
        "subtitle": " • ".join(subtitle_parts),
        "icon": _service_icon(request.service_id),
        "route": _request_route(request),
        "created_at": request.created_at.isoformat() if request.created_at else None,
    }


@router.get("/requests/detail")
def get_customer_request_detail_by_query(
    request_id: int = Query(..., alias="requestId"),
    db: Session = Depends(get_db),
    token_payload=Depends(require_access_token_payload),
) -> dict[str, Any]:
    user_id = int(token_payload.sub)
    request = _load_customer_request(db=db, user_id=user_id, request_id=request_id)
    return _serialize_request_detail(db=db, request=request)


@router.get("/requests/{request_id}")
def get_customer_request_detail(
    request_id: int,
    db: Session = Depends(get_db),
    token_payload=Depends(require_access_token_payload),
) -> dict[str, Any]:
    user_id = int(token_payload.sub)
    request = _load_customer_request(db=db, user_id=user_id, request_id=request_id)
    return _serialize_request_detail(db=db, request=request)


@router.post("/requests/{request_id}/actions/{action_id}")
def complete_customer_request_action(
    request_id: int,
    action_id: str,
    body: CompleteRequestActionRequest,
    db: Session = Depends(get_db),
    token_payload=Depends(require_access_token_payload),
) -> dict[str, Any]:
    user_id = int(token_payload.sub)
    request = _load_customer_request(db=db, user_id=user_id, request_id=request_id)

    latest_event = _latest_event_for_request(db=db, request_id=request.id)
    pending_actions = _derive_pending_actions(request=request, latest_event=latest_event)
    matched = next((item for item in pending_actions if item["id"] == action_id), None)
    if matched is None:
        raise HTTPException(status_code=409, detail="Action is not available")

    _apply_request_action(
        db=db,
        request=request,
        user_id=user_id,
        action_id=action_id,
        decision=body.decision,
        payload=body.payload,
    )
    db.commit()
    db.refresh(request)
    return _serialize_request_detail(db=db, request=request)


def _load_customer_request(
    *,
    db: Session,
    user_id: int,
    request_id: int,
) -> ServiceRequest:
    request = db.scalar(
        select(ServiceRequest).where(
            ServiceRequest.id == request_id,
            ServiceRequest.customer_user_id == user_id,
        )
    )
    if request is None:
        raise HTTPException(status_code=404, detail="Request not found")
    return request


def _serialize_request_detail(
    *,
    db: Session,
    request: ServiceRequest,
) -> dict[str, Any]:
    events = list(
        db.scalars(
            select(RequestEvent)
            .where(RequestEvent.request_id == request.id)
            .order_by(RequestEvent.created_at.asc(), RequestEvent.id.asc())
        )
    )
    latest_event = events[-1] if events else None
    pending_actions = _derive_pending_actions(request=request, latest_event=latest_event)
    attention = _attention_metadata(
        status=request.status,
        latest_event=latest_event,
        pending_action_count=len(pending_actions),
    )
    summary = _serialize_request_summary(request, latest_event=latest_event)

    return {
        "request": {
            "id": str(request.id),
            "serviceId": request.service_id,
            "title": _service_label(request.service_id),
            "status": request.status,
            "statusLabel": _status_label(request.status),
            "subtitle": summary["subtitle"],
            "detailSubtitle": _request_detail_subtitle(request),
            "createdAt": request.created_at.isoformat() if request.created_at else None,
            "updatedAt": request.updated_at.isoformat() if request.updated_at else None,
            "notes": request.notes,
            "deliveryLocation": _serialize_delivery_location(request.delivery_location_json),
            "paymentSummaryText": _payment_summary_text(request.payment_json),
            "attentionState": attention["attentionState"],
            "isAttentionRequired": attention["isAttentionRequired"],
            "isUpdateAvailable": attention["isUpdateAvailable"],
            "hasUnreadUpdates": attention["hasUnreadUpdates"],
            "pendingActionCount": len(pending_actions),
            "attentionTitle": attention["attentionTitle"],
            "attentionSubtitle": attention["attentionSubtitle"],
        },
        "pendingActions": pending_actions,
        "serviceDetails": _service_details(request),
        "timeline": [_serialize_request_event(event) for event in events],
    }


def _request_route(request: ServiceRequest) -> dict[str, Any]:
    return {
        "route": "customer.schema_screen",
        "value": {
            "screenId": "customer_request_detail",
            "title": _service_label(request.service_id),
            "params": {
                "requestId": str(request.id),
            },
        },
    }


def _service_label(service_id: str) -> str:
    return {
        "pharmacy": "Pharmacy order",
        "ambulance": "Ambulance request",
        "home_visit": "Home visit request",
    }.get(service_id, f"{service_id.replace('_', ' ').title()} request")


def _service_icon(service_id: str) -> str:
    return {
        "pharmacy": "pharmacy",
        "ambulance": "ambulance",
        "home_visit": "home",
    }.get(service_id, "history")


def _status_label(status: str) -> str:
    return {
        "created": "Requested",
        "requested": "Requested",
        "accepted": "Accepted",
        "assigned": "Assigned",
        "in_progress": "In progress",
        "awaiting_info": "Needs info",
        "completed": "Completed",
        "cancelled": "Cancelled",
        "failed": "Failed",
        "rejected": "Rejected",
    }.get(status, status.replace("_", " ").title())


def _serialize_delivery_location(value: Any) -> dict[str, Any] | None:
    if not isinstance(value, dict):
        return None
    text = value.get("text")
    if not isinstance(text, str) or not text.strip():
        return None
    return {"text": text.strip()}


def _payment_summary_text(value: Any) -> str | None:
    if not isinstance(value, dict):
        return None

    method = value.get("method")
    timing = value.get("timing")

    method_label = {
        "cash": "Cash",
        "mobile_money": "Mobile money",
    }.get(method, method.replace("_", " ").title() if isinstance(method, str) else None)
    timing_label = {
        "after_delivery": "after delivery",
        "before_delivery": "before delivery",
    }.get(timing, timing.replace("_", " ").lower() if isinstance(timing, str) else None)

    if method_label and timing_label:
        return f"{method_label} • {timing_label}"
    return method_label or timing_label


def _attention_metadata(
    *,
    status: str,
    latest_event: RequestEvent | None,
    pending_action_count: int,
) -> dict[str, Any]:
    has_unread_updates = _has_unread_updates(latest_event)
    is_attention_required = pending_action_count > 0 or status in _CUSTOMER_ACTION_REQUIRED_STATUSES
    is_update_available = has_unread_updates and not is_attention_required

    if is_attention_required:
        return {
            "attentionState": "action_required",
            "isAttentionRequired": True,
            "isUpdateAvailable": False,
            "hasUnreadUpdates": has_unread_updates,
            "summaryPrefixText": "Action needed",
            "attentionTitle": "Action needed",
            "attentionSubtitle": "This request needs information or confirmation from you.",
        }

    if is_update_available:
        return {
            "attentionState": "update_available",
            "isAttentionRequired": False,
            "isUpdateAvailable": True,
            "hasUnreadUpdates": True,
            "summaryPrefixText": "New update",
            "attentionTitle": "Recent update",
            "attentionSubtitle": "There is a new update on this request.",
        }

    return {
        "attentionState": "none",
        "isAttentionRequired": False,
        "isUpdateAvailable": False,
        "hasUnreadUpdates": has_unread_updates,
        "summaryPrefixText": None,
        "attentionTitle": None,
        "attentionSubtitle": None,
    }


def _derive_pending_actions(
    *,
    request: ServiceRequest,
    latest_event: RequestEvent | None,
) -> list[dict[str, Any]]:
    payload = request.payload_json if isinstance(request.payload_json, dict) else {}
    latest_metadata = (
        latest_event.metadata_json
        if latest_event is not None and isinstance(latest_event.metadata_json, dict)
        else {}
    )

    if request.service_id == "pharmacy":
        return _derive_pharmacy_pending_actions(
            status=request.status,
            payload=payload,
            latest_metadata=latest_metadata,
        )

    return _derive_generic_pending_actions(
        status=request.status,
        latest_metadata=latest_metadata,
    )


def _derive_generic_pending_actions(
    *,
    status: str,
    latest_metadata: dict[str, Any],
) -> list[dict[str, Any]]:
    message = _first_non_empty_string(
        latest_metadata.get("message"),
        latest_metadata.get("note"),
    )

    if status in {"awaiting_info", "awaiting_customer_info"}:
        return [
            {
                "id": "provide_information",
                "type": "provide_information",
                "title": "More information needed",
                "subtitle": message
                or "This request needs more information before it can continue.",
            }
        ]

    if status == "awaiting_customer_confirmation":
        return [
            {
                "id": "confirm_change",
                "type": "confirm_change",
                "title": "Confirmation needed",
                "subtitle": message
                or "Please review and confirm the latest update for this request.",
            }
        ]

    return []


def _derive_pharmacy_pending_actions(
    *,
    status: str,
    payload: dict[str, Any],
    latest_metadata: dict[str, Any],
) -> list[dict[str, Any]]:
    upload_ids = payload.get("prescription_upload_ids")
    has_uploads = isinstance(upload_ids, list) and bool(upload_ids)
    summary_total = payload.get("summary_total")
    amount_text = None
    if isinstance(summary_total, dict):
        amount_text = _first_non_empty_string(summary_total.get("amountText"))

    if status == "waiting_for_prescription" and not has_uploads:
        return [
            {
                "id": "upload_prescription",
                "type": "upload_document",
                "title": "Upload prescription",
                "subtitle": _first_non_empty_string(
                    latest_metadata.get("message"),
                    latest_metadata.get("reason"),
                )
                or "A prescription is required before the pharmacy can continue this order.",
            }
        ]

    if status == "waiting_price_change_confirmation":
        price_message = _first_non_empty_string(
            latest_metadata.get("message"),
            latest_metadata.get("priceChangeMessage"),
        ) or "The pharmacy updated the price and needs your approval."
        if amount_text:
            price_message = _join_non_empty(price_message, f"Updated total: {amount_text}")
        return [
            {
                "id": "confirm_price",
                "type": "confirm_price",
                "title": "Review price update",
                "subtitle": price_message,
            }
        ]

    if status == "waiting_substitution_confirmation":
        substitution_message = _first_non_empty_string(
            latest_metadata.get("message"),
            latest_metadata.get("substitutionSummary"),
            latest_metadata.get("reason"),
        ) or "The pharmacy suggested a substitution and needs your approval."
        return [
            {
                "id": "confirm_substitution",
                "type": "confirm_substitution",
                "title": "Review substitution",
                "subtitle": substitution_message,
            }
        ]

    return _derive_generic_pending_actions(
        status=status,
        latest_metadata=latest_metadata,
    )


def _has_unread_updates(latest_event: RequestEvent | None) -> bool:
    if latest_event is None:
        return False
    return latest_event.type != "created" and latest_event.actor_type != "customer"


def _service_details(request: ServiceRequest) -> dict[str, Any]:
    payload = request.payload_json if isinstance(request.payload_json, dict) else {}

    if request.service_id == "pharmacy":
        return {
            "serviceId": request.service_id,
            "isPharmacy": True,
            "summary": _pharmacy_summary(payload),
            "prescriptionStateText": _pharmacy_prescription_state_text(payload),
            "prescriptionUploads": _pharmacy_prescription_uploads(payload),
        }

    return {
        "serviceId": request.service_id,
        "isPharmacy": False,
        "summary": {},
    }


def _pharmacy_prescription_state_text(payload: dict[str, Any]) -> str | None:
    upload_ids = payload.get("prescription_upload_ids")
    has_uploads = isinstance(upload_ids, list) and bool(upload_ids)
    return "Prescription attached" if has_uploads else None


def _pharmacy_prescription_uploads(payload: dict[str, Any]) -> list[dict[str, str]]:
    upload_ids = payload.get("prescription_upload_ids")
    if not isinstance(upload_ids, list) or not upload_ids:
        return []

    uploads: list[dict[str, str]] = []
    index = 0
    for raw in upload_ids:
        if not isinstance(raw, str) or not raw.strip():
            continue
        index += 1
        upload_id = raw.strip()
        uploads.append(
            {
                "title": f"Prescription {index}",
                "subtitle": upload_id,
                "uploadId": upload_id,
            }
        )
    return uploads


def _pharmacy_summary(payload: dict[str, Any]) -> dict[str, Any]:
    cart_lines = payload.get("cart_lines")
    item_lines: list[str] = []
    items: list[dict[str, str]] = []
    if isinstance(cart_lines, list):
        for line in cart_lines:
            if not isinstance(line, dict):
                continue
            item_lines.append(_order_item_line(line))
            items.append(
                {
                    "title": _product_title(line),
                    "subtitle": _cart_line_subtitle(line),
                }
            )

    summary_lines = payload.get("summary_lines")
    pricing_lines: list[str] = []
    if isinstance(summary_lines, list):
        for line in summary_lines:
            if not isinstance(line, dict):
                continue
            formatted = _summary_line_text(line)
            if formatted is not None:
                pricing_lines.append(formatted)

    summary_total = payload.get("summary_total")
    estimated_total_text = None
    if isinstance(summary_total, dict):
        raw_amount_text = summary_total.get("amountText")
        if isinstance(raw_amount_text, str) and raw_amount_text.strip():
            estimated_total_text = raw_amount_text.strip()
            total_label = _first_non_empty_string(summary_total.get("label")) or "Total"
            pricing_lines.append(f"{total_label}: {estimated_total_text}")

    summary_text = "\n".join(pricing_lines) if pricing_lines else None

    return {
        "items": items,
        "estimatedTotalText": estimated_total_text,
        "summaryText": summary_text,
    }


def _product_title(line: dict[str, Any]) -> str:
    raw = _first_non_empty_string(
        line.get("name"),
        line.get("title"),
        line.get("product_name"),
        line.get("productName"),
    )
    if isinstance(raw, str) and raw.strip():
        return raw.strip()

    product_id = _first_non_empty_string(
        line.get("id"),
        line.get("product_id"),
        line.get("productId"),
    )
    if isinstance(product_id, str) and product_id.strip():
        trimmed = product_id.strip()
        if trimmed.startswith("prod_"):
            trimmed = trimmed[len("prod_"):]
        return _humanize_identifier(trimmed)

    return "Item"


def _cart_line_subtitle(line: dict[str, Any]) -> str:
    raw_quantity = line.get("quantity")
    if isinstance(raw_quantity, int):
        quantity = raw_quantity
    elif isinstance(raw_quantity, float):
        quantity = int(raw_quantity)
    elif isinstance(raw_quantity, str):
        try:
            quantity = int(raw_quantity.strip())
        except ValueError:
            quantity = 0
    else:
        quantity = 0

    # Prefer explicit line total text if present.
    price_text = _first_non_empty_string(
        line.get("lineTotalText"),
        line.get("line_total_text"),
        line.get("lineTotalAmountText"),
        line.get("line_total_amount_text"),
        line.get("totalText"),
        line.get("total_text"),
    )

    # Otherwise, compute a best-effort total using fields already present
    # on the cart line record (no catalog lookups/enrichment).
    if not price_text:
        unit_price_raw = _first_non_empty_string(
            line.get("unitPriceText"),
            line.get("unit_price_text"),
        )

        unit_price_num = None
        for candidate in (
            line.get("unitPrice"),
            line.get("unit_price"),
            line.get("price"),
        ):
            if isinstance(candidate, (int, float)):
                unit_price_num = Decimal(str(candidate))
                break
            if isinstance(candidate, str):
                try:
                    unit_price_num = Decimal(candidate.strip())
                    break
                except Exception:
                    unit_price_num = None

        if unit_price_num is not None and quantity > 0:
            total = (unit_price_num * Decimal(quantity)).quantize(
                Decimal("0.01"),
                rounding=ROUND_HALF_UP,
            )
            price_text = f"${total}"
        else:
            price_text = unit_price_raw

    parts: list[str] = []
    if quantity > 0:
        parts.append(f"Qty {quantity}")
    if price_text:
        parts.append(price_text)

    if not parts:
        return ""
    return "\u2022 " + " \u2022 ".join(parts)


def _order_item_line(line: dict[str, Any]) -> str:
    title = _product_title(line)
    subtitle = _cart_line_subtitle(line)
    return _join_non_empty(title, subtitle)


def _summary_line_text(line: dict[str, Any]) -> str | None:
    label = _first_non_empty_string(line.get("label"))
    amount_text = _first_non_empty_string(line.get("amountText"))
    if label and amount_text:
        return f"{label}: {amount_text}"
    return label or amount_text


def _serialize_request_event(event: RequestEvent) -> dict[str, Any]:
    return {
        "id": str(event.id),
        "type": event.type,
        "title": _event_title(event),
        "subtitle": _event_subtitle(event),
        "createdAt": event.created_at.isoformat() if event.created_at else None,
    }


def _event_title(event: RequestEvent) -> str:
    if event.type == "created":
        return "Request placed"
    if event.type == "status_changed" and event.to_status:
        return f"Status updated to {_status_label(event.to_status)}"
    if event.type == "provider_assigned":
        return "Provider assigned"
    return event.type.replace("_", " ").title()


def _event_subtitle(event: RequestEvent) -> str:
    created_label = _format_created_at(event.created_at) or ""

    if event.type == "created":
        return _join_non_empty("Your request was created.", created_label)
    if event.type == "status_changed" and event.to_status:
        return _join_non_empty(
            f"Status changed to {_status_label(event.to_status)}.",
            created_label,
        )
    if event.type == "provider_assigned":
        return _join_non_empty(
            "A provider has been assigned to your request.",
            created_label,
        )
    return created_label


def _latest_events_by_request_id(
    db: Session,
    request_ids: list[int],
) -> dict[int, RequestEvent]:
    if not request_ids:
        return {}

    events = list(
        db.scalars(
            select(RequestEvent)
            .where(RequestEvent.request_id.in_(request_ids))
            .order_by(RequestEvent.created_at.desc(), RequestEvent.id.desc())
        )
    )

    out: dict[int, RequestEvent] = {}
    for event in events:
        if event.request_id not in out:
            out[event.request_id] = event
    return out


def _latest_event_for_request(*, db: Session, request_id: int) -> RequestEvent | None:
    return db.scalar(
        select(RequestEvent)
        .where(RequestEvent.request_id == request_id)
        .order_by(RequestEvent.created_at.desc(), RequestEvent.id.desc())
    )


def _apply_request_action(
    *,
    db: Session,
    request: ServiceRequest,
    user_id: int,
    action_id: str,
    decision: str,
    payload: dict[str, Any],
) -> None:
    if request.service_id == "pharmacy":
        _apply_pharmacy_request_action(
            db=db,
            request=request,
            user_id=user_id,
            action_id=action_id,
            decision=decision,
            payload=payload,
        )
        return

    raise HTTPException(status_code=400, detail="Unsupported request action")


def _apply_pharmacy_request_action(
    *,
    db: Session,
    request: ServiceRequest,
    user_id: int,
    action_id: str,
    decision: str,
    payload: dict[str, Any],
) -> None:
    if action_id == "confirm_price":
        if decision not in {"approve", "reject"}:
            raise HTTPException(status_code=400, detail="Invalid decision")
        event_type = (
            "price_change_confirmed" if decision == "approve" else "price_change_rejected"
        )
        next_status = "accepted" if decision == "approve" else "rejected"
        message = (
            "Customer approved the price update."
            if decision == "approve"
            else "Customer rejected the price update."
        )
        _update_request_status(
            db=db,
            request=request,
            user_id=user_id,
            next_status=next_status,
            event_type=event_type,
            metadata={"decision": decision, "message": message},
        )
        return

    if action_id == "confirm_substitution":
        if decision not in {"approve", "reject"}:
            raise HTTPException(status_code=400, detail="Invalid decision")
        event_type = (
            "substitution_confirmed"
            if decision == "approve"
            else "substitution_rejected"
        )
        next_status = "accepted" if decision == "approve" else "rejected"
        message = (
            "Customer approved the substitution."
            if decision == "approve"
            else "Customer rejected the substitution."
        )
        _update_request_status(
            db=db,
            request=request,
            user_id=user_id,
            next_status=next_status,
            event_type=event_type,
            metadata={"decision": decision, "message": message},
        )
        return

    if action_id == "upload_prescription":
        if decision != "upload":
            raise HTTPException(status_code=400, detail="Invalid decision")
        upload_ids = payload.get("uploadIds")
        if not isinstance(upload_ids, list) or not upload_ids:
            raise HTTPException(status_code=400, detail="uploadIds are required")

        normalized_ids = [item.strip() for item in upload_ids if isinstance(item, str) and item.strip()]
        if not normalized_ids:
            raise HTTPException(status_code=400, detail="uploadIds are required")

        request_payload = (
            dict(request.payload_json)
            if isinstance(request.payload_json, dict)
            else {}
        )
        existing_upload_ids = request_payload.get("prescription_upload_ids")
        merged_upload_ids = (
            [
                item.strip()
                for item in existing_upload_ids
                if isinstance(item, str) and item.strip()
            ]
            if isinstance(existing_upload_ids, list)
            else []
        )
        for upload_id in normalized_ids:
            if upload_id not in merged_upload_ids:
                merged_upload_ids.append(upload_id)
        request_payload["prescription_upload_ids"] = merged_upload_ids
        request.payload_json = request_payload

        _update_request_status(
            db=db,
            request=request,
            user_id=user_id,
            next_status="accepted",
            event_type="prescription_uploaded",
            metadata={"uploadIds": normalized_ids, "message": "Customer uploaded prescription."},
        )
        return

    raise HTTPException(status_code=400, detail="Unsupported request action")


def _update_request_status(
    *,
    db: Session,
    request: ServiceRequest,
    user_id: int,
    next_status: str,
    event_type: str,
    metadata: dict[str, Any],
) -> None:
    previous_status = request.status
    request.status = next_status
    db.add(request)
    db.add(
        RequestEvent(
            request_id=request.id,
            type=event_type,
            from_status=previous_status,
            to_status=next_status,
            actor_type="customer",
            actor_id=user_id,
            metadata_json=metadata,
        )
    )


def _humanize_identifier(raw: str) -> str:
    normalized = raw.replace("_", " ").strip()
    if not normalized:
        return "Item"
    words = normalized.split()
    return " ".join(_humanize_word(word) for word in words)


def _humanize_word(word: str) -> str:
    lowered = word.lower()
    if lowered.endswith("mg") and len(lowered) > 2 and lowered[:-2].isdigit():
        return f"{lowered[:-2]} mg"
    if lowered.endswith("ml") and len(lowered) > 2 and lowered[:-2].isdigit():
        return f"{lowered[:-2]} ml"
    return lowered.capitalize()


def _join_non_empty(*parts: str) -> str:
    cleaned = [part.strip() for part in parts if part.strip()]
    return " • ".join(cleaned)


def _first_non_empty_string(*values: Any) -> str | None:
    for value in values:
        if isinstance(value, str) and value.strip():
            return value.strip()
    return None


def _format_created_at(value: datetime | None) -> str | None:
    if value is None:
        return None
    return value.strftime("%b %d")


def _format_detail_created_at(value: datetime | None) -> str | None:
    if value is None:
        return None
    return value.strftime("%b %d, %Y")


def _request_detail_subtitle(request: ServiceRequest) -> str:
    return _join_non_empty(
        _status_label(request.status),
        _format_detail_created_at(request.created_at) or "",
    )


def _request_details_label(request: ServiceRequest) -> str | None:
    payload = request.payload_json if isinstance(request.payload_json, dict) else None
    if request.service_id == "pharmacy" and payload is not None:
        cart_lines = payload.get("cart_lines")
        if isinstance(cart_lines, list) and cart_lines:
            total_quantity = 0
            for line in cart_lines:
                if not isinstance(line, dict):
                    continue
                raw_quantity = line.get("quantity")
                if isinstance(raw_quantity, int):
                    total_quantity += raw_quantity
                elif isinstance(raw_quantity, float):
                    total_quantity += int(raw_quantity)
                elif isinstance(raw_quantity, str):
                    try:
                        total_quantity += int(raw_quantity.strip())
                    except ValueError:
                        pass
            if total_quantity > 0:
                return f"{total_quantity} item{'s' if total_quantity != 1 else ''}"
        upload_ids = payload.get("prescription_upload_ids")
        if isinstance(upload_ids, list) and upload_ids:
            return f"{len(upload_ids)} prescription{'s' if len(upload_ids) != 1 else ''}"
    return None