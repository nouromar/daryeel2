from __future__ import annotations

import json
import hashlib
from pathlib import Path

from app.validation import DARYEEL2_ROOT
from app.schemas import ThemeDocument


THEME_CONTRACTS_DIR = DARYEEL2_ROOT / "packages" / "theme-contracts"


def _doc_id(payload: dict) -> str:
    raw = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def _load_json(path: Path) -> dict:
    return json.loads(path.read_text())


def list_theme_paths() -> list[str]:
    catalog = _load_json(THEME_CONTRACTS_DIR / "catalog.json")
    return catalog.get("themes", [])


def load_theme_document(theme_path: str) -> dict:
    path = THEME_CONTRACTS_DIR / theme_path
    if not path.exists():
        raise FileNotFoundError(theme_path)
    return _load_json(path)


def find_theme_path(theme_id: str, theme_mode: str) -> str | None:
    # Current contract naming convention: <themeId>.<mode>.json
    candidate = f"themes/{theme_id}.{theme_mode}.json"
    if candidate in set(list_theme_paths()):
        return candidate
    return None


def _build_theme_by_doc_id() -> tuple[dict[str, dict], dict[str, dict[str, str]]]:
    out: dict[str, dict] = {}
    by_id_mode: dict[str, dict[str, str]] = {}
    for theme_path in list_theme_paths():
        try:
            payload = ThemeDocument.model_validate(load_theme_document(theme_path)).model_dump()
        except Exception:
            # Ignore invalid theme documents; selector endpoints will 404/500 accordingly.
            continue
        doc_id = _doc_id(payload)
        out[doc_id] = payload

        theme_id = payload.get("themeId")
        theme_mode = payload.get("themeMode")
        if isinstance(theme_id, str) and theme_id and isinstance(theme_mode, str) and theme_mode:
            by_id_mode.setdefault(theme_id, {})[theme_mode] = doc_id

    return out, by_id_mode


THEMES_BY_DOC_ID, THEME_DOC_IDS_BY_ID_MODE = _build_theme_by_doc_id()


def get_theme_by_doc_id(doc_id: str) -> dict | None:
    return THEMES_BY_DOC_ID.get(doc_id)


def get_theme_doc_ids_by_id_mode() -> dict[str, dict[str, str]]:
    # Return a copy to avoid accidental mutation.
    return {k: dict(v) for k, v in THEME_DOC_IDS_BY_ID_MODE.items()}
