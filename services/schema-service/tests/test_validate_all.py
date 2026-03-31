from __future__ import annotations

import json
from pathlib import Path

import pytest

from app.validate_all import COMPONENT_CONTRACTS_DIR, SCHEMA_EXAMPLES_DIR, validate_examples


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
