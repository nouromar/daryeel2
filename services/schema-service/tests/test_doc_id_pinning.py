from fastapi.testclient import TestClient

from app.main import app


def test_screen_selector_includes_doc_id_and_can_fetch_by_doc_id() -> None:
    client = TestClient(app)

    selector = client.get("/schemas/screens/customer_home")
    assert selector.status_code == 200
    doc_id = selector.headers.get("x-daryeel-doc-id")
    assert doc_id

    immutable = client.get(f"/schemas/screens/docs/by-id/{doc_id}")
    assert immutable.status_code == 200
    assert "immutable" in (immutable.headers.get("cache-control") or "").lower()
    assert immutable.json() == selector.json()


def test_screen_selector_304_includes_doc_id_header() -> None:
    client = TestClient(app)

    first = client.get("/schemas/screens/customer_home")
    assert first.status_code == 200
    etag = first.headers.get("etag")
    doc_id = first.headers.get("x-daryeel-doc-id")
    assert etag
    assert doc_id

    second = client.get(
        "/schemas/screens/customer_home",
        headers={"if-none-match": etag},
    )
    assert second.status_code == 304
    assert second.headers.get("etag") == etag
    assert second.headers.get("x-daryeel-doc-id") == doc_id


def test_theme_selector_includes_doc_id_and_can_fetch_by_doc_id() -> None:
    client = TestClient(app)

    selector = client.get("/themes/customer-default/light")
    assert selector.status_code == 200
    doc_id = selector.headers.get("x-daryeel-doc-id")
    assert doc_id

    immutable = client.get(f"/themes/docs/by-id/{doc_id}")
    assert immutable.status_code == 200
    assert "immutable" in (immutable.headers.get("cache-control") or "").lower()
    assert immutable.json() == selector.json()
