from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from app.validation import DARYEEL2_ROOT


COMPONENT_CONTRACTS_DIR = DARYEEL2_ROOT / "packages" / "component-contracts"


def _load_json(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text())
    if not isinstance(data, dict):
        raise ValueError(f"Expected JSON object: {path}")
    return data


def _load_contracts() -> tuple[dict[str, Any], list[dict[str, Any]]]:
    catalog = _load_json(COMPONENT_CONTRACTS_DIR / "catalog.json")
    contract_paths = catalog.get("contracts")
    if not isinstance(contract_paths, list):
        contract_paths = []

    contracts: list[dict[str, Any]] = []
    for rel in contract_paths:
        if not isinstance(rel, str) or not rel:
            continue
        contract = _load_json(COMPONENT_CONTRACTS_DIR / rel)
        contracts.append(contract)

    return catalog, contracts


CATALOG, CONTRACTS = _load_contracts()


def component_contracts_payload() -> dict[str, Any]:
    # Keep the payload stable and JSON-serializable.
    return {
        "package": CATALOG.get("package", "component-contracts"),
        "version": CATALOG.get("version", "0.0.0"),
        "contracts": CONTRACTS,
    }
