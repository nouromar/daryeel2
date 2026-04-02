from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path


@lru_cache(maxsize=1)
def load_mappings() -> dict:
    """Load selector->version mappings for schema-service.

    This enables rollback by switching which on-disk document a stable selector
    (like a screen id or theme id/mode) points at.

    File format (JSON):
      {
        "screens": {"customer_home": "customer_home.screen.json"},
        "fragments": {"section:customer_welcome_v1": "customer_welcome.fragment.json"},
        "themes": {"customer-default:light": "themes/customer-default.light.json"}
      }

    The file is optional; if missing, the registries fall back to deterministic
    defaults.
    """

    path = Path(__file__).with_name("mappings.json")
    if not path.exists():
        return {}

    data = json.loads(path.read_text())
    if not isinstance(data, dict):
        return {}

    # Keep structure flexible; callers validate what they need.
    return data
