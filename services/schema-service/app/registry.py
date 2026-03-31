from __future__ import annotations

import json
from pathlib import Path

from app.schemas import BootstrapResponse, FragmentSchema, ScreenSchema
from app.validation import DARYEEL2_ROOT, validate_fragment_document, validate_screen_document


SCHEMA_EXAMPLES_DIR = DARYEEL2_ROOT / "packages" / "schema-contracts" / "examples"


def _load_screen_documents() -> dict[str, ScreenSchema]:
    screens: dict[str, ScreenSchema] = {}
    for path in SCHEMA_EXAMPLES_DIR.glob("*.screen.json"):
        document = json.loads(path.read_text())
        validate_screen_document(document)
        screen = ScreenSchema.model_validate(document)
        screens[screen.id] = screen
    return screens


def _load_fragment_documents() -> dict[str, FragmentSchema]:
    fragments: dict[str, FragmentSchema] = {}
    for path in SCHEMA_EXAMPLES_DIR.glob("*.fragment.json"):
        document = json.loads(path.read_text())
        validate_fragment_document(document)
        fragment = FragmentSchema.model_validate(document)
        fragments[fragment.id] = fragment
    return fragments


SCREENS = _load_screen_documents()
FRAGMENTS = _load_fragment_documents()


BOOTSTRAP = BootstrapResponse(product="customer_app", screens=sorted(SCREENS.keys()))


def get_bootstrap() -> BootstrapResponse:
    return BOOTSTRAP


def get_screen(screen_id: str) -> ScreenSchema | None:
    return SCREENS.get(screen_id)


def get_fragment(fragment_id: str) -> FragmentSchema | None:
    return FRAGMENTS.get(fragment_id)