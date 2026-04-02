from __future__ import annotations

import json
import hashlib
from pathlib import Path

from app.schemas import BootstrapResponse, FragmentSchema, ScreenSchema
from app.validation import DARYEEL2_ROOT, validate_fragment_document, validate_screen_document


SCHEMA_EXAMPLES_DIR = DARYEEL2_ROOT / "packages" / "schema-contracts" / "examples"


def _doc_id(payload: dict) -> str:
    raw = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


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


SCREENS_BY_DOC_ID: dict[str, ScreenSchema] = {}
SCREENS_DOC_ID_BY_ID: dict[str, str] = {}
for _screen in SCREENS.values():
    _id = _doc_id(_screen.model_dump())
    SCREENS_BY_DOC_ID[_id] = _screen
    SCREENS_DOC_ID_BY_ID[_screen.id] = _id

FRAGMENTS_BY_DOC_ID: dict[str, FragmentSchema] = {}
FRAGMENTS_DOC_ID_BY_ID: dict[str, str] = {}
for _frag in FRAGMENTS.values():
    _id = _doc_id(_frag.model_dump())
    FRAGMENTS_BY_DOC_ID[_id] = _frag
    FRAGMENTS_DOC_ID_BY_ID[_frag.id] = _id


BOOTSTRAP = BootstrapResponse(product="customer_app", screens=sorted(SCREENS.keys()))


def get_bootstrap() -> BootstrapResponse:
    return BOOTSTRAP


def get_screen(screen_id: str) -> ScreenSchema | None:
    return SCREENS.get(screen_id)


def get_screen_by_doc_id(doc_id: str) -> ScreenSchema | None:
    return SCREENS_BY_DOC_ID.get(doc_id)


def get_screen_doc_id(screen_id: str) -> str | None:
    return SCREENS_DOC_ID_BY_ID.get(screen_id)


def get_fragment(fragment_id: str) -> FragmentSchema | None:
    return FRAGMENTS.get(fragment_id)


def get_fragment_by_doc_id(doc_id: str) -> FragmentSchema | None:
    return FRAGMENTS_BY_DOC_ID.get(doc_id)


def get_fragment_doc_id(fragment_id: str) -> str | None:
    return FRAGMENTS_DOC_ID_BY_ID.get(fragment_id)