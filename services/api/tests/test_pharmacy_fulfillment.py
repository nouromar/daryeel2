from __future__ import annotations

import os
import tempfile
import uuid
from decimal import Decimal
from pathlib import Path

from fastapi.testclient import TestClient

from app.auth import create_access_token
from app.main import app


def _init_sqlite_db(*, with_fulfillment_permissions: bool = True) -> None:
    tmpdir = Path(tempfile.mkdtemp(prefix="daryeel_api_test_"))
    db_path = tmpdir / "test.db"
    url = f"sqlite+pysqlite:///{db_path}"

    os.environ["DATABASE_URL"] = url
    os.environ["API_DATABASE_URL"] = url

    import app.db as dbmod

    dbmod._engine = None

    engine = dbmod.get_engine()

    from app.models import Base, Permission, Person, PersonRoleAssignment, Role, RolePermission, User

    Base.metadata.create_all(bind=engine)

    with dbmod.SessionLocal() as db:
        user = User(phone="+252610000001")
        db.add(user)
        db.flush()

        person = Person(
            primary_person_type="customer",
            status="active",
            phone_e164=user.phone,
        )
        db.add(person)
        db.flush()
        user.person_id = person.id

        if with_fulfillment_permissions:
            admin_role = Role(
                code="admin",
                role_group="staff",
                name="Admin",
                description="Administrative staff",
                is_system=True,
            )
            manage_orders = Permission(
                code="pharmacy.manage_orders",
                name="Manage pharmacy orders",
                description="Manage pharmacy fulfillment operations",
                is_system=True,
            )
            complete_delivery = Permission(
                code="pharmacy.complete_delivery",
                name="Complete pharmacy delivery",
                description="Complete pharmacy delivery lifecycle transitions",
                is_system=True,
            )
            db.add_all([admin_role, manage_orders, complete_delivery])
            db.flush()
            db.add_all(
                [
                    RolePermission(role_id=admin_role.id, permission_id=manage_orders.id),
                    RolePermission(role_id=admin_role.id, permission_id=complete_delivery.id),
                    PersonRoleAssignment(
                        person_id=person.id,
                        role_id=admin_role.id,
                        status="active",
                    ),
                ]
            )
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


def _catalog_item_by_name(client: TestClient, name: str) -> dict[str, object]:
    res = client.get("/v1/pharmacy/catalog")
    assert res.status_code == 200
    items = res.json()["items"]
    return next(item for item in items if item["name"] == name)


def _create_order(client: TestClient, *, product_id: str) -> None:
    res = client.post(
        "/v1/pharmacy/orders",
        headers=_auth_header_for_user_id(1),
        json={
            "service_id": "pharmacy",
            "order": {
                "items": [{"productId": product_id, "quantity": 1}],
                "prescriptionAttachmentIds": [],
            },
        },
    )
    assert res.status_code == 200


def _seed_second_pharmacy_offer(*, product_id: str) -> str:
    import app.db as dbmod

    from app.models import Organization, Pharmacy, PharmacyProduct

    organization_id = uuid.UUID("018f2f23-0000-7000-8000-000000000001")
    pharmacy_id = uuid.UUID("018f2f23-0000-7000-8000-000000000002")

    with dbmod.SessionLocal() as db:
        db.add(
            Organization(
                id=organization_id,
                name="Second Pharmacy Group",
                status="active",
                country_code="SO",
                city_name="Mogadishu",
            )
        )
        db.add(
            Pharmacy(
                id=pharmacy_id,
                organization_id=organization_id,
                name="Backup Branch",
                branch_code="backup-branch",
                status="active",
                address_text="Wadajir",
                country_code="SO",
                city_name="Mogadishu",
                zone_code="wadajir",
            )
        )
        db.add(
            PharmacyProduct(
                pharmacy_id=pharmacy_id,
                product_id=uuid.UUID(product_id),
                price_amount=Decimal("1.50"),
                currency_code="USD",
                stock_status="in_stock",
                status="active",
            )
        )
        db.commit()

    return str(pharmacy_id)


def test_branch_accept_updates_request_and_assignment() -> None:
    _init_sqlite_db()
    client = TestClient(app)
    paracetamol = _catalog_item_by_name(client, "Paracetamol 500mg")
    _create_order(client, product_id=str(paracetamol["id"]))

    res = client.post(
        "/v1/pharmacy/orders/1/fulfillment/branch-accept",
        headers=_auth_header_for_user_id(1),
        json={},
    )

    assert res.status_code == 200
    payload = res.json()
    assert payload["request"]["status"] == "accepted"
    assert payload["request"]["subStatus"] == "preparing"
    assert payload["branchAssignment"]["assignmentKind"] == "branch_fulfillment"
    assert payload["branchAssignment"]["status"] == "accepted"


def test_branch_accept_requires_manage_orders_permission() -> None:
    _init_sqlite_db(with_fulfillment_permissions=False)
    client = TestClient(app)
    paracetamol = _catalog_item_by_name(client, "Paracetamol 500mg")
    _create_order(client, product_id=str(paracetamol["id"]))

    res = client.post(
        "/v1/pharmacy/orders/1/fulfillment/branch-accept",
        headers=_auth_header_for_user_id(1),
        json={},
    )

    assert res.status_code == 403
    assert res.json() == {"detail": "Missing permission: pharmacy.manage_orders"}


def test_branch_review_auto_applies_additive_items_without_confirmation() -> None:
    _init_sqlite_db()
    client = TestClient(app)
    paracetamol = _catalog_item_by_name(client, "Paracetamol 500mg")
    amoxicillin = _catalog_item_by_name(client, "Amoxicillin 500mg")
    _create_order(client, product_id=str(paracetamol["id"]))

    review = client.post(
        "/v1/pharmacy/orders/1/fulfillment/review",
        headers=_auth_header_for_user_id(1),
        json={
            "items": [
                {"productId": paracetamol["id"], "quantity": 1},
                {"productId": amoxicillin["id"], "quantity": 1},
            ],
            "message": "Prescription reviewed and additive item applied.",
        },
    )

    assert review.status_code == 200
    payload = review.json()
    assert payload["request"]["status"] == "created"
    assert payload["request"]["subStatus"] == "awaiting_branch_review"
    assert payload["pendingConfirmation"] is None

    import app.db as dbmod

    from sqlalchemy import select

    from app.models import PharmacyOrderDetail, PharmacyOrderItem, ServiceRequest

    with dbmod.SessionLocal() as db:
        detail = db.scalar(
            select(PharmacyOrderDetail).where(PharmacyOrderDetail.request_id == 1)
        )
        assert detail is not None
        assert float(detail.total_amount) == 4.5
        items = list(
            db.scalars(
                select(PharmacyOrderItem)
                .where(PharmacyOrderItem.request_id == 1)
                .order_by(PharmacyOrderItem.product_name.asc())
            )
        )
        assert [item.product_name for item in items] == [
            "Amoxicillin 500mg",
            "Paracetamol 500mg",
        ]
        request = db.scalar(select(ServiceRequest).where(ServiceRequest.id == 1))
        assert request is not None
        assert request.sub_status == "awaiting_branch_review"
        assert request.payload_json == {
            "submittedOrder": {
                "items": [
                    {
                        "productId": str(paracetamol["id"]),
                        "quantity": 1,
                    }
                ]
            }
        }


def test_branch_review_stages_pending_confirmation_for_changed_customer_items() -> None:
    _init_sqlite_db()
    client = TestClient(app)
    paracetamol = _catalog_item_by_name(client, "Paracetamol 500mg")
    cetirizine = _catalog_item_by_name(client, "Cetirizine 10mg")
    _create_order(client, product_id=str(paracetamol["id"]))

    review = client.post(
        "/v1/pharmacy/orders/1/fulfillment/review",
        headers=_auth_header_for_user_id(1),
        json={
            "items": [{"productId": cetirizine["id"], "quantity": 2}],
            "reasonCode": "prescription_translation",
            "message": "Customer-selected item was replaced after reviewing the prescription.",
        },
    )

    assert review.status_code == 200
    payload = review.json()
    assert payload["request"]["status"] == "created"
    assert payload["request"]["subStatus"] == "awaiting_customer_confirmation"
    assert payload["pendingConfirmation"]["confirmationType"] == "derived_order_change"
    assert payload["pendingConfirmation"]["channel"] == "phone_call"
    assert payload["pendingConfirmation"]["proposedPricing"]["total"]["amountText"] == "$4.00"

    import app.db as dbmod

    from sqlalchemy import select

    from app.models import PharmacyOrderDetail, PharmacyOrderItem

    with dbmod.SessionLocal() as db:
        detail = db.scalar(
            select(PharmacyOrderDetail).where(PharmacyOrderDetail.request_id == 1)
        )
        assert detail is not None
        assert float(detail.total_amount) == 1.0
        item = db.scalar(
            select(PharmacyOrderItem).where(PharmacyOrderItem.request_id == 1)
        )
        assert item is not None
        assert item.product_name == "Paracetamol 500mg"


def test_resolve_confirmation_approval_applies_pending_snapshot() -> None:
    _init_sqlite_db()
    client = TestClient(app)
    paracetamol = _catalog_item_by_name(client, "Paracetamol 500mg")
    cetirizine = _catalog_item_by_name(client, "Cetirizine 10mg")
    _create_order(client, product_id=str(paracetamol["id"]))
    review = client.post(
        "/v1/pharmacy/orders/1/fulfillment/review",
        headers=_auth_header_for_user_id(1),
        json={
            "items": [{"productId": cetirizine["id"], "quantity": 2}],
            "confirmationChannel": "phone_call",
        },
    )
    assert review.status_code == 200

    resolve = client.post(
        "/v1/pharmacy/orders/1/fulfillment/resolve-confirmation",
        headers=_auth_header_for_user_id(1),
        json={"decision": "approve"},
    )

    assert resolve.status_code == 200
    payload = resolve.json()
    assert payload["request"]["status"] == "accepted"
    assert payload["request"]["subStatus"] == "preparing"
    assert payload["pendingConfirmation"] is None
    assert payload["branchAssignment"]["status"] == "accepted"

    import app.db as dbmod

    from sqlalchemy import select

    from app.models import PharmacyOrderDetail, PharmacyOrderItem, ServiceRequest

    with dbmod.SessionLocal() as db:
        detail = db.scalar(
            select(PharmacyOrderDetail).where(PharmacyOrderDetail.request_id == 1)
        )
        assert detail is not None
        assert float(detail.total_amount) == 4.0
        item = db.scalar(
            select(PharmacyOrderItem).where(PharmacyOrderItem.request_id == 1)
        )
        assert item is not None
        assert item.product_name == "Cetirizine 10mg"
        request = db.scalar(select(ServiceRequest).where(ServiceRequest.id == 1))
        assert request is not None
        assert request.payload_json == {
            "submittedOrder": {
                "items": [
                    {
                        "productId": str(paracetamol["id"]),
                        "quantity": 1,
                    }
                ]
            }
        }


def test_reroute_closes_previous_assignment_and_opens_new_branch_attempt() -> None:
    _init_sqlite_db()
    client = TestClient(app)
    paracetamol = _catalog_item_by_name(client, "Paracetamol 500mg")
    _create_order(client, product_id=str(paracetamol["id"]))
    backup_pharmacy_id = _seed_second_pharmacy_offer(product_id=str(paracetamol["id"]))

    res = client.post(
        "/v1/pharmacy/orders/1/fulfillment/reroute",
        headers=_auth_header_for_user_id(1),
        json={"pharmacyId": backup_pharmacy_id, "reasonCode": "branch_unavailable"},
    )

    assert res.status_code == 200
    payload = res.json()
    assert payload["request"]["status"] == "created"
    assert payload["request"]["subStatus"] == "awaiting_branch_review"
    assert payload["request"]["selectedPharmacyId"] == backup_pharmacy_id
    assert payload["branchAssignment"]["status"] == "active"
    assert payload["branchAssignment"]["attemptNo"] == 2
    assert payload["branchAssignment"]["pharmacyId"] == backup_pharmacy_id


def test_dispatch_then_deliver_completes_order() -> None:
    _init_sqlite_db()
    client = TestClient(app)
    paracetamol = _catalog_item_by_name(client, "Paracetamol 500mg")
    _create_order(client, product_id=str(paracetamol["id"]))

    accept = client.post(
        "/v1/pharmacy/orders/1/fulfillment/branch-accept",
        headers=_auth_header_for_user_id(1),
        json={},
    )
    assert accept.status_code == 200

    dispatch = client.post(
        "/v1/pharmacy/orders/1/fulfillment/dispatch",
        headers=_auth_header_for_user_id(1),
        json={},
    )
    assert dispatch.status_code == 200
    dispatch_payload = dispatch.json()
    assert dispatch_payload["request"]["status"] == "in_progress"
    assert dispatch_payload["request"]["subStatus"] == "out_for_delivery"
    assert dispatch_payload["branchAssignment"] is None
    assert dispatch_payload["deliveryAssignment"]["assignmentKind"] == "delivery"
    assert dispatch_payload["deliveryAssignment"]["status"] == "active"

    deliver = client.post(
        "/v1/pharmacy/orders/1/fulfillment/deliver",
        headers=_auth_header_for_user_id(1),
    )
    assert deliver.status_code == 200
    delivered_payload = deliver.json()
    assert delivered_payload["request"]["status"] == "completed"
    assert delivered_payload["request"]["subStatus"] == "delivered"
    assert delivered_payload["deliveryAssignment"] is None


def test_delivery_failure_marks_order_failed() -> None:
    _init_sqlite_db()
    client = TestClient(app)
    paracetamol = _catalog_item_by_name(client, "Paracetamol 500mg")
    _create_order(client, product_id=str(paracetamol["id"]))

    accept = client.post(
        "/v1/pharmacy/orders/1/fulfillment/branch-accept",
        headers=_auth_header_for_user_id(1),
        json={},
    )
    assert accept.status_code == 200

    dispatch = client.post(
        "/v1/pharmacy/orders/1/fulfillment/dispatch",
        headers=_auth_header_for_user_id(1),
        json={},
    )
    assert dispatch.status_code == 200

    failure = client.post(
        "/v1/pharmacy/orders/1/fulfillment/delivery-failed",
        headers=_auth_header_for_user_id(1),
        json={"reasonCode": "customer_unreachable"},
    )
    assert failure.status_code == 200
    payload = failure.json()
    assert payload["request"]["status"] == "failed"
    assert payload["request"]["subStatus"] == "delivery_failed"
    assert payload["deliveryAssignment"] is None
