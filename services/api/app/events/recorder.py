from __future__ import annotations

from typing import Any

from sqlalchemy.orm import Session

from app.events.types import REQUEST_CREATED
from app.events.types import REQUEST_EVENT_TYPES
from app.events.types import REQUEST_STATUS_CHANGED
from app.models import RequestEvent
from app.models import ServiceRequest

_MISSING = object()


def record_request_event(
    db: Session,
    *,
    request: ServiceRequest,
    event_type: str,
    actor_type: str,
    actor_id: int | None,
    from_status: str | None | object = _MISSING,
    to_status: str | object = _MISSING,
    sub_status: str | None | object = _MISSING,
    related_entity_type: str | None = None,
    related_entity_id: str | None = None,
    metadata: dict[str, Any] | None = None,
) -> RequestEvent:
    if event_type not in REQUEST_EVENT_TYPES:
        raise ValueError(f"Unsupported request event type: {event_type}")

    if event_type in {REQUEST_CREATED, REQUEST_STATUS_CHANGED} and to_status is _MISSING:
        raise ValueError(f"{event_type} requires to_status")

    resolved_from_status: str | None = None
    resolved_to_status: str | None = None

    if to_status is not _MISSING:
        if not isinstance(to_status, str) or not to_status.strip():
            raise ValueError("to_status must be a non-empty string when provided")
        if from_status is _MISSING:
            resolved_from_status = request.status
        elif isinstance(from_status, str):
            resolved_from_status = from_status.strip()
        else:
            resolved_from_status = None
        resolved_to_status = to_status.strip()
        request.status = resolved_to_status
        db.add(request)

    if sub_status is not _MISSING:
        request.sub_status = sub_status.strip() if isinstance(sub_status, str) else None
        db.add(request)

    event = RequestEvent(
        request_id=request.id,
        type=event_type,
        from_status=resolved_from_status,
        to_status=resolved_to_status,
        actor_type=actor_type,
        actor_id=actor_id,
        related_entity_type=related_entity_type,
        related_entity_id=related_entity_id,
        metadata_json=metadata or None,
    )
    db.add(event)
    return event
