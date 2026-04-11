from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from app.validation import DARYEEL2_ROOT


SHARED_COMPONENT_CONTRACTS_DIR = DARYEEL2_ROOT / "packages" / "component-contracts"
APPS_DIR = DARYEEL2_ROOT / "apps"

_PRODUCT_APP_DIRS = {
    "customer_app": "customer-app",
    "provider_app": "provider-app",
}

_CORE_ACTION_CONTRACTS: list[dict[str, Any]] = [
    {
        "type": "navigate",
        "scope": "runtime",
        "category": "navigation",
        "version": "1.0",
        "valueKind": "any",
        "allowNullValue": True,
    },
    {
        "type": "open_url",
        "scope": "runtime",
        "category": "navigation",
        "version": "1.0",
        "valueKind": "any",
        "allowNullValue": True,
    },
    {
        "type": "submit_form",
        "scope": "runtime",
        "category": "form",
        "version": "1.0",
        "valueKind": "any",
        "allowNullValue": True,
    },
    {
        "type": "track_event",
        "scope": "runtime",
        "category": "telemetry",
        "version": "1.0",
        "valueKind": "any",
        "allowNullValue": True,
    },
    {
        "type": "set_state",
        "scope": "runtime",
        "category": "state",
        "version": "1.0",
        "valueKind": "any",
        "allowNullValue": True,
    },
    {
        "type": "patch_state",
        "scope": "runtime",
        "category": "state",
        "version": "1.0",
        "valueKind": "any",
        "allowNullValue": True,
    },
]


def _load_json(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text())
    if not isinstance(data, dict):
        raise ValueError(f"Expected JSON object: {path}")
    return data


def _load_catalog_entries(base_dir: Path) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    catalog_path = base_dir / "catalog.json"
    if not catalog_path.exists():
        return {}, []

    catalog = _load_json(catalog_path)
    contract_paths = catalog.get("contracts")
    if not isinstance(contract_paths, list):
        contract_paths = []

    contracts: list[dict[str, Any]] = []
    for rel in contract_paths:
        if not isinstance(rel, str) or not rel:
            continue
        contract = _load_json(base_dir / rel)
        contracts.append(contract)

    return catalog, contracts


def _app_contract_dir(product: str | None, kind: str) -> Path | None:
    if product is None:
        return None

    app_dir = _PRODUCT_APP_DIRS.get(product)
    if app_dir is None:
        return None

    return APPS_DIR / app_dir / "contracts" / kind


def _merge_contracts(
    shared_contracts: list[dict[str, Any]],
    app_contracts: list[dict[str, Any]],
    *,
    key_field: str,
) -> list[dict[str, Any]]:
    merged: dict[str, dict[str, Any]] = {}
    for contract in shared_contracts:
        key = contract.get(key_field)
        if isinstance(key, str) and key:
            merged[key] = contract

    for contract in app_contracts:
        key = contract.get(key_field)
        if isinstance(key, str) and key:
            merged[key] = contract

    return list(merged.values())


def load_component_contract_list(product: str | None = None) -> list[dict[str, Any]]:
    _, shared_contracts = _load_catalog_entries(SHARED_COMPONENT_CONTRACTS_DIR)
    app_dir = _app_contract_dir(product, "components")
    _, app_contracts = _load_catalog_entries(app_dir) if app_dir is not None else ({}, [])
    return _merge_contracts(shared_contracts, app_contracts, key_field="name")



def load_component_contract_map(product: str | None = None) -> dict[str, dict[str, Any]]:
    return {
        contract["name"]: contract
        for contract in load_component_contract_list(product=product)
        if isinstance(contract.get("name"), str) and contract.get("name")
    }



def component_contracts_payload(product: str | None = None) -> dict[str, Any]:
    catalog, _ = _load_catalog_entries(SHARED_COMPONENT_CONTRACTS_DIR)
    return {
        "package": catalog.get("package", "component-contracts"),
        "version": catalog.get("version", "0.0.0"),
        "product": product,
        "contracts": load_component_contract_list(product=product),
    }



def load_action_contract_list(product: str | None = None) -> list[dict[str, Any]]:
    app_dir = _app_contract_dir(product, "actions")
    app_catalog, app_contracts = _load_catalog_entries(app_dir) if app_dir is not None else ({}, [])
    _ = app_catalog
    return _merge_contracts(_CORE_ACTION_CONTRACTS, app_contracts, key_field="type")



def load_action_contract_map(product: str | None = None) -> dict[str, dict[str, Any]]:
    return {
        contract["type"]: contract
        for contract in load_action_contract_list(product=product)
        if isinstance(contract.get("type"), str) and contract.get("type")
    }



def action_contracts_payload(product: str | None = None) -> dict[str, Any]:
    return {
        "package": "action-contracts",
        "version": "0.1.0",
        "product": product,
        "contracts": load_action_contract_list(product=product),
    }
