from __future__ import annotations

from typing import Any

from fastapi import APIRouter
from fastapi import Body
from fastapi import Depends
from fastapi import HTTPException
from fastapi import Query
from pydantic import BaseModel
from pydantic import Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import get_db
from app.deps import require_access_token_payload
from app.models import RequestEvent, ServiceRequest, User

router = APIRouter(prefix="/v1/pharmacy", tags=["pharmacy"])


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

    if not payload.cart_lines and payload.prescription_upload_id is None:
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
            "prescription_upload_id": payload.prescription_upload_id,
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
