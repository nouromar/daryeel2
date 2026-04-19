from __future__ import annotations

import json
import hashlib
import time
from dataclasses import dataclass

from app.settings import settings


@dataclass(frozen=True)
class CacheValue:
    payload_json: str
    etag: str
    doc_id: str


class CacheBackend:
    def get(self, key: str) -> CacheValue | None:
        raise NotImplementedError

    def set(self, key: str, value: CacheValue, ttl_seconds: int | None) -> None:
        raise NotImplementedError

    def clear(self) -> None:
        raise NotImplementedError


class InMemoryCacheBackend(CacheBackend):
    def __init__(self) -> None:
        self._store: dict[str, tuple[CacheValue, float | None]] = {}

    def get(self, key: str) -> CacheValue | None:
        item = self._store.get(key)
        if item is None:
            return None
        value, expires_at = item
        if expires_at is not None and time.time() >= expires_at:
            self._store.pop(key, None)
            return None
        return value

    def set(self, key: str, value: CacheValue, ttl_seconds: int | None) -> None:
        expires_at = None if ttl_seconds is None else (time.time() + ttl_seconds)
        self._store[key] = (value, expires_at)

    def clear(self) -> None:
        self._store.clear()


class RedisCacheBackend(CacheBackend):
    """Optional Redis cache backend.

    This module intentionally imports redis lazily so schema-service can run
    without Redis in early phases.

    To enable:
    - set SCHEMA_SERVICE_REDIS_URL
    - ensure the `redis` package is installed
    """

    def __init__(self, redis_url: str, key_prefix: str) -> None:
        try:
            import redis  # type: ignore
        except Exception as exc:  # pragma: no cover
            raise RuntimeError(
                "Redis backend requires the `redis` Python package"
            ) from exc

        self._client = redis.Redis.from_url(redis_url, decode_responses=True)
        self._prefix = key_prefix

    def _k(self, key: str) -> str:
        return f"{self._prefix}{key}"

    def get(self, key: str) -> CacheValue | None:
        raw = self._client.get(self._k(key))
        if raw is None:
            return None
        decoded = json.loads(raw)
        if not isinstance(decoded, dict):
            return None
        payload_json = decoded.get("payload_json")
        etag = decoded.get("etag")
        doc_id = decoded.get("doc_id")
        if not isinstance(payload_json, str) or not isinstance(etag, str):
            return None
        if not isinstance(doc_id, str) or not doc_id:
            # Backwards compatible with old cache entries.
            doc_id = "legacy:sha256:" + hashlib.sha256(payload_json.encode("utf-8")).hexdigest()
        return CacheValue(payload_json=payload_json, etag=etag, doc_id=doc_id)

    def set(self, key: str, value: CacheValue, ttl_seconds: int | None) -> None:
        body = json.dumps(
            {
                "payload_json": value.payload_json,
                "etag": value.etag,
                "doc_id": value.doc_id,
            }
        )
        full_key = self._k(key)
        if ttl_seconds is None:
            self._client.set(full_key, body)
        else:
            self._client.setex(full_key, ttl_seconds, body)

    def clear(self) -> None:
        # Clear only this service's keys (prefix-scoped), not the entire Redis DB.
        for key in self._client.scan_iter(match=f"{self._prefix}*"):
            self._client.delete(key)


def build_cache_backend() -> CacheBackend:
    if settings.redis_url:
        return RedisCacheBackend(
            redis_url=settings.redis_url,
            key_prefix=settings.redis_key_prefix,
        )
    return InMemoryCacheBackend()
