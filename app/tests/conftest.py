"""Test fixtures: in-memory SQLite + fakeredis so tests need no services."""
from __future__ import annotations

import os

os.environ.setdefault("DATABASE_URL", "sqlite+pysqlite:///:memory:")
os.environ.setdefault("APP_ENV", "ci")

import fakeredis  # noqa: E402
import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import create_engine  # noqa: E402
from sqlalchemy.orm import sessionmaker  # noqa: E402
from sqlalchemy.pool import StaticPool  # noqa: E402

import pulseops.db as db_module  # noqa: E402
import pulseops.queue as queue_module  # noqa: E402
from pulseops.db import Base  # noqa: E402


@pytest.fixture
def engine():
    eng = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(eng)
    return eng


@pytest.fixture(autouse=True)
def _wire(engine, monkeypatch):
    Session = sessionmaker(bind=engine, expire_on_commit=False, future=True)
    monkeypatch.setattr(db_module, "_engine", engine)
    monkeypatch.setattr(db_module, "_SessionLocal", Session)

    fake = fakeredis.FakeRedis(decode_responses=True)
    monkeypatch.setattr(queue_module, "_client", fake)
    yield


@pytest.fixture
def client():
    from pulseops.api import app

    return TestClient(app)
