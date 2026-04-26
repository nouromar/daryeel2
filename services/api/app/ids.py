from __future__ import annotations

import secrets
import threading
import time
import uuid

_RAND74_MASK = (1 << 74) - 1
_RAND62_MASK = (1 << 62) - 1

_uuid7_lock = threading.Lock()
_last_timestamp_ms = -1
_last_random_bits = 0


def new_uuid7() -> uuid.UUID:
    global _last_random_bits
    global _last_timestamp_ms

    timestamp_ms = time.time_ns() // 1_000_000

    with _uuid7_lock:
        if timestamp_ms > _last_timestamp_ms:
            _last_timestamp_ms = timestamp_ms
            _last_random_bits = secrets.randbits(74)
        else:
            timestamp_ms = _last_timestamp_ms
            _last_random_bits = (_last_random_bits + 1) & _RAND74_MASK

            if _last_random_bits == 0:
                while True:
                    next_timestamp_ms = time.time_ns() // 1_000_000
                    if next_timestamp_ms > _last_timestamp_ms:
                        _last_timestamp_ms = next_timestamp_ms
                        timestamp_ms = next_timestamp_ms
                        _last_random_bits = secrets.randbits(74)
                        break

        random_bits = _last_random_bits

    rand_a = (random_bits >> 62) & 0xFFF
    rand_b = random_bits & _RAND62_MASK

    value = (
        ((timestamp_ms & ((1 << 48) - 1)) << 80)
        | (0x7 << 76)
        | (rand_a << 64)
        | (0b10 << 62)
        | rand_b
    )
    return uuid.UUID(int=value)
