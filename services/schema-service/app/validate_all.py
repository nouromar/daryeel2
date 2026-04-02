from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

from app.validation import DARYEEL2_ROOT, validate_fragment_document, validate_screen_document


SCHEMA_EXAMPLES_DIR = DARYEEL2_ROOT / "packages" / "schema-contracts" / "examples"
COMPONENT_CONTRACTS_DIR = DARYEEL2_ROOT / "packages" / "component-contracts"


MAX_JSON_BYTES = 256 * 1024
MAX_NODES_PER_DOCUMENT = 5_000
MAX_REF_DEPTH = 32
MAX_FRAGMENTS_PER_SCREEN = 200


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


def validate_examples(
    *,
    examples_dir: Path = SCHEMA_EXAMPLES_DIR,
    contracts_dir: Path = COMPONENT_CONTRACTS_DIR,
) -> list[ValidationIssue]:
    issues: list[ValidationIssue] = []

    contracts = _load_component_contracts(contracts_dir)

    fragment_docs: dict[str, dict[str, Any]] = {}
    fragment_paths_by_id: dict[str, str] = {}
    for path in sorted(examples_dir.glob("*.fragment.json")):
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
                        contracts=contracts,
                        issue_path=f"{path.name}.node[{idx}]",
                        action_ids=None,
                    )
                )

    fragment_ids = set(fragment_docs.keys())

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
    for path in sorted(examples_dir.glob("*.screen.json")):
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
                    contracts=contracts,
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
