from __future__ import annotations

import json
import hashlib
from pathlib import Path
from threading import RLock

from app.schemas import BootstrapResponse, FragmentSchema, ScreenSchema
from app.validation import DARYEEL2_ROOT, validate_fragment_document, validate_screen_document
from app.settings import settings


SCHEMA_EXAMPLES_DIR = DARYEEL2_ROOT / "packages" / "schema-contracts" / "examples"
CUSTOMER_SCREENS_DIR = DARYEEL2_ROOT / "apps" / "customer-app" / "schemas" / "screens"
CUSTOMER_FRAGMENTS_DIR = DARYEEL2_ROOT / "apps" / "customer-app" / "schemas" / "fragments"


def _doc_id(payload: dict) -> str:
    raw = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def _load_screen_documents() -> dict[str, ScreenSchema]:
    screens: dict[str, ScreenSchema] = {}
    screen_sources = [SCHEMA_EXAMPLES_DIR, CUSTOMER_SCREENS_DIR]
    for source_dir in screen_sources:
        if not source_dir.exists():
            continue
        for path in source_dir.glob("*.screen.json"):
            document = json.loads(path.read_text())
            validate_screen_document(document)
            screen = ScreenSchema.model_validate(document)
            screens[screen.id] = screen
    return screens


def _load_fragment_documents() -> dict[str, FragmentSchema]:
    fragments: dict[str, FragmentSchema] = {}
    fragment_sources = [SCHEMA_EXAMPLES_DIR, CUSTOMER_FRAGMENTS_DIR]
    for source_dir in fragment_sources:
        if not source_dir.exists():
            continue
        for path in source_dir.glob("*.fragment.json"):
            document = json.loads(path.read_text())
            validate_fragment_document(document)
            fragment = FragmentSchema.model_validate(document)
            fragments[fragment.id] = fragment
    return fragments

_LOCK = RLock()


SCREENS: dict[str, ScreenSchema] = {}
FRAGMENTS: dict[str, FragmentSchema] = {}


def _validate_fixtures_on_startup() -> None:
    if not settings.validate_fixtures_on_startup:
        return

    # Import here to keep module import order simple.
    from app.validate_all import COMPONENT_CONTRACTS_DIR, SCHEMA_EXAMPLES_DIR, validate_examples

    issues = validate_examples(
        examples_dir=SCHEMA_EXAMPLES_DIR,
        contracts_dir=COMPONENT_CONTRACTS_DIR,
    )
    if not issues:
        return

    summary_lines = [
        f"Schema fixture validation failed with {len(issues)} issue(s):"
    ]
    for i in issues[:25]:
        summary_lines.append(f"- {i.code}: {i.message} ({i.path})")
    if len(issues) > 25:
        summary_lines.append(f"- ... and {len(issues) - 25} more")

    msg = "\n".join(summary_lines)
    if settings.strict_fixture_validation:
        raise RuntimeError(msg)

    # Non-strict mode: log and continue.
    import logging

    logging.getLogger("daryeel.validation").error(msg)


_validate_fixtures_on_startup()

SCREENS_BY_DOC_ID: dict[str, ScreenSchema] = {}
SCREENS_DOC_ID_BY_ID: dict[str, str] = {}

FRAGMENTS_BY_DOC_ID: dict[str, FragmentSchema] = {}
FRAGMENTS_DOC_ID_BY_ID: dict[str, str] = {}

BOOTSTRAP = BootstrapResponse(product="customer_app", screens=[])


def reload_registry() -> dict[str, int]:
    """Reload schema documents from disk.

    This is intended for local development so editing JSON fixtures under
    apps/customer-app/schemas immediately affects served payloads without
    requiring a process restart.
    """

    screens = _load_screen_documents()
    fragments = _load_fragment_documents()

    screens_by_doc_id: dict[str, ScreenSchema] = {}
    screens_doc_id_by_id: dict[str, str] = {}
    for screen in screens.values():
        doc_id = _doc_id(screen.model_dump())
        screens_by_doc_id[doc_id] = screen
        screens_doc_id_by_id[screen.id] = doc_id

    fragments_by_doc_id: dict[str, FragmentSchema] = {}
    fragments_doc_id_by_id: dict[str, str] = {}
    for frag in fragments.values():
        doc_id = _doc_id(frag.model_dump())
        fragments_by_doc_id[doc_id] = frag
        fragments_doc_id_by_id[frag.id] = doc_id

    bootstrap = BootstrapResponse(product="customer_app", screens=sorted(screens.keys()))

    with _LOCK:
        SCREENS.clear()
        SCREENS.update(screens)
        FRAGMENTS.clear()
        FRAGMENTS.update(fragments)

        SCREENS_BY_DOC_ID.clear()
        SCREENS_BY_DOC_ID.update(screens_by_doc_id)
        SCREENS_DOC_ID_BY_ID.clear()
        SCREENS_DOC_ID_BY_ID.update(screens_doc_id_by_id)

        FRAGMENTS_BY_DOC_ID.clear()
        FRAGMENTS_BY_DOC_ID.update(fragments_by_doc_id)
        FRAGMENTS_DOC_ID_BY_ID.clear()
        FRAGMENTS_DOC_ID_BY_ID.update(fragments_doc_id_by_id)

        global BOOTSTRAP
        BOOTSTRAP = bootstrap

    return {
        "screens": len(screens),
        "fragments": len(fragments),
    }


# Load initial fixtures on import.
reload_registry()


def get_bootstrap() -> BootstrapResponse:
    with _LOCK:
        return BOOTSTRAP


def get_screen(screen_id: str) -> ScreenSchema | None:
    with _LOCK:
        return SCREENS.get(screen_id)


def get_screen_by_doc_id(doc_id: str) -> ScreenSchema | None:
    with _LOCK:
        return SCREENS_BY_DOC_ID.get(doc_id)


def get_screen_doc_id(screen_id: str) -> str | None:
    with _LOCK:
        return SCREENS_DOC_ID_BY_ID.get(screen_id)


def get_fragment(fragment_id: str) -> FragmentSchema | None:
    with _LOCK:
        return FRAGMENTS.get(fragment_id)


def get_fragment_by_doc_id(doc_id: str) -> FragmentSchema | None:
    with _LOCK:
        return FRAGMENTS_BY_DOC_ID.get(doc_id)


def get_fragment_doc_id(fragment_id: str) -> str | None:
    with _LOCK:
        return FRAGMENTS_DOC_ID_BY_ID.get(fragment_id)