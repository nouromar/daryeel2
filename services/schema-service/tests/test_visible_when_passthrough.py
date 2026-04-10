import pytest

from app.schemas import ScreenSchema


def test_visible_when_is_preserved_in_response_payload() -> None:
    doc = {
        "schemaVersion": "1.0",
        "id": "test_visible_when",
        "documentType": "screen",
        "product": "customer_app",
        "themeId": "customer-default",
        "themeMode": "light",
        "root": {
            "type": "Column",
            "visibleWhen": {"expr": "len(state.foo) > 0"},
            "props": {"spacing": 12},
            "slots": {
                "children": [
                    {
                        "type": "Text",
                        "visibleWhen": {"expr": "state.bar == true"},
                        "props": {"text": "Hello", "variant": "body"},
                    }
                ]
            },
        },
        "actions": {},
    }

    schema = ScreenSchema.model_validate(doc)
    payload = schema.model_dump()

    assert payload["root"]["visibleWhen"] == {"expr": "len(state.foo) > 0"}
    assert payload["root"]["slots"]["children"][0]["visibleWhen"] == {"expr": "state.bar == true"}
