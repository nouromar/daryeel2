from __future__ import annotations

import json
from pathlib import Path

from app.validation import DARYEEL2_ROOT


THEME_CONTRACTS_DIR = DARYEEL2_ROOT / "packages" / "theme-contracts"


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
