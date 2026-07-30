"""Thin Redis-backed queue wrapper.

Redis is used as a simple, reliable list-based queue (``LPUSH`` / ``BLPOP``).
It decouples request handling (API) from asynchronous processing (worker) and
is trivial to run both locally (docker-compose) and in the cloud (ElastiCache).
"""
from __future__ import annotations

import redis

from .config import get_settings

_client: redis.Redis | None = None


def get_redis() -> redis.Redis:
    global _client
    if _client is None:
        _client = redis.Redis.from_url(
            get_settings().redis_url, decode_responses=True, socket_connect_timeout=5
        )
    return _client


def enqueue(job_id: str) -> None:
    settings = get_settings()
    get_redis().lpush(settings.queue_name, job_id)


def dequeue(timeout: int) -> str | None:
    """Blocking pop. Returns the job id or None on timeout."""
    settings = get_settings()
    item = get_redis().blpop([settings.queue_name], timeout=timeout)
    if item is None:
        return None
    _, job_id = item
    return job_id


def queue_depth() -> int:
    settings = get_settings()
    return int(get_redis().llen(settings.queue_name))
