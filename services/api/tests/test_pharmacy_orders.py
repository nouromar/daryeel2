from __future__ import annotations

import os
import tempfile
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


def test_create_pharmacy_order_requires_cart_or_prescription() -> None:
    _init_sqlite_db()
    client = TestClient(app)

    res = client.post(
        "/v1/pharmacy/orders",
        headers=_auth_header_for_user_id(1),
        json={
            "service_id": "pharmacy",
            "payload": {
                "cart_lines": [],
                "prescription_upload_ids": [],
            },
        },
    )

    assert res.status_code == 400


def test_create_pharmacy_order_creates_request_and_event() -> None:
    _init_sqlite_db()
    client = TestClient(app)

    res = client.post(
        "/v1/pharmacy/orders",
        headers=_auth_header_for_user_id(1),
        json={
            "service_id": "pharmacy",
            "delivery_location": {"text": "Hodan", "lat": 2.046934, "lng": 45.318162, "accuracy_m": 15},
            "payment": {"method": "cash", "timing": "after_delivery"},
            "notes": "Leave at door",
            "payload": {
                "cart_lines": [
                    {
                        "id": "prod_paracetamol_500mg",
                        "name": "Paracetamol 500mg",
                        "price": 1.0,
                        "subtitle": "$1.00",
                        "rx_required": False,
                        "icon": "pharmacy",
                        "route": "",
                        "quantity": 2,
                    }
                ],
                "summary_lines": [
                    {"id": "subtotal", "label": "Subtotal", "amount": 2, "amountText": "$2.00"}
                ],
                "summary_total": {"label": "Total", "amount": 2, "amountText": "$2.00"},
                "prescription_upload_ids": [],
            },
        },
    )

    assert res.status_code == 200
    payload = res.json()
    assert "order" in payload
    order = payload["order"]
    assert order["service_id"] == "pharmacy"
    assert order["status"] == "created"
    assert order["customer_user_id"] == "1"

    # Confirm DB rows exist.
    import app.db as dbmod

    from sqlalchemy import select

    from app.models import RequestEvent, ServiceRequest

    with dbmod.SessionLocal() as db:
        sr = db.scalar(select(ServiceRequest).where(ServiceRequest.id == int(order["id"])))
        assert sr is not None
        assert sr.service_id == "pharmacy"
        assert sr.notes == "Leave at door"
        assert sr.payment_json == {"method": "cash", "timing": "after_delivery"}
        assert sr.delivery_location_json["text"] == "Hodan"
        assert sr.payload_json["summary_total"]["label"] == "Total"
        assert sr.payload_json["cart_lines"][0]["id"] == "prod_paracetamol_500mg"
        assert sr.payload_json["cart_lines"][0]["quantity"] == 2
        assert sr.payload_json["cart_lines"][0]["price"] == 1.0
        assert sr.payload_json["cart_lines"][0]["subtitle"] == "$1.00"
        assert sr.payload_json["cart_lines"][0]["icon"] == "pharmacy"
        assert sr.payload_json["cart_lines"][0]["route"] == ""

        ev = db.scalar(select(RequestEvent).where(RequestEvent.request_id == sr.id))
        assert ev is not None
        assert ev.type == "created"
        assert ev.actor_type == "customer"
        assert ev.actor_id == 1


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
