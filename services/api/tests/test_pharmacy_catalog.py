from __future__ import annotations

import os
import tempfile
import uuid
from decimal import Decimal
from pathlib import Path

from fastapi.testclient import TestClient

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

    from app.models import Base

    Base.metadata.create_all(bind=engine)


def _seed_catalog_rows() -> list[str]:
    import app.db as dbmod

    from app.models import Organization, Pharmacy, PharmacyProduct, Product

    organization_id = uuid.UUID("018f2f21-0000-7000-8000-000000000001")
    pharmacy_id = uuid.UUID("018f2f21-0000-7000-8000-000000000002")
    product_ids = [
        uuid.UUID("018f2f21-0000-7000-8000-000000000101"),
        uuid.UUID("018f2f21-0000-7000-8000-000000000102"),
    ]

    with dbmod.SessionLocal() as db:
        db.add(
            Organization(
                id=organization_id,
                name="Test Pharmacy Group",
                status="active",
                country_code="SO",
                city_name="Mogadishu",
            )
        )
        db.add(
            Pharmacy(
                id=pharmacy_id,
                organization_id=organization_id,
                name="Test Branch",
                branch_code="test-branch",
                status="active",
                address_text="Hodan",
                country_code="SO",
                city_name="Mogadishu",
                zone_code="hodan",
            )
        )
        db.add(
            Product(
                id=product_ids[0],
                name="Amoxicillin 500mg",
                generic_name="Amoxicillin",
                form="capsule",
                strength="500mg",
                rx_required=True,
                status="active",
            )
        )
        db.add(
            Product(
                id=product_ids[1],
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
                product_id=product_ids[0],
                price_amount=Decimal("3.50"),
                currency_code="USD",
                stock_status="in_stock",
                status="active",
            )
        )
        db.add(
            PharmacyProduct(
                pharmacy_id=pharmacy_id,
                product_id=product_ids[1],
                price_amount=Decimal("1.00"),
                currency_code="USD",
                stock_status="in_stock",
                status="active",
            )
        )
        db.commit()

    return [str(product_id) for product_id in product_ids]


def test_pharmacy_catalog_default_shape() -> None:
    _init_sqlite_db()
    expected_ids = _seed_catalog_rows()
    client = TestClient(app)

    res = client.get("/v1/pharmacy/catalog")
    assert res.status_code == 200

    payload = res.json()
    assert isinstance(payload.get("items"), list)
    assert isinstance(payload.get("next"), dict)
    assert "cursor" in payload["next"]
    assert [item["id"] for item in payload["items"]] == expected_ids

    item = payload["items"][0]
    assert item["name"] == "Amoxicillin 500mg"
    assert item["rx_required"] is True
    assert item["price"] == 3.5
    assert item["subtitle"] == "$3.50"
    assert uuid.UUID(item["id"]).version == 7


def test_pharmacy_catalog_q_filters() -> None:
    _init_sqlite_db()
    _seed_catalog_rows()
    client = TestClient(app)

    res = client.get("/v1/pharmacy/catalog", params={"q": "amox"})
    assert res.status_code == 200

    items = res.json()["items"]
    assert [item["name"] for item in items] == ["Amoxicillin 500mg"]


def test_pharmacy_catalog_cursor_paginates() -> None:
    _init_sqlite_db()
    _seed_catalog_rows()
    client = TestClient(app)

    first = client.get("/v1/pharmacy/catalog", params={"limit": 1})
    assert first.status_code == 200
    p1 = first.json()
    assert len(p1["items"]) == 1
    cursor = p1["next"].get("cursor")
    assert cursor

    second = client.get(
        "/v1/pharmacy/catalog",
        params={"limit": 1, "cursor": cursor},
    )
    assert second.status_code == 200
    p2 = second.json()
    assert len(p2["items"]) == 1
    assert p2["items"][0]["id"] != p1["items"][0]["id"]
    assert p2["items"][0]["name"] == "Paracetamol 500mg"
