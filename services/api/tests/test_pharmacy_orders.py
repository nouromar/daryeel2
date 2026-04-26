from __future__ import annotations

import os
import tempfile
import uuid
from pathlib import Path

from fastapi.testclient import TestClient

from app.auth import create_access_token
from app.main import app


def _init_sqlite_db() -> None:
    # Use a file-backed sqlite DB so the API's session-per-request sees the same DB.
    tmpdir = Path(tempfile.mkdtemp(prefix="daryeel_api_test_"))
    db_path = tmpdir / "test.db"
    url = f"sqlite+pysqlite:///{db_path}"

    os.environ["DATABASE_URL"] = url
    os.environ["API_DATABASE_URL"] = url

    # Reset cached engine between tests.
    import app.db as dbmod

    dbmod._engine = None

    engine = dbmod.get_engine()

    from app.models import Base, User

    Base.metadata.create_all(bind=engine)

    # Seed a user.
    with dbmod.SessionLocal() as db:
        user = User(phone="+252610000001")
        db.add(user)
        db.commit()
        db.refresh(user)


def _auth_header_for_user_id(user_id: int) -> dict[str, str]:
    # Default secret is fine for tests.
    token = create_access_token(secret="dev-insecure-secret", user_id=user_id, phone="+252610000001", ttl_seconds=60)
    return {"Authorization": f"Bearer {token}"}


def _catalog_item_by_name(client: TestClient, name: str) -> dict[str, object]:
    res = client.get("/v1/pharmacy/catalog")
    assert res.status_code == 200
    items = res.json()["items"]
    return next(item for item in items if item["name"] == name)


def test_create_pharmacy_order_requires_cart_or_prescription() -> None:
    _init_sqlite_db()
    client = TestClient(app)

    res = client.post(
        "/v1/pharmacy/orders",
        headers=_auth_header_for_user_id(1),
        json={
            "service_id": "pharmacy",
            "order": {
                "items": [],
                "prescriptionAttachmentIds": [],
            },
        },
    )

    assert res.status_code == 400


def test_create_pharmacy_order_creates_request_and_event() -> None:
    _init_sqlite_db()
    client = TestClient(app)
    paracetamol = _catalog_item_by_name(client, "Paracetamol 500mg")

    res = client.post(
        "/v1/pharmacy/orders",
        headers=_auth_header_for_user_id(1),
        json={
            "service_id": "pharmacy",
            "delivery_location": {"text": "Hodan", "lat": 2.046934, "lng": 45.318162, "accuracy_m": 15},
            "payment": {"method": "cash", "timing": "after_delivery"},
            "notes": "Leave at door",
            "order": {
                "items": [
                    {
                        "productId": paracetamol["id"],
                        "quantity": 2,
                    },
                ],
                "prescriptionAttachmentIds": [],
            },
        },
    )

    assert res.status_code == 200
    payload = res.json()
    assert "order" in payload
    order = payload["order"]
    assert order["service_id"] == "pharmacy"
    assert order["status"] == "created"
    assert order["sub_status"] == "awaiting_branch_review"
    assert order["customer_user_id"] == "1"

    # Confirm DB rows exist.
    import app.db as dbmod

    from sqlalchemy import select

    from app.models import PharmacyOrderDetail, PharmacyOrderItem, RequestEvent, ServiceRequest

    with dbmod.SessionLocal() as db:
        sr = db.scalar(select(ServiceRequest).where(ServiceRequest.id == int(order["id"])))
        assert sr is not None
        assert sr.service_id == "pharmacy"
        assert sr.sub_status == "awaiting_branch_review"
        assert sr.notes == "Leave at door"
        assert sr.payment_json == {"method": "cash", "timing": "after_delivery"}
        assert sr.delivery_location_json["text"] == "Hodan"
        assert sr.payload_json is None
        detail = db.scalar(
            select(PharmacyOrderDetail).where(PharmacyOrderDetail.request_id == sr.id)
        )
        assert detail is not None
        assert float(detail.subtotal_amount) == 2.0
        assert float(detail.total_amount) == 2.0
        item = db.scalar(
            select(PharmacyOrderItem).where(PharmacyOrderItem.request_id == sr.id)
        )
        assert item is not None
        assert str(item.product_id) == paracetamol["id"]
        assert item.quantity == 2
        assert float(item.unit_price_amount) == 1.0
        assert float(item.line_total_amount) == 2.0

        ev = db.scalar(select(RequestEvent).where(RequestEvent.request_id == sr.id))
        assert ev is not None
        assert ev.type == "request_created"
        assert ev.actor_type == "customer"
        assert ev.actor_id == 1
        assert isinstance(ev.id, uuid.UUID)
        assert ev.id.version == 7


def test_create_pharmacy_order_sets_awaiting_prescription_for_rx_only_cart() -> None:
    _init_sqlite_db()
    client = TestClient(app)
    amoxicillin = _catalog_item_by_name(client, "Amoxicillin 500mg")

    res = client.post(
        "/v1/pharmacy/orders",
        headers=_auth_header_for_user_id(1),
        json={
            "service_id": "pharmacy",
            "order": {
                "items": [
                    {
                        "productId": amoxicillin["id"],
                        "quantity": 1,
                    }
                ],
                "prescriptionAttachmentIds": [],
            },
        },
    )

    assert res.status_code == 200
    assert res.json()["order"]["status"] == "created"
    assert res.json()["order"]["sub_status"] == "awaiting_prescription"


def test_create_pharmacy_order_links_prescription_attachments() -> None:
    _init_sqlite_db()
    client = TestClient(app)
    _catalog_item_by_name(client, "Paracetamol 500mg")

    import app.db as dbmod

    from app.ids import new_uuid7
    from app.models import Attachment

    with dbmod.SessionLocal() as db:
        attachment = Attachment(
            id=new_uuid7(),
            storage_key="/tmp/rx-file.jpg",
            filename="rx-file.jpg",
            content_type="image/jpeg",
            size_bytes=32,
        )
        db.add(attachment)
        db.commit()
        db.refresh(attachment)
        attachment_id = str(attachment.id)

    res = client.post(
        "/v1/pharmacy/orders",
        headers=_auth_header_for_user_id(1),
        json={
            "service_id": "pharmacy",
            "order": {
                "items": [],
                "prescriptionAttachmentIds": [attachment_id],
            },
        },
    )

    assert res.status_code == 200

    from sqlalchemy import select

    from app.models import PharmacyOrderDetail, RequestAttachment, ServiceRequest

    with dbmod.SessionLocal() as db:
        request = db.scalar(select(ServiceRequest).where(ServiceRequest.id == 1))
        assert request is not None
        detail = db.scalar(
            select(PharmacyOrderDetail).where(PharmacyOrderDetail.request_id == request.id)
        )
        assert detail is not None
        assert float(detail.total_amount) == 0.0
        request_attachment = db.scalar(
            select(RequestAttachment).where(RequestAttachment.request_id == request.id)
        )
        assert request_attachment is not None
        assert request_attachment.attachment_type == "prescription"
        assert str(request_attachment.attachment_id) == attachment_id
        assert request.payload_json is None


def test_pharmacy_checkout_options_returns_payment_methods_and_timings() -> None:
    _init_sqlite_db()
    client = TestClient(app)

    res = client.get("/v1/pharmacy/checkout_options")

    assert res.status_code == 200
    payload = res.json()
    assert "payment_options" in payload
    payment_options = payload["payment_options"]
    assert payment_options["methods"][0]["id"] == "cash"
    assert payment_options["methods"][1]["id"] == "mobile_money"
    assert payment_options["timings"][0]["id"] == "after_delivery"
    assert payment_options["timings"][1]["id"] == "before_delivery"
