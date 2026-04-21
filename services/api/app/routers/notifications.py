from __future__ import annotations

from collections import Counter
from datetime import datetime
from typing import Any

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import get_db
from app.deps import require_access_token_payload
from app.models import ServiceRequest
from app.routers import requests as requests_router

router = APIRouter(prefix="/v1/notifications", tags=["notifications"])


def _parse_dt(value: Any) -> datetime | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        return value
    # We store ISO8601 strings in API responses, so tolerate that too.
    if isinstance(value, str):
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return None
    return None


def _is_action_required(summary: dict[str, Any]) -> bool:
    pending = summary.get("pendingActionCount")
    if isinstance(pending, int) and pending > 0:
        return True

    attention_state = str(summary.get("attentionState") or "").strip().lower()
    return attention_state in {"action_required", "urgent", "attention"}


def _notification_from_request_summary(summary: dict[str, Any]) -> dict[str, Any]:
    kind = "action_required" if _is_action_required(summary) else "fyi"

    return {
        "id": f"request:{summary.get('id')}",
        "entity": {"kind": "request", "id": summary.get("id")},
        "kind": kind,
        "service": summary.get("service_id"),
        "title": summary.get("title"),
        "subtitle": summary.get("subtitle"),
        "icon": summary.get("icon"),
        "route": summary.get("route"),
        "createdAt": summary.get("created_at"),
        "hasUnreadUpdates": summary.get("hasUnreadUpdates", False),
        "pendingActionCount": summary.get("pendingActionCount", 0),
        "attentionState": summary.get("attentionState"),
    }


def _sort_key(item: dict[str, Any]) -> tuple[int, float]:
    kind = str(item.get("kind") or "").strip().lower()
    is_action = 1 if kind == "action_required" else 0

    created_at = _parse_dt(item.get("createdAt"))
    ts = created_at.timestamp() if created_at else 0.0

    # Higher = more important / newer.
    return (is_action, ts)


@router.get("")
def list_notifications(
    db: Session = Depends(get_db),
    token_payload=Depends(require_access_token_payload),
) -> dict[str, Any]:
    user_id = int(token_payload.sub)

    requests = list(
        db.scalars(
            select(ServiceRequest)
            .where(ServiceRequest.customer_user_id == user_id)
            .where(
                ServiceRequest.status.notin_(
                    requests_router._TERMINAL_REQUEST_STATUSES
                )
            )
            .order_by(ServiceRequest.created_at.desc(), ServiceRequest.id.desc())
        )
    )

    latest_by_id = requests_router._latest_events_by_request_id(
        db,
        [r.id for r in requests],
    )

    items: list[dict[str, Any]] = []
    for req in requests:
        summary = requests_router._serialize_request_summary(
            req,
            latest_event=latest_by_id.get(req.id),
        )
        items.append(_notification_from_request_summary(summary))

    items.sort(key=_sort_key, reverse=True)

    return {
        "schemaVersion": "1.0",
        "items": items,
        "has_notifications": len(items) > 0,
    }


@router.get("/home-summary")
def home_summary(
    db: Session = Depends(get_db),
    token_payload=Depends(require_access_token_payload),
) -> dict[str, Any]:
    payload = list_notifications(db=db, token_payload=token_payload)
    items = list(payload.get("items") or [])

    if not items:
        return {
            "schemaVersion": "1.0",
            "primary": None,
            "moreCount": 0,
            "moreByService": {},
            "activeCount": 0,
        }

    primary = items[0]
    remaining = items[1:]

    counts = Counter(
        str(n.get("service") or "").strip()
        for n in remaining
        if str(n.get("service") or "").strip()
    )

    return {
        "schemaVersion": "1.0",
        "primary": primary,
        "moreCount": len(remaining),
        "moreByService": dict(counts),
        "activeCount": len(items),
    }
