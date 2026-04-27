from __future__ import annotations

import os
import re
import tempfile
import uuid
from decimal import Decimal
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


def _seed_pharmacy_catalog(db) -> tuple[str, str]:
    from app.models import Organization, Pharmacy, PharmacyProduct, Product

    organization_id = uuid.UUID("018f2f22-0000-7000-8000-000000000001")
    pharmacy_id = uuid.UUID("018f2f22-0000-7000-8000-000000000002")
    product_id = uuid.UUID("018f2f22-0000-7000-8000-000000000101")

    db.add(
        Organization(
            id=organization_id,
            name="Normalized Pharmacy Group",
            status="active",
            country_code="SO",
            city_name="Mogadishu",
        )
    )
    db.add(
        Pharmacy(
            id=pharmacy_id,
            organization_id=organization_id,
            name="Normalized Branch",
            branch_code="normalized-branch",
            status="active",
            address_text="Hodan",
            country_code="SO",
            city_name="Mogadishu",
            zone_code="hodan",
        )
    )
    db.add(
        Product(
            id=product_id,
            name="Paracetamol 500mg",
            generic_name="Paracetamol",
            form="tablet",
            strength="500mg",
            rx_required=False,
            status="active",
        )
    )
    db.add(
        PharmacyProduct(
            pharmacy_id=pharmacy_id,
            product_id=product_id,
            price_amount=Decimal("1.00"),
            currency_code="USD",
            stock_status="in_stock",
            status="active",
        )
    )
    db.commit()
    return str(pharmacy_id), str(product_id)


def _add_pharmacy_order_rows(
    db,
    *,
    request_id: int,
    pharmacy_id: str,
    product_id: str,
    quantity: int = 1,
    subtotal_amount: str = "1.00",
    total_amount: str = "1.00",
    product_name: str = "Paracetamol 500mg",
    rx_required: bool = False,
) -> None:
    from app.ids import new_uuid7
    from app.models import PharmacyOrderDetail, PharmacyOrderItem

    db.add(
        PharmacyOrderDetail(
            request_id=request_id,
            selected_pharmacy_id=uuid.UUID(pharmacy_id),
            currency_code="USD",
            subtotal_amount=Decimal(subtotal_amount),
            discount_amount=Decimal("0.00"),
            fee_amount=Decimal("0.00"),
            tax_amount=Decimal("0.00"),
            total_amount=Decimal(total_amount),
        )
    )
    db.add(
        PharmacyOrderItem(
            id=new_uuid7(),
            request_id=request_id,
            product_id=uuid.UUID(product_id),
            quantity=quantity,
            product_name=product_name,
            form="tablet",
            strength="500mg",
            rx_required=rx_required,
            seller_sku=None,
            unit_price_amount=(
                Decimal(total_amount) / quantity if quantity > 0 else Decimal("0.00")
            ),
            line_subtotal_amount=Decimal(subtotal_amount),
            line_discount_amount=None,
            line_tax_amount=None,
            line_total_amount=Decimal(total_amount),
        )
    )


def test_requests_endpoint_buckets_active_and_history() -> None:
    _init_sqlite_db()

    import app.db as dbmod
    from app.models import PharmacyOrderAssignment, RequestEvent, ServiceRequest

    with dbmod.SessionLocal() as db:
        pharmacy_id, product_id = _seed_pharmacy_catalog(db)
        active_request = ServiceRequest(
            service_id="pharmacy",
            customer_user_id=1,
            status="awaiting_info",
            payload_json=None,
        )
        history_request = ServiceRequest(
            service_id="pharmacy",
            customer_user_id=1,
            status="completed",
            payload_json=None,
        )
        db.add(active_request)
        db.add(history_request)
        db.commit()
        db.refresh(active_request)
        db.refresh(history_request)
        _add_pharmacy_order_rows(
            db,
            request_id=active_request.id,
            pharmacy_id=pharmacy_id,
            product_id=product_id,
            quantity=2,
            subtotal_amount="2.00",
            total_amount="2.00",
        )
        _add_pharmacy_order_rows(
            db,
            request_id=history_request.id,
            pharmacy_id=pharmacy_id,
            product_id=product_id,
            quantity=1,
            subtotal_amount="1.00",
            total_amount="1.00",
        )
        db.add(
            RequestEvent(
                request_id=active_request.id,
                type="request_created",
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
    from app.models import PharmacyOrderAssignment, RequestEvent, ServiceRequest

    with dbmod.SessionLocal() as db:
        pharmacy_id, product_id = _seed_pharmacy_catalog(db)
        request = ServiceRequest(
            service_id="pharmacy",
            customer_user_id=1,
            status="created",
            notes="Leave at door",
            delivery_location_json={"text": "Hodan"},
            payment_json={"method": "cash", "timing": "after_delivery"},
            payload_json=None,
        )
        db.add(request)
        db.commit()
        db.refresh(request)
        _add_pharmacy_order_rows(
            db,
            request_id=request.id,
            pharmacy_id=pharmacy_id,
            product_id=product_id,
            quantity=2,
            subtotal_amount="2.00",
            total_amount="2.00",
        )
        db.add(
            RequestEvent(
                request_id=request.id,
                type="request_created",
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
    assert payload["request"]["subStatus"] is None
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
        "order": {
            "items": [
                {
                    "productId": product_id,
                    "name": "Paracetamol 500mg",
                    "unitPriceAmount": 1.0,
                    "unitPriceText": "$1.00",
                    "rxRequired": False,
                    "quantity": 2,
                }
            ],
            "pricing": {
                "currencyCode": "USD",
                "lines": [
                    {
                        "id": "subtotal",
                        "label": "Subtotal",
                        "amount": 2.0,
                        "amountText": "$2.00",
                    }
                ],
                "total": {
                    "label": "Total",
                    "amount": 2.0,
                    "amountText": "$2.00",
                },
            },
            "prescriptionAttachments": [],
        },
    }
    assert payload["timeline"][0]["title"] == "Requested"
    assert re.match(r"^[A-Z][a-z]{2} \d{2}$", payload["timeline"][0]["subtitle"])


def test_request_detail_prefers_normalized_pharmacy_order_rows() -> None:
    _init_sqlite_db()

    import app.db as dbmod
    from app.ids import new_uuid7
    from app.models import PharmacyOrderDetail, PharmacyOrderItem, RequestEvent, ServiceRequest

    with dbmod.SessionLocal() as db:
        pharmacy_id, product_id = _seed_pharmacy_catalog(db)
        request = ServiceRequest(
            service_id="pharmacy",
            customer_user_id=1,
            status="created",
            payment_json={"method": "cash", "timing": "after_delivery"},
            payload_json={
                "cart_lines": [
                    {"id": "legacy-product", "name": "Legacy payload row", "quantity": 99},
                ],
                "summary_total": {"label": "Total", "amountText": "$999.00"},
                "prescription_upload_ids": [],
            },
        )
        db.add(request)
        db.commit()
        db.refresh(request)
        db.add(
            PharmacyOrderDetail(
                request_id=request.id,
                selected_pharmacy_id=uuid.UUID(pharmacy_id),
                currency_code="USD",
                subtotal_amount=Decimal("2.00"),
                discount_amount=Decimal("0.00"),
                fee_amount=Decimal("0.00"),
                tax_amount=Decimal("0.00"),
                total_amount=Decimal("2.00"),
            )
        )
        db.add(
            PharmacyOrderItem(
                id=new_uuid7(),
                request_id=request.id,
                product_id=uuid.UUID(product_id),
                quantity=2,
                product_name="Paracetamol 500mg",
                form="tablet",
                strength="500mg",
                rx_required=False,
                seller_sku=None,
                unit_price_amount=Decimal("1.00"),
                line_subtotal_amount=Decimal("2.00"),
                line_discount_amount=None,
                line_tax_amount=None,
                line_total_amount=Decimal("2.00"),
            )
        )
        db.add(
            RequestEvent(
                request_id=request.id,
                type="request_created",
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
    service_payload = payload["serviceDetails"]["order"]
    assert service_payload["items"] == [
        {
            "productId": product_id,
            "name": "Paracetamol 500mg",
            "unitPriceAmount": 1.0,
            "unitPriceText": "$1.00",
            "rxRequired": False,
            "quantity": 2,
        }
    ]
    assert service_payload["pricing"] == {
        "currencyCode": "USD",
        "lines": [
            {
                "id": "subtotal",
                "label": "Subtotal",
                "amount": 2.0,
                "amountText": "$2.00",
            }
        ],
        "total": {
            "label": "Total",
            "amount": 2.0,
            "amountText": "$2.00",
        },
    }


def test_request_detail_marks_recent_updates_for_non_created_latest_event() -> None:
    _init_sqlite_db()

    import app.db as dbmod
    from app.models import PharmacyOrderAssignment, RequestEvent, ServiceRequest

    with dbmod.SessionLocal() as db:
        request = ServiceRequest(
            service_id="pharmacy",
            customer_user_id=1,
            status="assigned",
            payload_json=None,
        )
        db.add(request)
        db.commit()
        db.refresh(request)
        db.add(
            RequestEvent(
                request_id=request.id,
                type="request_created",
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
                type="request_status_changed",
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
    from app.models import PharmacyOrderAssignment, RequestEvent, ServiceRequest

    with dbmod.SessionLocal() as db:
        request = ServiceRequest(
            service_id="pharmacy",
            customer_user_id=1,
            status="created",
            sub_status="awaiting_prescription",
            payload_json=None,
        )
        db.add(request)
        db.commit()
        db.refresh(request)
        db.add(
            RequestEvent(
                request_id=request.id,
                type="request_status_changed",
                from_status="created",
                to_status="created",
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
    from app.models import PharmacyOrderAssignment, RequestEvent, ServiceRequest

    with dbmod.SessionLocal() as db:
        pharmacy_id, product_id = _seed_pharmacy_catalog(db)
        request = ServiceRequest(
            service_id="pharmacy",
            customer_user_id=1,
            status="created",
            sub_status="awaiting_customer_confirmation",
            payload_json=None,
        )
        db.add(request)
        db.commit()
        db.refresh(request)
        _add_pharmacy_order_rows(
            db,
            request_id=request.id,
            pharmacy_id=pharmacy_id,
            product_id=product_id,
            quantity=1,
            subtotal_amount="7.00",
            total_amount="7.00",
        )
        db.add(
            RequestEvent(
                request_id=request.id,
                type="customer_confirmation_requested",
                from_status="created",
                to_status="created",
                actor_type="system",
                actor_id=None,
                metadata_json={
                    "confirmationType": "price_change",
                    "message": "Price changed because one item is out of stock.",
                },
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
    from app.models import PharmacyOrderAssignment, RequestEvent, ServiceRequest

    with dbmod.SessionLocal() as db:
        pharmacy_id, product_id = _seed_pharmacy_catalog(db)
        request = ServiceRequest(
            service_id="pharmacy",
            customer_user_id=1,
            status="created",
            sub_status="awaiting_customer_confirmation",
            payload_json=None,
        )
        db.add(request)
        db.commit()
        db.refresh(request)
        _add_pharmacy_order_rows(
            db,
            request_id=request.id,
            pharmacy_id=pharmacy_id,
            product_id=product_id,
            quantity=1,
            subtotal_amount="7.00",
            total_amount="7.00",
        )
        db.add(
            RequestEvent(
                request_id=request.id,
                type="customer_confirmation_requested",
                from_status="created",
                to_status="created",
                actor_type="system",
                actor_id=None,
                metadata_json={
                    "confirmationType": "price_change",
                    "message": "Please confirm the updated price.",
                },
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
    assert payload["timeline"][-1]["type"] == "customer_confirmation_resolved"


def test_request_detail_returns_pending_action_for_generic_order_change_confirmation() -> None:
    _init_sqlite_db()

    import app.db as dbmod
    from app.models import PharmacyOrderAssignment, RequestEvent, ServiceRequest

    with dbmod.SessionLocal() as db:
        pharmacy_id, product_id = _seed_pharmacy_catalog(db)
        request = ServiceRequest(
            service_id="pharmacy",
            customer_user_id=1,
            status="created",
            sub_status="awaiting_customer_confirmation",
            payload_json={
                "submittedOrder": {
                    "items": [
                        {
                            "productId": product_id,
                            "quantity": 1,
                        }
                    ]
                },
                "pendingConfirmation": {
                    "confirmationType": "derived_order_change",
                    "channel": "in_app",
                    "message": "The pharmacist updated the order after reviewing the prescription.",
                    "proposedItems": [
                        {
                            "productId": product_id,
                            "quantity": 2,
                            "productName": "Paracetamol 500mg",
                            "form": "tablet",
                            "strength": "500mg",
                            "rxRequired": False,
                            "sellerSku": None,
                            "unitPriceAmount": 1.0,
                            "lineSubtotalAmount": 2.0,
                            "lineDiscountAmount": None,
                            "lineTaxAmount": None,
                            "lineTotalAmount": 2.0,
                        }
                    ],
                    "proposedPricing": {
                        "currencyCode": "USD",
                        "subtotalAmount": 2.0,
                        "discountAmount": 0.0,
                        "feeAmount": 0.0,
                        "taxAmount": 0.0,
                        "totalAmount": 2.0,
                        "lines": [
                            {
                                "id": "subtotal",
                                "label": "Subtotal",
                                "amount": 2.0,
                                "amountText": "$2.00",
                            }
                        ],
                        "total": {
                            "label": "Total",
                            "amount": 2.0,
                            "amountText": "$2.00",
                        },
                    },
                },
            },
        )
        db.add(request)
        db.commit()
        db.refresh(request)
        _add_pharmacy_order_rows(
            db,
            request_id=request.id,
            pharmacy_id=pharmacy_id,
            product_id=product_id,
            quantity=1,
            subtotal_amount="1.00",
            total_amount="1.00",
        )
        db.add(
            PharmacyOrderAssignment(
                request_id=request.id,
                pharmacy_id=uuid.UUID(pharmacy_id),
                assignment_kind="branch_fulfillment",
                assigned_role_code="branch_staff",
                status="active",
                attempt_no=1,
            )
        )
        db.add(
            RequestEvent(
                request_id=request.id,
                type="customer_confirmation_requested",
                from_status="created",
                to_status="created",
                actor_type="system",
                actor_id=None,
                metadata_json={
                    "confirmationType": "derived_order_change",
                    "channel": "in_app",
                    "message": "Please review the updated order.",
                },
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
    assert payload["pendingActions"][0]["id"] == "confirm_change"
    assert payload["pendingActions"][0]["type"] == "confirm_change"
    assert payload["pendingActions"][0]["title"] == "Review order changes"
    assert "Updated total: $2.00" in payload["pendingActions"][0]["subtitle"]
    assert payload["serviceDetails"]["order"]["pendingConfirmation"]["confirmationType"] == "derived_order_change"


def test_request_detail_hides_manual_phone_confirmation_action() -> None:
    _init_sqlite_db()

    import app.db as dbmod
    from app.models import PharmacyOrderAssignment, RequestEvent, ServiceRequest

    with dbmod.SessionLocal() as db:
        pharmacy_id, product_id = _seed_pharmacy_catalog(db)
        request = ServiceRequest(
            service_id="pharmacy",
            customer_user_id=1,
            status="created",
            sub_status="awaiting_customer_confirmation",
            payload_json={
                "submittedOrder": {"items": []},
                "pendingConfirmation": {
                    "confirmationType": "derived_order_change",
                    "channel": "phone_call",
                    "message": "The branch will call to confirm the reviewed order.",
                    "proposedItems": [],
                    "proposedPricing": {
                        "currencyCode": "USD",
                        "totalAmount": 0.0,
                        "total": {
                            "label": "Total",
                            "amount": 0.0,
                            "amountText": "$0.00",
                        },
                    },
                },
            },
        )
        db.add(request)
        db.commit()
        db.refresh(request)
        _add_pharmacy_order_rows(
            db,
            request_id=request.id,
            pharmacy_id=pharmacy_id,
            product_id=product_id,
            quantity=1,
            subtotal_amount="1.00",
            total_amount="1.00",
        )
        db.add(
            PharmacyOrderAssignment(
                request_id=request.id,
                pharmacy_id=uuid.UUID(pharmacy_id),
                assignment_kind="branch_fulfillment",
                assigned_role_code="branch_staff",
                status="active",
                attempt_no=1,
            )
        )
        db.add(
            RequestEvent(
                request_id=request.id,
                type="customer_confirmation_requested",
                from_status="created",
                to_status="created",
                actor_type="system",
                actor_id=None,
                metadata_json={
                    "confirmationType": "derived_order_change",
                    "channel": "phone_call",
                },
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
    assert payload["pendingActions"] == []


def test_complete_request_action_approves_generic_order_change() -> None:
    _init_sqlite_db()

    import app.db as dbmod
    from app.models import PharmacyOrderAssignment, RequestEvent, ServiceRequest

    with dbmod.SessionLocal() as db:
        pharmacy_id, product_id = _seed_pharmacy_catalog(db)
        request = ServiceRequest(
            service_id="pharmacy",
            customer_user_id=1,
            status="created",
            sub_status="awaiting_customer_confirmation",
            payload_json={
                "submittedOrder": {
                    "items": [
                        {
                            "productId": product_id,
                            "quantity": 1,
                        }
                    ]
                },
                "pendingConfirmation": {
                    "confirmationType": "derived_order_change",
                    "channel": "in_app",
                    "message": "Please confirm the reviewed order.",
                    "proposedItems": [
                        {
                            "productId": product_id,
                            "quantity": 2,
                            "productName": "Paracetamol 500mg",
                            "form": "tablet",
                            "strength": "500mg",
                            "rxRequired": False,
                            "sellerSku": None,
                            "unitPriceAmount": 1.0,
                            "lineSubtotalAmount": 2.0,
                            "lineDiscountAmount": None,
                            "lineTaxAmount": None,
                            "lineTotalAmount": 2.0,
                        }
                    ],
                    "proposedPricing": {
                        "currencyCode": "USD",
                        "subtotalAmount": 2.0,
                        "discountAmount": 0.0,
                        "feeAmount": 0.0,
                        "taxAmount": 0.0,
                        "totalAmount": 2.0,
                        "lines": [
                            {
                                "id": "subtotal",
                                "label": "Subtotal",
                                "amount": 2.0,
                                "amountText": "$2.00",
                            }
                        ],
                        "total": {
                            "label": "Total",
                            "amount": 2.0,
                            "amountText": "$2.00",
                        },
                    },
                },
            },
        )
        db.add(request)
        db.commit()
        db.refresh(request)
        _add_pharmacy_order_rows(
            db,
            request_id=request.id,
            pharmacy_id=pharmacy_id,
            product_id=product_id,
            quantity=1,
            subtotal_amount="1.00",
            total_amount="1.00",
        )
        db.add(
            PharmacyOrderAssignment(
                request_id=request.id,
                pharmacy_id=uuid.UUID(pharmacy_id),
                assignment_kind="branch_fulfillment",
                assigned_role_code="branch_staff",
                status="active",
                attempt_no=1,
            )
        )
        db.add(
            RequestEvent(
                request_id=request.id,
                type="customer_confirmation_requested",
                from_status="created",
                to_status="created",
                actor_type="system",
                actor_id=None,
                metadata_json={
                    "confirmationType": "derived_order_change",
                    "channel": "in_app",
                },
            )
        )
        db.commit()

    client = TestClient(app)
    res = client.post(
        "/v1/requests/1/actions/confirm_change",
        json={"decision": "approve"},
        headers=_auth_header_for_user_id(1),
    )

    assert res.status_code == 200
    payload = res.json()
    assert payload["request"]["status"] == "accepted"
    assert payload["request"]["subStatus"] == "preparing"
    assert payload["pendingActions"] == []
    assert payload["serviceDetails"]["order"]["items"] == [
        {
            "productId": product_id,
            "name": "Paracetamol 500mg",
            "unitPriceAmount": 1.0,
            "unitPriceText": "$1.00",
            "rxRequired": False,
            "quantity": 2,
        }
    ]
    assert payload["timeline"][-1]["type"] == "customer_confirmation_resolved"


def test_complete_request_action_uploads_prescription() -> None:
    _init_sqlite_db()

    import app.db as dbmod
    from app.ids import new_uuid7
    from sqlalchemy import select

    from app.models import Attachment, RequestAttachment, RequestEvent, ServiceRequest

    with dbmod.SessionLocal() as db:
        request = ServiceRequest(
            service_id="pharmacy",
            customer_user_id=1,
            status="created",
            sub_status="awaiting_prescription",
            payload_json=None,
        )
        db.add(request)
        db.commit()
        db.refresh(request)
        db.add(
            RequestEvent(
                request_id=request.id,
                type="request_status_changed",
                from_status="created",
                to_status="created",
                actor_type="system",
                actor_id=None,
                metadata_json={"message": "Please upload a valid prescription."},
            )
        )
        attachment = Attachment(
            id=new_uuid7(),
            storage_key="/tmp/rx-123.jpg",
            filename="rx-123.jpg",
            content_type="image/jpeg",
            size_bytes=16,
        )
        db.add(attachment)
        db.commit()
        attachment_id = str(attachment.id)

    client = TestClient(app)
    res = client.post(
        "/v1/requests/1/actions/upload_prescription",
        json={"decision": "upload", "payload": {"uploadIds": [attachment_id]}},
        headers=_auth_header_for_user_id(1),
    )

    assert res.status_code == 200
    payload = res.json()
    assert payload["request"]["status"] == "created"
    assert payload["request"]["subStatus"] == "awaiting_branch_review"
    assert payload["pendingActions"] == []
    assert payload["request"]["hasUnreadUpdates"] is False
    assert payload["serviceDetails"]["order"]["prescriptionAttachments"] == [
        {
            "attachmentId": attachment_id,
            "filename": "rx-123.jpg",
        }
    ]
    assert payload["timeline"][-1]["type"] == "attachment_added"

    with dbmod.SessionLocal() as db:
        request_attachment = db.scalar(
            select(RequestAttachment).where(RequestAttachment.request_id == 1)
        )
        assert request_attachment is not None
        assert str(request_attachment.attachment_id) == attachment_id
