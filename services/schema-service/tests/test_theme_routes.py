from fastapi.testclient import TestClient

from app.main import app


def test_themes_catalog_lists_theme_contracts() -> None:
    client = TestClient(app)
    response = client.get("/themes/catalog")
    assert response.status_code == 200
    payload = response.json()
    assert any(path.endswith("customer-default.light.json") for path in payload["themes"])


def test_get_theme_document() -> None:
    client = TestClient(app)
    response = client.get("/themes/customer-default/light")
    assert response.status_code == 200
    payload = response.json()
    assert payload["themeId"] == "customer-default"
    assert payload["themeMode"] == "light"
    assert "color.action.brand" in payload["tokens"]

    def test_theme_doc_etag_304(client):
        first = client.get("/themes/customer-default/light")
        assert first.status_code == 200
        etag = first.headers.get("ETag")
        assert etag

        second = client.get(
            "/themes/customer-default/light",
            headers={"If-None-Match": etag},
        )
        assert second.status_code == 304
        assert second.text == ""
