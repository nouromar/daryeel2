from fastapi.testclient import TestClient

from app.main import app


def test_dev_mappings_endpoint_includes_doc_ids() -> None:
    client = TestClient(app)
    response = client.get("/dev/mappings", params={"product": "customer_app"})
    assert response.status_code == 200
    payload = response.json()

    assert payload["product"] == "customer_app"
    assert "schemas" in payload
    assert "themes" in payload

    screens = payload["schemas"].get("screens")
    assert isinstance(screens, dict)
    assert "customer_home" in screens
    assert isinstance(screens["customer_home"], str)
    assert len(screens["customer_home"]) == 64


def test_dev_recent_errors_captures_schema_404() -> None:
    client = TestClient(app)

    missing = client.get("/schemas/screens/does_not_exist")
    assert missing.status_code == 404

    recent = client.get("/dev/errors/recent", params={"limit": 10})
    assert recent.status_code == 200
    payload = recent.json()

    errors = payload.get("errors")
    assert isinstance(errors, list)
    assert any(e.get("path") == "/schemas/screens/does_not_exist" and e.get("statusCode") == 404 for e in errors)
