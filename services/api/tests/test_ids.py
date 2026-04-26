from __future__ import annotations

import uuid

from app.ids import new_uuid7


def test_new_uuid7_is_unique_ordered_and_versioned() -> None:
    values = [new_uuid7() for _ in range(128)]

    assert len(values) == len(set(values))
    assert all(isinstance(value, uuid.UUID) for value in values)
    assert all(value.version == 7 for value in values)
    assert all(value.variant == uuid.RFC_4122 for value in values)
    assert values == sorted(values, key=lambda item: item.int)
