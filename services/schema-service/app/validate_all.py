from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
import re
from typing import Any, Iterable

from app.contract_catalog import load_action_contract_map, load_component_contract_map
from app.validation import DARYEEL2_ROOT, validate_fragment_document, validate_screen_document
from app.budgets import (
    MAX_FRAGMENTS_PER_SCREEN,
    MAX_JSON_BYTES,
    MAX_NODES_PER_DOCUMENT,
    MAX_REF_DEPTH,
)


SCHEMA_EXAMPLES_DIR = DARYEEL2_ROOT / "packages" / "schema-contracts" / "examples"
CUSTOMER_SCREENS_DIR = DARYEEL2_ROOT / "apps" / "customer-app" / "schemas" / "screens"
CUSTOMER_FRAGMENTS_DIR = DARYEEL2_ROOT / "apps" / "customer-app" / "schemas" / "fragments"
COMPONENT_CONTRACTS_DIR = DARYEEL2_ROOT / "packages" / "component-contracts"


@dataclass(frozen=True)
class ValidationIssue:
    code: str
    message: str
    path: str


def _read_json_file(path: Path) -> dict[str, Any]:
    raw = path.read_bytes()
    if len(raw) > MAX_JSON_BYTES:
        raise ValueError(f"Document too large: {path} ({len(raw)} bytes)")
    decoded = json.loads(raw)
    if not isinstance(decoded, dict):
        raise ValueError(f"Expected JSON object at top level: {path}")
    return decoded


def _load_component_contracts(contracts_dir: Path = COMPONENT_CONTRACTS_DIR) -> dict[str, dict[str, Any]]:
    catalog_path = contracts_dir / "catalog.json"
    catalog = _read_json_file(catalog_path)
    contract_paths = catalog.get("contracts")
    if not isinstance(contract_paths, list) or not contract_paths:
        raise ValueError("component-contracts/catalog.json missing 'contracts' list")

    contracts: dict[str, dict[str, Any]] = {}
    for rel in contract_paths:
        if not isinstance(rel, str) or not rel:
            raise ValueError(f"Invalid contract path entry: {rel!r}")
        contract_path = contracts_dir / rel
        contract = _read_json_file(contract_path)
        name = contract.get("name")
        if not isinstance(name, str) or not name:
            raise ValueError(f"Contract missing name: {contract_path}")
        contracts[name] = contract

    return contracts


def _load_component_contracts_for_product(
    *,
    product: str | None,
    contracts_dir: Path = COMPONENT_CONTRACTS_DIR,
) -> dict[str, dict[str, Any]]:
    if contracts_dir != COMPONENT_CONTRACTS_DIR:
        return _load_component_contracts(contracts_dir)
    return load_component_contract_map(product=product)


def _matches_action_value_kind(raw: Any, kind: str) -> bool:
    if kind == "any":
        return True
    if kind == "null":
        return raw is None
    if kind == "string":
        return isinstance(raw, str)
    if kind == "boolean":
        return isinstance(raw, (bool, str))
    if kind == "integer":
        return (isinstance(raw, int) and not isinstance(raw, bool)) or isinstance(raw, str)
    if kind == "number":
        return (isinstance(raw, (int, float)) and not isinstance(raw, bool)) or isinstance(raw, str)
    if kind == "object":
        return isinstance(raw, dict)
    if kind == "list":
        return isinstance(raw, list)
    return False


def _validate_action_definition_against_contract(
    *,
    action_id: str,
    action: dict[str, Any],
    action_contracts: dict[str, dict[str, Any]],
    issue_path: str,
) -> list[ValidationIssue]:
    issues: list[ValidationIssue] = []

    action_type = action.get("type")
    if not isinstance(action_type, str) or not action_type:
        issues.append(
            ValidationIssue(
                code="invalid_action_type",
                message="Action definition must include string 'type'",
                path=f"{issue_path}.actions.{action_id}.type",
            )
        )
        return issues

    contract = action_contracts.get(action_type)
    if contract is None:
        issues.append(
            ValidationIssue(
                code="unknown_action_type",
                message=f"Unknown action type: {action_type}",
                path=f"{issue_path}.actions.{action_id}.type",
            )
        )
        return issues

    raw_value = action.get("value")
    value_kind = contract.get("valueKind", "any")
    allow_null = bool(contract.get("allowNullValue", False))

    if raw_value is None:
        if value_kind not in {"any", "null"} and not allow_null:
            issues.append(
                ValidationIssue(
                    code="missing_action_value",
                    message=f"Action type '{action_type}' requires 'value'",
                    path=f"{issue_path}.actions.{action_id}.value",
                )
            )
        return issues

    if not _matches_action_value_kind(raw_value, value_kind):
        issues.append(
            ValidationIssue(
                code="invalid_action_value_type",
                message=f"Action type '{action_type}' requires value kind '{value_kind}'",
                path=f"{issue_path}.actions.{action_id}.value",
            )
        )
        return issues

    if value_kind != "object":
        return issues

    value_schema = contract.get("valueSchema")
    if not isinstance(value_schema, dict):
        value_schema = {}
    required = contract.get("required")
    if not isinstance(required, list):
        required = []

    assert isinstance(raw_value, dict)

    for key in raw_value.keys():
        if key not in value_schema:
            issues.append(
                ValidationIssue(
                    code="unknown_action_value_key",
                    message=f"Unknown key '{key}' for action type '{action_type}'",
                    path=f"{issue_path}.actions.{action_id}.value.{key}",
                )
            )

    for key in required:
        if isinstance(key, str) and key not in raw_value:
            issues.append(
                ValidationIssue(
                    code="missing_action_value_key",
                    message=f"Missing required key '{key}' for action type '{action_type}'",
                    path=f"{issue_path}.actions.{action_id}.value.{key}",
                )
            )

    for key, raw in raw_value.items():
        kind = value_schema.get(key)
        if not isinstance(kind, str):
            continue
        if not _matches_action_value_kind(raw, kind):
            issues.append(
                ValidationIssue(
                    code="invalid_action_value_property_type",
                    message=(
                        f"Action type '{action_type}' key '{key}' requires kind '{kind}'"
                    ),
                    path=f"{issue_path}.actions.{action_id}.value.{key}",
                )
            )

    return issues


def _iter_nodes(node: Any) -> Iterable[dict[str, Any]]:
    if not isinstance(node, dict):
        return

    if "ref" in node:
        yield node
        return

    if "type" in node:
        yield node
        slots = node.get("slots")
        if isinstance(slots, dict):
            for children in slots.values():
                if isinstance(children, list):
                    for child in children:
                        yield from _iter_nodes(child)


def _node_count(root: dict[str, Any]) -> int:
    return sum(1 for _ in _iter_nodes(root))


def _collect_refs_from_node_tree(root: dict[str, Any]) -> set[str]:
    refs: set[str] = set()
    for n in _iter_nodes(root):
        ref = n.get("ref")
        if isinstance(ref, str) and ref:
            refs.add(ref)
    return refs


def _reachable_fragment_refs_for_screen(
    *,
    screen_root: dict[str, Any],
    fragment_docs: dict[str, dict[str, Any]],
    max_depth: int = MAX_REF_DEPTH,
    max_fragments: int = MAX_FRAGMENTS_PER_SCREEN,
) -> tuple[set[str], bool]:
    """Return (reachable_refs, exceeded_budget).

    Budget is based on unique fragment refs that may be loaded while resolving a
    screen.
    """

    initial = _collect_refs_from_node_tree(screen_root)
    if not initial:
        return set(), False

    from collections import deque

    seen: set[str] = set()
    q: deque[tuple[str, int]] = deque((r, 1) for r in initial)

    while q:
        ref, depth = q.popleft()
        if ref in seen:
            continue
        seen.add(ref)
        if len(seen) > max_fragments:
            return seen, True

        if depth > max_depth:
            # Ref depth budgets are validated separately.
            continue

        doc = fragment_docs.get(ref)
        if not isinstance(doc, dict):
            continue
        node = doc.get("node")
        if not isinstance(node, dict):
            continue

        for child_ref in _collect_refs_from_node_tree(node):
            if child_ref not in seen:
                q.append((child_ref, depth + 1))

    return seen, False


def _validate_component_node_against_contract(
    *,
    node: dict[str, Any],
    contracts: dict[str, dict[str, Any]],
    issue_path: str,
    action_ids: set[str] | None,
) -> list[ValidationIssue]:
    issues: list[ValidationIssue] = []

    if "ref" in node:
        return issues

    component_type = node.get("type")
    if not isinstance(component_type, str) or not component_type:
        return issues

    contract = contracts.get(component_type)
    if contract is None:
        issues.append(
            ValidationIssue(
                code="unknown_component",
                message=f"Unknown component type: {component_type}",
                path=issue_path,
            )
        )
        return issues

    props_schema = contract.get("propsSchema")
    if not isinstance(props_schema, dict):
        props_schema = {}

    style_contract = contract.get("styleContract")
    if not isinstance(style_contract, dict):
        style_contract = {}

    allowed_slots = contract.get("slots")
    if not isinstance(allowed_slots, list):
        allowed_slots = []
    allowed_slots_set = {s for s in allowed_slots if isinstance(s, str)}

    allowed_actions = contract.get("actions")
    if not isinstance(allowed_actions, list):
        allowed_actions = []
    allowed_actions_set = {a for a in allowed_actions if isinstance(a, str)}

    props = node.get("props")
    if props is None:
        props = {}
    if isinstance(props, dict):
        for key, value in props.items():
            if key not in props_schema:
                issues.append(
                    ValidationIssue(
                        code="unknown_prop",
                        message=f"Unknown prop '{key}' for {component_type}",
                        path=f"{issue_path}.props.{key}",
                    )
                )
                continue

            kind = props_schema.get(key)
            if kind == "string":
                if not isinstance(value, str):
                    issues.append(
                        ValidationIssue(
                            code="invalid_prop_type",
                            message=f"Prop '{key}' must be a string",
                            path=f"{issue_path}.props.{key}",
                        )
                    )
            elif kind == "enum":
                if not isinstance(value, str):
                    issues.append(
                        ValidationIssue(
                            code="invalid_prop_type",
                            message=f"Prop '{key}' must be a string enum",
                            path=f"{issue_path}.props.{key}",
                        )
                    )
                else:
                    allowed = style_contract.get(key)
                    if isinstance(allowed, list) and allowed:
                        allowed_set = {v for v in allowed if isinstance(v, str)}
                        if value not in allowed_set:
                            issues.append(
                                ValidationIssue(
                                    code="invalid_enum_value",
                                    message=f"Invalid value '{value}' for {component_type}.{key}",
                                    path=f"{issue_path}.props.{key}",
                                )
                            )
            elif kind == "boolean":
                if not isinstance(value, bool):
                    issues.append(
                        ValidationIssue(
                            code="invalid_prop_type",
                            message=f"Prop '{key}' must be a boolean",
                            path=f"{issue_path}.props.{key}",
                        )
                    )
            elif kind == "integer":
                if not isinstance(value, int) or isinstance(value, bool):
                    issues.append(
                        ValidationIssue(
                            code="invalid_prop_type",
                            message=f"Prop '{key}' must be an integer",
                            path=f"{issue_path}.props.{key}",
                        )
                    )
            elif kind == "number":
                if not isinstance(value, (int, float)) or isinstance(value, bool):
                    issues.append(
                        ValidationIssue(
                            code="invalid_prop_type",
                            message=f"Prop '{key}' must be a number",
                            path=f"{issue_path}.props.{key}",
                        )
                    )
            elif kind == "object":
                if not isinstance(value, dict):
                    issues.append(
                        ValidationIssue(
                            code="invalid_prop_type",
                            message=f"Prop '{key}' must be an object",
                            path=f"{issue_path}.props.{key}",
                        )
                    )
            elif kind == "list":
                if not isinstance(value, list):
                    issues.append(
                        ValidationIssue(
                            code="invalid_prop_type",
                            message=f"Prop '{key}' must be a list",
                            path=f"{issue_path}.props.{key}",
                        )
                    )
            else:
                # Unknown kind; treat as warning-level lint failure (strict for now).
                issues.append(
                    ValidationIssue(
                        code="unknown_contract_type",
                        message=f"Unknown contract prop kind '{kind}' for {component_type}.{key}",
                        path=f"{issue_path}.props.{key}",
                    )
                )
    else:
        issues.append(
            ValidationIssue(
                code="invalid_props",
                message=f"Props must be an object for {component_type}",
                path=f"{issue_path}.props",
            )
        )

    slots = node.get("slots")
    if slots is not None:
        if not isinstance(slots, dict):
            issues.append(
                ValidationIssue(
                    code="invalid_slots",
                    message=f"Slots must be an object for {component_type}",
                    path=f"{issue_path}.slots",
                )
            )
        else:
            for slot_name in slots.keys():
                if slot_name not in allowed_slots_set:
                    issues.append(
                        ValidationIssue(
                            code="unknown_slot",
                            message=f"Unknown slot '{slot_name}' for {component_type}",
                            path=f"{issue_path}.slots.{slot_name}",
                        )
                    )

    actions = node.get("actions")
    if actions is not None:
        if not isinstance(actions, dict):
            issues.append(
                ValidationIssue(
                    code="invalid_actions",
                    message=f"Actions must be an object for {component_type}",
                    path=f"{issue_path}.actions",
                )
            )
        else:
            for action_key, action_id in actions.items():
                if action_key not in allowed_actions_set:
                    issues.append(
                        ValidationIssue(
                            code="unknown_action_key",
                            message=f"Unknown action key '{action_key}' for {component_type}",
                            path=f"{issue_path}.actions.{action_key}",
                        )
                    )
                if action_ids is not None:
                    if not isinstance(action_id, str) or not action_id:
                        issues.append(
                            ValidationIssue(
                                code="invalid_action_id",
                                message=f"Action id for '{action_key}' must be a string",
                                path=f"{issue_path}.actions.{action_key}",
                            )
                        )
                    elif action_id not in action_ids:
                        issues.append(
                            ValidationIssue(
                                code="unknown_action_id",
                                message=f"Action id '{action_id}' is not defined in screen.actions",
                                path=f"{issue_path}.actions.{action_key}",
                            )
                        )

    return issues


def _validate_ref_resolution(
    *,
    root_node: dict[str, Any],
    available_fragment_ids: set[str],
    issue_path_prefix: str,
) -> list[ValidationIssue]:
    issues: list[ValidationIssue] = []
    for ref in _collect_refs_from_node_tree(root_node):
        if ref not in available_fragment_ids:
            issues.append(
                ValidationIssue(
                    code="missing_fragment",
                    message=f"Missing fragment for ref '{ref}'",
                    path=f"{issue_path_prefix}.ref[{ref}]",
                )
            )
    return issues


def _build_fragment_ref_graph(fragment_docs: dict[str, dict[str, Any]]) -> dict[str, set[str]]:
    graph: dict[str, set[str]] = {}
    for fragment_id, doc in fragment_docs.items():
        node = doc.get("node")
        if not isinstance(node, dict):
            graph[fragment_id] = set()
            continue
        refs = _collect_refs_from_node_tree(node)
        graph[fragment_id] = {r for r in refs if isinstance(r, str)}
    return graph


def _detect_ref_cycles(graph: dict[str, set[str]]) -> list[list[str]]:
    visited: set[str] = set()
    in_stack: set[str] = set()
    stack: list[str] = []
    cycles: list[list[str]] = []

    def dfs(node: str) -> None:
        visited.add(node)
        in_stack.add(node)
        stack.append(node)

        for nxt in graph.get(node, set()):
            if nxt not in graph:
                continue
            if nxt not in visited:
                dfs(nxt)
            elif nxt in in_stack:
                # Extract cycle path from stack
                if nxt in stack:
                    idx = stack.index(nxt)
                    cycles.append(stack[idx:] + [nxt])

        stack.pop()
        in_stack.remove(node)

    for node in graph.keys():
        if node not in visited:
            dfs(node)

    # Deduplicate cycles
    unique: list[list[str]] = []
    seen: set[tuple[str, ...]] = set()
    for c in cycles:
        t = tuple(c)
        if t not in seen:
            seen.add(t)
            unique.append(c)
    return unique


def _max_ref_depth(
    *,
    root_node: dict[str, Any],
    fragment_docs: dict[str, dict[str, Any]],
    max_budget: int = MAX_REF_DEPTH,
) -> int:
    """Compute maximum fragment-ref expansion depth reachable from a node.

    Depth counts the number of fragment expansions along a path.
    Cycles are ignored here (reported separately).
    """

    max_seen = 0
    visiting: set[str] = set()

    def walk_node(node: dict[str, Any], depth: int) -> None:
        nonlocal max_seen
        if depth > max_seen:
            max_seen = depth
        if depth > max_budget:
            return

        for n in _iter_nodes(node):
            ref = n.get("ref")
            if not isinstance(ref, str) or not ref:
                continue
            if ref in visiting:
                continue

            doc = fragment_docs.get(ref)
            if not isinstance(doc, dict):
                continue
            fragment_node = doc.get("node")
            if not isinstance(fragment_node, dict):
                continue

            visiting.add(ref)
            try:
                walk_node(fragment_node, depth + 1)
            finally:
                visiting.remove(ref)

    walk_node(root_node, 0)
    return max_seen


_SCHEMA_SCREEN_ROUTE = "customer.schema_screen"
_SCREEN_ID_RE = re.compile(r"^[a-z][a-z0-9_\-.]{0,79}$")


def _validate_schema_screen_route_args(
    *,
    action_id: str,
    action: dict[str, Any],
    issue_path: str,
) -> list[ValidationIssue]:
    issues: list[ValidationIssue] = []

    raw_value = action.get("value")
    if not isinstance(raw_value, dict):
        issues.append(
            ValidationIssue(
                code="invalid_schema_route_value",
                message="customer.schema_screen requires object 'value'",
                path=f"{issue_path}.actions.{action_id}.value",
            )
        )
        return issues

    reserved = {"screenId", "title", "service", "chromePreset", "params"}
    extra_keys = [k for k in raw_value.keys() if isinstance(k, str) and k not in reserved]
    if extra_keys:
        issues.append(
            ValidationIssue(
                code="unknown_schema_route_args",
                message=(
                    "customer.schema_screen only allows {screenId,title,service,chromePreset,params}; "
                    f"unknown keys: {sorted(extra_keys)[:10]}"
                ),
                path=f"{issue_path}.actions.{action_id}.value",
            )
        )

    screen_id = raw_value.get("screenId")
    if not isinstance(screen_id, str) or not screen_id.strip() or not _SCREEN_ID_RE.match(screen_id.strip()):
        issues.append(
            ValidationIssue(
                code="invalid_schema_route_screen_id",
                message="value.screenId must be a valid screen id",
                path=f"{issue_path}.actions.{action_id}.value.screenId",
            )
        )

    for key in ("title", "service"):
        v = raw_value.get(key)
        if v is None:
            continue
        if not isinstance(v, str):
            issues.append(
                ValidationIssue(
                    code="invalid_schema_route_string",
                    message=f"value.{key} must be a string",
                    path=f"{issue_path}.actions.{action_id}.value.{key}",
                )
            )
        elif len(v) > 120:
            issues.append(
                ValidationIssue(
                    code="schema_route_string_too_long",
                    message=f"value.{key} exceeds max length (120)",
                    path=f"{issue_path}.actions.{action_id}.value.{key}",
                )
            )

    chrome = raw_value.get("chromePreset")
    if chrome is not None:
        if not isinstance(chrome, str):
            issues.append(
                ValidationIssue(
                    code="invalid_schema_route_chrome_preset",
                    message="value.chromePreset must be a string",
                    path=f"{issue_path}.actions.{action_id}.value.chromePreset",
                )
            )
        else:
            allowed = {"standard", "pharmacy_cart_badge"}
            if chrome.strip() and chrome.strip() not in allowed:
                issues.append(
                    ValidationIssue(
                        code="unknown_schema_route_chrome_preset",
                        message=f"value.chromePreset not in allowlist: {sorted(allowed)}",
                        path=f"{issue_path}.actions.{action_id}.value.chromePreset",
                    )
                )

    params = raw_value.get("params")
    if params is not None and not isinstance(params, dict):
        issues.append(
            ValidationIssue(
                code="invalid_schema_route_params",
                message="value.params must be an object",
                path=f"{issue_path}.actions.{action_id}.value.params",
            )
        )
        params = None

    if isinstance(params, dict):
        if len(params) > 50:
            issues.append(
                ValidationIssue(
                    code="schema_route_params_budget_exceeded",
                    message="value.params exceeds max keys (50)",
                    path=f"{issue_path}.actions.{action_id}.value.params",
                )
            )

        def is_jsonish(v: Any, depth: int) -> bool:
            if v is None or isinstance(v, (str, int, float, bool)):
                return True
            if depth >= 4:
                return False
            if isinstance(v, list):
                if len(v) > 100:
                    return False
                return all(is_jsonish(x, depth + 1) for x in v)
            if isinstance(v, dict):
                if len(v) > 50:
                    return False
                for k, vv in v.items():
                    if not isinstance(k, str) or not k:
                        return False
                    if not is_jsonish(vv, depth + 1):
                        return False
                return True
            return False

        if not is_jsonish(params, 0):
            issues.append(
                ValidationIssue(
                    code="invalid_schema_route_params_value",
                    message="value.params must be JSON-like (bounded depth/types)",
                    path=f"{issue_path}.actions.{action_id}.value.params",
                )
            )

    # Payload size budget (defense-in-depth).
    try:
        import json

        if len(json.dumps(raw_value, separators=(",", ":"), sort_keys=True).encode("utf-8")) > 16 * 1024:
            issues.append(
                ValidationIssue(
                    code="schema_route_value_too_large",
                    message="customer.schema_screen value exceeds size budget (16KB)",
                    path=f"{issue_path}.actions.{action_id}.value",
                )
            )
    except Exception:
        issues.append(
            ValidationIssue(
                code="schema_route_value_not_serializable",
                message="customer.schema_screen value must be JSON-serializable",
                path=f"{issue_path}.actions.{action_id}.value",
            )
        )

    return issues


def validate_examples(
    *,
    examples_dir: Path = SCHEMA_EXAMPLES_DIR,
    contracts_dir: Path = COMPONENT_CONTRACTS_DIR,
) -> list[ValidationIssue]:
    issues: list[ValidationIssue] = []

    contracts = _load_component_contracts(contracts_dir)

    fragment_docs: dict[str, dict[str, Any]] = {}
    fragment_paths_by_id: dict[str, str] = {}

    fragment_paths: list[Path] = []
    fragment_paths.extend(sorted(examples_dir.glob("*.fragment.json")))
    if CUSTOMER_FRAGMENTS_DIR.exists():
        fragment_paths.extend(sorted(CUSTOMER_FRAGMENTS_DIR.glob("*.fragment.json")))

    for path in sorted(set(fragment_paths)):
        doc = _read_json_file(path)
        try:
            validate_fragment_document(doc)
        except Exception as e:  # pragma: no cover
            issues.append(
                ValidationIssue(
                    code="invalid_fragment_schema",
                    message=str(e),
                    path=str(path),
                )
            )
            continue

        fragment_id = doc.get("id")
        if isinstance(fragment_id, str) and fragment_id:
            fragment_docs[fragment_id] = doc
            fragment_paths_by_id[fragment_id] = str(path)
        else:
            issues.append(
                ValidationIssue(
                    code="invalid_fragment_id",
                    message="Fragment missing valid 'id'",
                    path=str(path),
                )
            )

        node = doc.get("node")
        if isinstance(node, dict):
            fragment_product = "customer_app" if path.parent == CUSTOMER_FRAGMENTS_DIR else None
            fragment_contracts = _load_component_contracts_for_product(
                product=fragment_product,
                contracts_dir=contracts_dir,
            )
            if _node_count(node) > MAX_NODES_PER_DOCUMENT:
                issues.append(
                    ValidationIssue(
                        code="node_budget_exceeded",
                        message=f"Fragment exceeds node budget ({MAX_NODES_PER_DOCUMENT})",
                        path=str(path),
                    )
                )

            # Contract validation for fragment component nodes
            for idx, n in enumerate(_iter_nodes(node)):
                issues.extend(
                    _validate_component_node_against_contract(
                        node=n,
                        contracts=fragment_contracts,
                        issue_path=f"{path.name}.node[{idx}]",
                        action_ids=None,
                    )
                )

    fragment_ids = set(fragment_docs.keys())
    component_contracts_cache: dict[str | None, dict[str, dict[str, Any]]] = {
        None: contracts,
    }
    action_contracts_cache: dict[str | None, dict[str, dict[str, Any]]] = {}

    # Ref depth budgets (compute after all fragments are loaded).
    for fragment_id, doc in fragment_docs.items():
        node = doc.get("node")
        if not isinstance(node, dict):
            continue
        max_depth = _max_ref_depth(root_node=node, fragment_docs=fragment_docs)
        if max_depth > MAX_REF_DEPTH:
            issues.append(
                ValidationIssue(
                    code="ref_depth_exceeded",
                    message=f"Fragment ref depth exceeds budget ({MAX_REF_DEPTH})",
                    path=fragment_paths_by_id.get(fragment_id, f"fragment:{fragment_id}"),
                )
            )

    # Ref cycles
    graph = _build_fragment_ref_graph(fragment_docs)
    cycles = _detect_ref_cycles(graph)
    for cycle in cycles:
        issues.append(
            ValidationIssue(
                code="ref_cycle",
                message=f"Fragment ref cycle detected: {' -> '.join(cycle)}",
                path="fragments",
            )
        )

    # Validate refs inside fragments point to known fragments
    for fragment_id, doc in fragment_docs.items():
        node = doc.get("node")
        if isinstance(node, dict):
            issues.extend(
                _validate_ref_resolution(
                    root_node=node,
                    available_fragment_ids=fragment_ids,
                    issue_path_prefix=f"fragment:{fragment_id}",
                )
            )

    # Screens
    screen_paths: list[Path] = []
    screen_paths.extend(sorted(examples_dir.glob("*.screen.json")))
    if CUSTOMER_SCREENS_DIR.exists():
        screen_paths.extend(sorted(CUSTOMER_SCREENS_DIR.glob("*.screen.json")))

    for path in sorted(set(screen_paths)):
        doc = _read_json_file(path)
        try:
            validate_screen_document(doc)
        except Exception as e:
            issues.append(
                ValidationIssue(
                    code="invalid_screen_schema",
                    message=str(e),
                    path=str(path),
                )
            )
            continue

        root = doc.get("root")
        if not isinstance(root, dict):
            issues.append(
                ValidationIssue(
                    code="missing_root",
                    message="Screen missing object 'root'",
                    path=str(path),
                )
            )
            continue

        product_raw = doc.get("product")
        product = product_raw if isinstance(product_raw, str) and product_raw else None
        effective_contracts = component_contracts_cache.setdefault(
            product,
            _load_component_contracts_for_product(
                product=product,
                contracts_dir=contracts_dir,
            ),
        )
        action_contracts = action_contracts_cache.setdefault(
            product,
            load_action_contract_map(product=product),
        )

        if _node_count(root) > MAX_NODES_PER_DOCUMENT:
            issues.append(
                ValidationIssue(
                    code="node_budget_exceeded",
                    message=f"Screen exceeds node budget ({MAX_NODES_PER_DOCUMENT})",
                    path=str(path),
                )
            )

        max_depth = _max_ref_depth(root_node=root, fragment_docs=fragment_docs)
        if max_depth > MAX_REF_DEPTH:
            issues.append(
                ValidationIssue(
                    code="ref_depth_exceeded",
                    message=f"Screen ref depth exceeds budget ({MAX_REF_DEPTH})",
                    path=str(path),
                )
            )

        _, exceeded = _reachable_fragment_refs_for_screen(
            screen_root=root,
            fragment_docs=fragment_docs,
            max_depth=MAX_REF_DEPTH,
            max_fragments=MAX_FRAGMENTS_PER_SCREEN,
        )
        if exceeded:
            issues.append(
                ValidationIssue(
                    code="fragments_budget_exceeded",
                    message=f"Screen exceeds fragments budget ({MAX_FRAGMENTS_PER_SCREEN})",
                    path=str(path),
                )
            )

        screen_actions = doc.get("actions")
        action_ids: set[str] = set()
        if isinstance(screen_actions, dict):
            action_ids = {k for k in screen_actions.keys() if isinstance(k, str) and k}

        # Contract validation
        for idx, n in enumerate(_iter_nodes(root)):
            issues.extend(
                _validate_component_node_against_contract(
                    node=n,
                    contracts=effective_contracts,
                    issue_path=f"{path.name}.root[{idx}]",
                    action_ids=action_ids,
                )
            )

        # Ref validation
        issues.extend(
            _validate_ref_resolution(
                root_node=root,
                available_fragment_ids=fragment_ids,
                issue_path_prefix=path.name,
            )
        )

        # Action validation (route settings guardrails)
        if isinstance(screen_actions, dict):
            for action_id, action in screen_actions.items():
                if not isinstance(action_id, str) or not action_id:
                    continue
                if not isinstance(action, dict):
                    issues.append(
                        ValidationIssue(
                            code="invalid_action_definition",
                            message="Action definition must be an object",
                            path=f"{path.name}.actions.{action_id}",
                        )
                    )
                    continue

                issues.extend(
                    _validate_action_definition_against_contract(
                        action_id=action_id,
                        action=action,
                        action_contracts=action_contracts,
                        issue_path=path.name,
                    )
                )

                if action.get("type") == "navigate" and action.get("route") == _SCHEMA_SCREEN_ROUTE:
                    issues.extend(
                        _validate_schema_screen_route_args(
                            action_id=action_id,
                            action=action,
                            issue_path=path.name,
                        )
                    )

    return issues


def main() -> None:
    issues = validate_examples()
    if not issues:
        print("OK: schema-contracts examples validated")
        return

    print("Schema validation failed:\n")
    for issue in issues:
        print(f"- [{issue.code}] {issue.path}: {issue.message}")

    raise SystemExit(1)


if __name__ == "__main__":
    main()
