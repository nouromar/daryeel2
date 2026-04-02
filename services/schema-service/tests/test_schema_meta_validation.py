from app.validation import validate_fragment_document, validate_screen_document


def test_screen_schema_accepts_optional_meta_block() -> None:
    validate_screen_document(
        {
            "schemaVersion": "1.0",
            "id": "customer_home",
            "documentType": "screen",
            "product": "customer_app",
            "themeId": "customer-default",
            "themeMode": "light",
            "meta": {
                "minRuntimeApi": 1,
                "requiresCapabilities": ["refNodes"],
                "contractsCatalogVersion": "2026-04-01",
            },
            "root": {"type": "Text"},
        }
    )


def test_fragment_schema_accepts_optional_meta_block() -> None:
    validate_fragment_document(
        {
            "schemaVersion": "1.0",
            "id": "fragment_v1",
            "documentType": "fragment",
            "meta": {
                "minRuntimeApi": 1,
                "requiresCapabilities": ["refNodes"],
            },
            "node": {"type": "Text"},
        }
    )
