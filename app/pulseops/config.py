"""Centralised, environment-based configuration.

All configuration comes from environment variables — nothing is hard-coded and
no secrets live in the image. See ``.env.example`` for the full list.
"""
from __future__ import annotations

from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="", env_file=".env", extra="ignore")

    # --- Application ---
    app_env: str = Field(default="local", description="local|ci|staging|production")
    log_level: str = Field(default="INFO")
    # Populated at build time with the git SHA so logs/metrics carry the version.
    app_version: str = Field(default="dev")

    # --- Database ---
    # e.g. postgresql+psycopg://user:pass@host:5432/pulseops
    database_url: str = Field(
        default="postgresql+psycopg://pulseops:pulseops@localhost:5432/pulseops"
    )
    db_pool_size: int = Field(default=5)
    db_max_overflow: int = Field(default=5)

    # --- Queue (Redis) ---
    redis_url: str = Field(default="redis://localhost:6379/0")
    queue_name: str = Field(default="pulseops:jobs")

    # --- Worker ---
    worker_poll_timeout: int = Field(default=5, description="BLPOP timeout seconds")
    worker_process_delay: float = Field(
        default=0.5, description="Simulated processing time per job (seconds)"
    )

    # --- Deliberate-failure toggle (used for the controlled-failure demo) ---
    # When true the readiness probe reports unhealthy without crashing the process,
    # which lets us demonstrate detection + rollback safely.
    break_readiness: bool = Field(default=False)


@lru_cache
def get_settings() -> Settings:
    return Settings()
