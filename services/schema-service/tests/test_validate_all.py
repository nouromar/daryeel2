from __future__ import annotations

import json
from pathlib import Path

import pytest

from app.validate_all import COMPONENT_CONTRACTS_DIR, MAX_FRAGMENTS_PER_SCREEN, MAX_REF_DEPTH, SCHEMA_EXAMPLES_DIR, validate_examples


def test_validate_examples_ok() -> None:
    issues = validate_examples(
        examples_dir=SCHEMA_EXAMPLES_DIR,
        contracts_dir=COMPONENT_CONTRACTS_DIR,
    )
    assert issues == []


def test_unknown_prop_is_reported(tmp_path: Path) -> None:
    # Copy the real examples into a temp dir and introduce an unknown prop.
    examples_dir = tmp_path / "examples"
    examples_dir.mkdir(parents=True)

    screen_path = SCHEMA_EXAMPLES_DIR / "customer_home.screen.json"
    fragment_path = SCHEMA_EXAMPLES_DIR / "customer_welcome.fragment.json"

    screen_doc = json.loads(screen_path.read_text())
    fragment_doc = json.loads(fragment_path.read_text())

    # Find the first InfoCard and add an unknown prop.
    body = screen_doc["root"]["slots"]["body"]
    info_card = next(n for n in body if n.get("type") == "InfoCard")
    info_card.setdefault("props", {})["unknownProp"] = "nope"

    (examples_dir / screen_path.name).write_text(json.dumps(screen_doc))
    (examples_dir / fragment_path.name).write_text(json.dumps(fragment_doc))

    issues = validate_examples(examples_dir=examples_dir, contracts_dir=COMPONENT_CONTRACTS_DIR)
    assert any(i.code == "unknown_prop" for i in issues)


def test_ref_depth_budget_exceeded(tmp_path: Path) -> None:
    examples_dir = tmp_path / "examples"
    examples_dir.mkdir(parents=True)

    depth = MAX_REF_DEPTH + 1
    fragment_ids = [f"section:depth_chain_v{i}" for i in range(depth)]

    for i, fragment_id in enumerate(fragment_ids):
        next_id = fragment_ids[i + 1] if i + 1 < len(fragment_ids) else None
        node: dict[str, object] = {
            "type": "ScreenTemplate",
            "slots": {
                "body": ([{"ref": next_id}] if next_id is not None else []),
            },
        }
        frag_doc = {
            "schemaVersion": "1.0",
            "id": fragment_id,
            "documentType": "fragment",
            "node": node,
        }
        (examples_dir / f"depth_{i}.fragment.json").write_text(json.dumps(frag_doc))

    screen_doc = {
        "schemaVersion": "1.0",
        "id": "depth_budget_test",
        "documentType": "screen",
        "product": "customer_app",
        "themeId": "customer-default",
        "themeMode": "light",
        "root": {
            "type": "ScreenTemplate",
            "slots": {"body": [{"ref": fragment_ids[0]}]},
        },
    }
    (examples_dir / "depth_budget_test.screen.json").write_text(json.dumps(screen_doc))

    issues = validate_examples(examples_dir=examples_dir, contracts_dir=COMPONENT_CONTRACTS_DIR)
    assert any(i.code == "ref_depth_exceeded" for i in issues)


def test_fragments_budget_exceeded(tmp_path: Path) -> None:
    examples_dir = tmp_path / "examples"
    examples_dir.mkdir(parents=True)

    fragment_ids = [f"section:frag_v{i}" for i in range(MAX_FRAGMENTS_PER_SCREEN + 1)]

    for i, fragment_id in enumerate(fragment_ids):
        frag_doc = {
            "schemaVersion": "1.0",
            "id": fragment_id,
            "documentType": "fragment",
            "node": {
                "type": "InfoCard",
                "props": {"title": f"F{i}"},
            },
        }
        (examples_dir / f"frag_{i}.fragment.json").write_text(json.dumps(frag_doc))

    screen_doc = {
        "schemaVersion": "1.0",
        "id": "fragments_budget_test",
        "documentType": "screen",
        "product": "customer_app",
        "themeId": "customer-default",
        "themeMode": "light",
        "root": {
            "type": "ScreenTemplate",
            "slots": {"body": [{"ref": fid} for fid in fragment_ids]},
        },
    }
    (examples_dir / "fragments_budget_test.screen.json").write_text(json.dumps(screen_doc))

    issues = validate_examples(examples_dir=examples_dir, contracts_dir=COMPONENT_CONTRACTS_DIR)
    assert any(i.code == "fragments_budget_exceeded" for i in issues)
