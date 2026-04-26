from __future__ import annotations

from datetime import datetime
import uuid
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
from app.events import record_request_event
from app.events.types import ATTACHMENT_ADDED
from app.events.types import CUSTOMER_CONFIRMATION_RESOLVED
from app.events.types import REQUEST_CREATED
from app.models import Attachment
from app.models import RequestEvent
from app.models import RequestAttachment
from app.models import ServiceRequest
router = APIRouter(prefix="/v1", tags=["requests"])

_TERMINAL_REQUEST_STATUSES = {"completed", "cancelled", "failed", "rejected"}
_CUSTOMER_ACTION_REQUIRED_STATES = {
    "awaiting_info",
    "awaiting_customer_confirmation",
    "awaiting_customer_info",
    "awaiting_prescription",
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

    active: list[dict[str, Any]] = []
    history: list[dict[str, Any]] = []

    for request in rows:
        item = _serialize_request_summary(
            request,
            latest_event=latest_events.get(request.id),
        )
        if request.status in _TERMINAL_REQUEST_STATUSES:
            history.append(item)
        else:
            active.append(item)

    return {
        "has_requests": bool(active or history),
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
        request=request,
        latest_event=latest_event,
        pending_action_count=len(pending_actions),
    )
    service_label = _service_label(request.service_id)
    status_label = _display_state_label(request)
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
        "sub_status": request.sub_status,
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
        request=request,
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
            "subStatus": request.sub_status,
            "statusLabel": _display_state_label(request),
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
        "serviceDetails": _service_details(db=db, request=request),
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


def _sub_status_label(sub_status: str) -> str:
    return {
        "awaiting_prescription": "Awaiting prescription",
        "awaiting_branch_review": "Awaiting branch review",
        "awaiting_customer_confirmation": "Awaiting confirmation",
        "customer_rejected_changes": "Customer rejected changes",
        "preparing": "Preparing",
        "out_for_delivery": "Out for delivery",
        "delivered": "Delivered",
        "rejected_unavailable": "Unavailable",
        "rejected_invalid_prescription": "Invalid prescription",
        "delivery_failed": "Delivery failed",
        "unable_to_fulfill": "Unable to fulfill",
    }.get(sub_status, sub_status.replace("_", " ").title())


def _request_workflow_state(request: ServiceRequest) -> str:
    if isinstance(request.sub_status, str) and request.sub_status.strip():
        return request.sub_status.strip()
    return request.status


def _display_state_label(request: ServiceRequest) -> str:
    workflow_state = _request_workflow_state(request)
    if workflow_state != request.status:
        return _sub_status_label(workflow_state)
    return _status_label(request.status)


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
    request: ServiceRequest,
    latest_event: RequestEvent | None,
    pending_action_count: int,
) -> dict[str, Any]:
    has_unread_updates = _has_unread_updates(latest_event)
    is_attention_required = (
        pending_action_count > 0
        or _request_workflow_state(request) in _CUSTOMER_ACTION_REQUIRED_STATES
    )
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
    workflow_state = _request_workflow_state(request)

    if request.service_id == "pharmacy":
        return _derive_pharmacy_pending_actions(
            workflow_state=workflow_state,
            payload=payload,
            latest_metadata=latest_metadata,
        )

    return _derive_generic_pending_actions(
        workflow_state=workflow_state,
        latest_metadata=latest_metadata,
    )


def _derive_generic_pending_actions(
    *,
    workflow_state: str,
    latest_metadata: dict[str, Any],
) -> list[dict[str, Any]]:
    message = _first_non_empty_string(
        latest_metadata.get("message"),
        latest_metadata.get("note"),
    )

    if workflow_state in {"awaiting_info", "awaiting_customer_info"}:
        return [
            {
                "id": "provide_information",
                "type": "provide_information",
                "title": "More information needed",
                "subtitle": message
                or "This request needs more information before it can continue.",
            }
        ]

    if workflow_state == "awaiting_customer_confirmation":
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
    workflow_state: str,
    payload: dict[str, Any],
    latest_metadata: dict[str, Any],
) -> list[dict[str, Any]]:
    upload_ids = payload.get("prescription_upload_ids")
    has_uploads = isinstance(upload_ids, list) and bool(upload_ids)
    summary_total = payload.get("summary_total")
    amount_text = None
    if isinstance(summary_total, dict):
        amount_text = _first_non_empty_string(summary_total.get("amountText"))

    confirmation_type = _first_non_empty_string(
        latest_metadata.get("confirmationType"),
        latest_metadata.get("confirmation_type"),
    )

    if workflow_state in {"awaiting_prescription", "waiting_for_prescription"} and not has_uploads:
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

    if workflow_state == "waiting_price_change_confirmation" or (
        workflow_state == "awaiting_customer_confirmation" and confirmation_type == "price_change"
    ):
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

    if workflow_state == "waiting_substitution_confirmation" or (
        workflow_state == "awaiting_customer_confirmation" and confirmation_type == "substitution"
    ):
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
        workflow_state=workflow_state,
        latest_metadata=latest_metadata,
    )


def _has_unread_updates(latest_event: RequestEvent | None) -> bool:
    if latest_event is None:
        return False
    return latest_event.type != REQUEST_CREATED and latest_event.actor_type != "customer"


def _service_details(*, db: Session, request: ServiceRequest) -> dict[str, Any]:
    payload = request.payload_json if isinstance(request.payload_json, dict) else {}

    if request.service_id == "pharmacy":
        enriched_payload = _enrich_pharmacy_payload_with_prescription_uploads(
            db,
            request=request,
            payload=payload,
        )
        return {
            "serviceId": request.service_id,
            "isPharmacy": True,
            "payload": enriched_payload,
        }

    return {
        "serviceId": request.service_id,
        "isPharmacy": False,
        "payload": payload,
    }


def _enrich_pharmacy_payload_with_prescription_uploads(
    db: Session,
    *,
    request: ServiceRequest,
    payload: dict[str, Any],
) -> dict[str, Any]:
    rows = db.execute(
        select(RequestAttachment, Attachment)
        .join(Attachment, Attachment.id == RequestAttachment.attachment_id)
        .where(
            RequestAttachment.request_id == request.id,
            RequestAttachment.attachment_type == "prescription",
            RequestAttachment.status == "active",
        )
        .order_by(RequestAttachment.created_at.asc(), RequestAttachment.id.asc())
    ).all()

    if not rows:
        return payload

    uploads: list[dict[str, Any]] = []
    upload_ids: list[str] = []
    for request_attachment, attachment in rows:
        attachment_id = str(attachment.id)
        upload_ids.append(attachment_id)
        uploads.append(
            {
                "id": attachment_id,
                "filename": (attachment.filename or attachment_id).strip() or attachment_id,
            }
        )

    out = dict(payload)
    out["prescription_upload_ids"] = upload_ids
    out["prescription_uploads"] = uploads
    return out


def _normalize_attachment_ids(values: Any) -> list[uuid.UUID]:
    if not isinstance(values, list):
        return []

    normalized: list[uuid.UUID] = []
    seen: set[uuid.UUID] = set()
    for raw in values:
        if not isinstance(raw, str):
            continue
        candidate = raw.strip()
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


def _load_existing_attachments(
    *,
    db: Session,
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
        raise HTTPException(status_code=400, detail="Unknown attachment id")
    return [rows_by_id[attachment_id] for attachment_id in attachment_ids]


def _link_prescription_attachments(
    *,
    db: Session,
    request: ServiceRequest,
    attachments: list[Attachment],
    actor_type: str,
    actor_id: int | None,
) -> list[str]:
    if not attachments:
        return []

    attachment_ids = [attachment.id for attachment in attachments]
    existing_rows = list(
        db.scalars(
            select(RequestAttachment).where(
                RequestAttachment.request_id == request.id,
                RequestAttachment.attachment_id.in_(attachment_ids),
                RequestAttachment.attachment_type == "prescription",
                RequestAttachment.status == "active",
            )
        )
    )
    existing_attachment_ids = {row.attachment_id for row in existing_rows}

    linked_ids: list[str] = []
    for attachment in attachments:
        linked_ids.append(str(attachment.id))
        if attachment.id in existing_attachment_ids:
            continue

        db.add(
            RequestAttachment(
                request_id=request.id,
                attachment_id=attachment.id,
                attachment_type="prescription",
                status="active",
                uploaded_by_actor_type=actor_type,
                uploaded_by_actor_id=actor_id,
            )
        )
        record_request_event(
            db,
            request=request,
            event_type=ATTACHMENT_ADDED,
            actor_type=actor_type,
            actor_id=actor_id,
            related_entity_type="attachment",
            related_entity_id=str(attachment.id),
            metadata={"attachmentType": "prescription"},
        )
    return linked_ids


def _serialize_request_event(event: RequestEvent) -> dict[str, Any]:
    status_title = _status_label(event.to_status) if event.to_status else _event_title(event)
    return {
        "id": str(event.id),
        "type": event.type,
        "title": status_title,
        "subtitle": _format_created_at(event.created_at) or "",
        "createdAt": event.created_at.isoformat() if event.created_at else None,
    }


def _event_title(event: RequestEvent) -> str:
    return event.type.replace("_", " ").title()


def _event_subtitle(event: RequestEvent) -> str:
    return _format_created_at(event.created_at) or ""


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
        next_status = "accepted" if decision == "approve" else "rejected"
        next_sub_status = None if decision == "approve" else "customer_rejected_changes"
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
            next_sub_status=next_sub_status,
            event_type=CUSTOMER_CONFIRMATION_RESOLVED,
            metadata={
                "confirmationType": "price_change",
                "decision": decision,
                "channel": "in_app",
                "message": message,
            },
        )
        return

    if action_id == "confirm_substitution":
        if decision not in {"approve", "reject"}:
            raise HTTPException(status_code=400, detail="Invalid decision")
        next_status = "accepted" if decision == "approve" else "rejected"
        next_sub_status = None if decision == "approve" else "customer_rejected_changes"
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
            next_sub_status=next_sub_status,
            event_type=CUSTOMER_CONFIRMATION_RESOLVED,
            metadata={
                "confirmationType": "substitution",
                "decision": decision,
                "channel": "in_app",
                "message": message,
            },
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

        attachment_ids = _normalize_attachment_ids(normalized_ids)
        if normalized_ids and not attachment_ids:
            raise HTTPException(status_code=400, detail="Unknown attachment id")
        attachments = _load_existing_attachments(
            db=db,
            attachment_ids=attachment_ids,
        )
        linked_upload_ids = _link_prescription_attachments(
            db=db,
            request=request,
            attachments=attachments,
            actor_type="customer",
            actor_id=user_id,
        )

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
        for upload_id in linked_upload_ids:
            if upload_id not in merged_upload_ids:
                merged_upload_ids.append(upload_id)
        request_payload["prescription_upload_ids"] = merged_upload_ids
        request.payload_json = request_payload

        request.sub_status = "awaiting_branch_review"
        db.add(request)
        return

    raise HTTPException(status_code=400, detail="Unsupported request action")


def _update_request_status(
    *,
    db: Session,
    request: ServiceRequest,
    user_id: int,
    next_status: str,
    next_sub_status: str | None,
    event_type: str,
    metadata: dict[str, Any],
) -> None:
    record_request_event(
        db,
        request=request,
        event_type=event_type,
        actor_type="customer",
        actor_id=user_id,
        to_status=next_status,
        sub_status=next_sub_status,
        metadata=metadata,
    )


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
        _display_state_label(request),
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
