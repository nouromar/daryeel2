from __future__ import annotations

import json
from pathlib import Path

from jsonschema import Draft202012Validator
from referencing import Registry, Resource


REPO_ROOT = Path(__file__).resolve().parents[4]
DARYEEL2_ROOT = REPO_ROOT / "Daryeel2"
DOMAIN_SCHEMAS_DIR = DARYEEL2_ROOT / "packages" / "domain" / "schemas"
SCHEMA_CONTRACTS_DIR = DARYEEL2_ROOT / "packages" / "schema-contracts"
SCHEMA_SCHEMA_DIR = SCHEMA_CONTRACTS_DIR / "schemas"


def _load_json(path: Path) -> dict:
    return json.loads(path.read_text())


def build_registry() -> Registry:
    registry = Registry()
    schema_files = list(DOMAIN_SCHEMAS_DIR.glob("*.json")) + list(
        SCHEMA_SCHEMA_DIR.glob("*.json")
    )

    for path in schema_files:
        contents = _load_json(path)
        schema_id = contents.get("$id")
        if schema_id:
            registry = registry.with_resource(schema_id, Resource.from_contents(contents))
    return registry


def validate_screen_document(document: dict) -> None:
    screen_schema = _load_json(SCHEMA_SCHEMA_DIR / "screen.schema.json")
    validator = Draft202012Validator(screen_schema, registry=build_registry())
    validator.validate(document)


def validate_fragment_document(document: dict) -> None:
    fragment_schema = _load_json(SCHEMA_SCHEMA_DIR / "fragment.schema.json")
    validator = Draft202012Validator(fragment_schema, registry=build_registry())
    validator.validate(document)