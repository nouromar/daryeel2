from __future__ import annotations

import os
import re
import tempfile
from pathlib import Path

from fastapi.testclient import TestClient

from app.auth import create_access_token
from app.main import app


def _init_sqlite_db() -> None:
    tmpdir = Path(tempfile.mkdtemp(prefix="daryeel_api_test_"))
    db_path = tmpdir / "test.db"
    url = f"sqlite+pysqlite:///{db_path}"

    os.environ["DATABASE_URL"] = url
    os.environ["API_DATABASE_URL"] = url

    import app.db as dbmod

    dbmod._engine = None

    engine = dbmod.get_engine()

    from app.models import Base, User

    Base.metadata.create_all(bind=engine)

    with dbmod.SessionLocal() as db:
        user = User(phone="+252610000001")
        db.add(user)
        db.commit()
        db.refresh(user)


def _auth_header_for_user_id(user_id: int) -> dict[str, str]:
    token = create_access_token(
        secret="dev-insecure-secret",
        user_id=user_id,
        phone="+252610000001",
        ttl_seconds=60,
    )
    return {"Authorization": f"Bearer {token}"}


def test_requests_endpoint_buckets_active_and_history() -> None:
    _init_sqlite_db()

    import app.db as dbmod
    from app.models import RequestEvent, ServiceRequest

    with dbmod.SessionLocal() as db:
        active_request = ServiceRequest(
            service_id="pharmacy",
            customer_user_id=1,
            status="awaiting_info",
            payload_json={
                "cart_lines": [
                    {"product_id": "prod_paracetamol_500mg", "quantity": 2},
                ],
                "prescription_upload_ids": [],
            },
        )
        history_request = ServiceRequest(
            service_id="pharmacy",
            customer_user_id=1,
            status="completed",
            payload_json={
                "cart_lines": [
                    {"product_id": "prod_cetirizine_10mg", "quantity": 1},
                ],
                "prescription_upload_ids": [],
            },
        )
        db.add(active_request)
        db.add(history_request)
        db.commit()
        db.refresh(active_request)
        db.add(
            RequestEvent(
                request_id=active_request.id,
                type="created",
                from_status=None,
                to_status="created",
                actor_type="customer",
                actor_id=1,
                metadata_json=None,
            )
        )
        db.commit()

    client = TestClient(app)
    res = client.get("/v1/requests", headers=_auth_header_for_user_id(1))

    assert res.status_code == 200
    payload = res.json()
    assert payload["has_requests"] is True
    assert "attention" not in payload
    assert len(payload["active"]) == 1
    assert len(payload["history"]) == 1
    assert payload["active"][0]["title"] == "Pharmacy order"
    assert payload["active"][0]["attentionState"] == "action_required"
    assert payload["active"][0]["isAttentionRequired"] is True
    assert payload["active"][0]["pendingActionCount"] == 1
    assert payload["active"][0]["subtitle"].startswith("Action needed")
    assert "2 items" in payload["active"][0]["subtitle"]
    assert payload["active"][0]["route"]["route"] == "customer.schema_screen"
    assert payload["active"][0]["route"]["value"]["screenId"] == "customer_request_detail"
    assert payload["history"][0]["status"] == "completed"


def test_request_detail_endpoint_returns_common_shell_data() -> None:
    _init_sqlite_db()

    import app.db as dbmod
    from app.models import RequestEvent, ServiceRequest

    request_payload = {
        "cart_lines": [
            {
                "id": "prod_paracetamol_500mg",
                "name": "Paracetamol 500 mg",
                "subtitle": "$1.00",
                "price": 1.0,
                "icon": "pharmacy",
                "route": "",
                "rx_required": False,
                "quantity": 2,
            },
        ],
        "summary_lines": [
            {"id": "subtotal", "label": "Subtotal", "amount": 2, "amountText": "$2.00"},
        ],
        "summary_total": {"label": "Total", "amountText": "$2.00"},
        "prescription_upload_ids": [],
    }

    with dbmod.SessionLocal() as db:
        request = ServiceRequest(
            service_id="pharmacy",
            customer_user_id=1,
            status="created",
            notes="Leave at door",
            delivery_location_json={"text": "Hodan"},
            payment_json={"method": "cash", "timing": "after_delivery"},
            payload_json=request_payload,
        )
        db.add(request)
        db.commit()
        db.refresh(request)
        db.add(
            RequestEvent(
                request_id=request.id,
                type="created",
                from_status=None,
                to_status="created",
                actor_type="customer",
                actor_id=1,
                metadata_json=None,
            )
        )
        db.commit()

    client = TestClient(app)
    res = client.get(
        "/v1/requests/detail",
        params={"requestId": 1},
        headers=_auth_header_for_user_id(1),
    )

    assert res.status_code == 200
    payload = res.json()
    assert payload["request"]["title"] == "Pharmacy order"
    assert payload["request"]["statusLabel"] == "Requested"
    assert payload["request"]["detailSubtitle"].startswith("Requested • ")
    assert payload["request"]["detailSubtitle"].endswith(", 2026")
    assert payload["request"]["attentionState"] == "none"
    assert payload["request"]["isAttentionRequired"] is False
    assert payload["request"]["deliveryLocation"]["text"] == "Hodan"
    assert payload["request"]["paymentSummaryText"] == "Cash • after delivery"
    assert payload["request"]["pendingActionCount"] == 0
    assert payload["pendingActions"] == []
    assert payload["serviceDetails"]["isPharmacy"] is True
    assert payload["serviceDetails"] == {
        "serviceId": "pharmacy",
        "isPharmacy": True,
        "payload": request_payload,
    }
    assert payload["timeline"][0]["title"] == "Requested"
    assert re.match(r"^[A-Z][a-z]{2} \d{2}$", payload["timeline"][0]["subtitle"])


def test_request_detail_marks_recent_updates_for_non_created_latest_event() -> None:
    _init_sqlite_db()

    import app.db as dbmod
    from app.models import RequestEvent, ServiceRequest

    with dbmod.SessionLocal() as db:
        request = ServiceRequest(
            service_id="pharmacy",
            customer_user_id=1,
            status="assigned",
            payload_json={
                "cart_lines": [
                    {"product_id": "prod_paracetamol_500mg", "quantity": 1},
                ],
                "prescription_upload_ids": [],
            },
        )
        db.add(request)
        db.commit()
        db.refresh(request)
        db.add(
            RequestEvent(
                request_id=request.id,
                type="created",
                from_status=None,
                to_status="created",
                actor_type="customer",
                actor_id=1,
                metadata_json=None,
            )
        )
        db.add(
            RequestEvent(
                request_id=request.id,
                type="status_changed",
                from_status="created",
                to_status="assigned",
                actor_type="system",
                actor_id=None,
                metadata_json=None,
            )
        )
        db.commit()

    client = TestClient(app)
    res = client.get(
        "/v1/requests/detail",
        params={"requestId": 1},
        headers=_auth_header_for_user_id(1),
    )

    assert res.status_code == 200
    payload = res.json()
    assert payload["request"]["attentionState"] == "update_available"
    assert payload["request"]["isUpdateAvailable"] is True
    assert payload["request"]["hasUnreadUpdates"] is True
    assert payload["request"]["attentionTitle"] == "Recent update"


def test_request_detail_returns_pending_action_for_prescription_upload() -> None:
    _init_sqlite_db()

    import app.db as dbmod
    from app.models import RequestEvent, ServiceRequest

    with dbmod.SessionLocal() as db:
        request = ServiceRequest(
            service_id="pharmacy",
            customer_user_id=1,
            status="waiting_for_prescription",
            payload_json={
                "cart_lines": [
                    {"product_id": "prod_paracetamol_500mg", "quantity": 1},
                ],
                "prescription_upload_ids": [],
            },
        )
        db.add(request)
        db.commit()
        db.refresh(request)
        db.add(
            RequestEvent(
                request_id=request.id,
                type="prescription_requested",
                from_status="created",
                to_status="waiting_for_prescription",
                actor_type="system",
                actor_id=None,
                metadata_json={"message": "Please upload a valid prescription."},
            )
        )
        db.commit()

    client = TestClient(app)
    res = client.get(
        "/v1/requests/detail",
        params={"requestId": 1},
        headers=_auth_header_for_user_id(1),
    )

    assert res.status_code == 200
    payload = res.json()
    assert payload["request"]["attentionState"] == "action_required"
    assert payload["request"]["pendingActionCount"] == 1
    assert payload["pendingActions"][0]["id"] == "upload_prescription"
    assert payload["pendingActions"][0]["type"] == "upload_document"
    assert payload["pendingActions"][0]["title"] == "Upload prescription"
    assert "Please upload a valid prescription." in payload["pendingActions"][0]["subtitle"]


def test_request_detail_returns_pending_action_for_price_confirmation() -> None:
    _init_sqlite_db()

    import app.db as dbmod
    from app.models import RequestEvent, ServiceRequest

    with dbmod.SessionLocal() as db:
        request = ServiceRequest(
            service_id="pharmacy",
            customer_user_id=1,
            status="waiting_price_change_confirmation",
            payload_json={
                "cart_lines": [
                    {"product_id": "prod_paracetamol_500mg", "quantity": 1},
                ],
                "summary_total": {"label": "Total", "amountText": "$7.00"},
                "prescription_upload_ids": [],
            },
        )
        db.add(request)
        db.commit()
        db.refresh(request)
        db.add(
            RequestEvent(
                request_id=request.id,
                type="price_change_proposed",
                from_status="assigned",
                to_status="waiting_price_change_confirmation",
                actor_type="system",
                actor_id=None,
                metadata_json={"message": "Price changed because one item is out of stock."},
            )
        )
        db.commit()

    client = TestClient(app)
    res = client.get(
        "/v1/requests/detail",
        params={"requestId": 1},
        headers=_auth_header_for_user_id(1),
    )

    assert res.status_code == 200
    payload = res.json()
    assert payload["request"]["pendingActionCount"] == 1
    assert payload["pendingActions"][0]["id"] == "confirm_price"
    assert payload["pendingActions"][0]["type"] == "confirm_price"
    assert payload["pendingActions"][0]["title"] == "Review price update"
    assert "Updated total: $7.00" in payload["pendingActions"][0]["subtitle"]


def test_complete_request_action_approves_price_change() -> None:
    _init_sqlite_db()

    import app.db as dbmod
    from app.models import RequestEvent, ServiceRequest

    with dbmod.SessionLocal() as db:
        request = ServiceRequest(
            service_id="pharmacy",
            customer_user_id=1,
            status="waiting_price_change_confirmation",
            payload_json={
                "cart_lines": [
                    {"product_id": "prod_paracetamol_500mg", "quantity": 1},
                ],
                "summary_total": {"label": "Total", "amountText": "$7.00"},
                "prescription_upload_ids": [],
            },
        )
        db.add(request)
        db.commit()
        db.refresh(request)
        db.add(
            RequestEvent(
                request_id=request.id,
                type="price_change_proposed",
                from_status="assigned",
                to_status="waiting_price_change_confirmation",
                actor_type="system",
                actor_id=None,
                metadata_json={"message": "Please confirm the updated price."},
            )
        )
        db.commit()

    client = TestClient(app)
    res = client.post(
        "/v1/requests/1/actions/confirm_price",
        json={"decision": "approve"},
        headers=_auth_header_for_user_id(1),
    )

    assert res.status_code == 200
    payload = res.json()
    assert payload["request"]["status"] == "accepted"
    assert payload["request"]["pendingActionCount"] == 0
    assert payload["request"]["attentionState"] == "none"
    assert payload["request"]["hasUnreadUpdates"] is False
    assert payload["pendingActions"] == []
    assert payload["timeline"][-1]["type"] == "price_change_confirmed"


def test_complete_request_action_uploads_prescription() -> None:
    _init_sqlite_db()

    import app.db as dbmod
    from app.models import RequestEvent, ServiceRequest

    with dbmod.SessionLocal() as db:
        request = ServiceRequest(
            service_id="pharmacy",
            customer_user_id=1,
            status="waiting_for_prescription",
            payload_json={
                "cart_lines": [
                    {"product_id": "prod_paracetamol_500mg", "quantity": 1},
                ],
                "prescription_upload_ids": [],
            },
        )
        db.add(request)
        db.commit()
        db.refresh(request)
        db.add(
            RequestEvent(
                request_id=request.id,
                type="prescription_requested",
                from_status="created",
                to_status="waiting_for_prescription",
                actor_type="system",
                actor_id=None,
                metadata_json={"message": "Please upload a valid prescription."},
            )
        )
        db.commit()

    client = TestClient(app)
    res = client.post(
        "/v1/requests/1/actions/upload_prescription",
        json={"decision": "upload", "payload": {"uploadIds": ["rx-123"]}},
        headers=_auth_header_for_user_id(1),
    )

    assert res.status_code == 200
    payload = res.json()
    assert payload["request"]["status"] == "accepted"
    assert payload["pendingActions"] == []
    assert payload["request"]["hasUnreadUpdates"] is False
    assert payload["serviceDetails"]["payload"]["prescription_upload_ids"] == ["rx-123"]
    assert payload["timeline"][-1]["type"] == "prescription_uploaded"