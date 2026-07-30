"""Structured JSON logging with correlation identifiers.

Every log line is JSON so it can be shipped to CloudWatch/Loki and queried by
field. A ``correlation_id`` (job id or request id) is threaded through via a
``contextvars`` so worker and API logs can be tied to a single job.
"""
from __future__ import annotations

import logging
from contextvars import ContextVar

from pythonjsonlogger import json as jsonlogger

from .config import get_settings

# Correlation id carried per-request / per-job.
correlation_id: ContextVar[str] = ContextVar("correlation_id", default="-")


class CorrelationFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        record.correlation_id = correlation_id.get()
        record.app_version = get_settings().app_version
        record.app_env = get_settings().app_env
        return True


def configure_logging() -> None:
    settings = get_settings()
    handler = logging.StreamHandler()
    formatter = jsonlogger.JsonFormatter(
        "%(asctime)s %(levelname)s %(name)s %(message)s "
        "%(correlation_id)s %(app_version)s %(app_env)s",
        rename_fields={"asctime": "timestamp", "levelname": "level"},
    )
    handler.setFormatter(formatter)
    handler.addFilter(CorrelationFilter())

    root = logging.getLogger()
    root.handlers.clear()
    root.addHandler(handler)
    root.setLevel(settings.log_level.upper())

    # Quiet noisy libraries a little.
    logging.getLogger("uvicorn.access").setLevel(logging.WARNING)
