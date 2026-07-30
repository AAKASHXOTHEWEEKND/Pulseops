# syntax=docker/dockerfile:1.7
# ---------------------------------------------------------------------------
# Shared image for BOTH the API and the worker. They run the same code and
# differ only by entrypoint command (see docker-compose / ECS / task defs).
# One image => one thing to build, scan and promote unchanged staging->prod.
# ---------------------------------------------------------------------------

# --- Builder: install deps into a venv --------------------------------------
FROM python:3.12-slim AS builder

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /build
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy only requirements first for better layer caching.
COPY requirements.txt .
RUN pip install -r requirements.txt

# --- Runtime: small, non-root -----------------------------------------------
FROM python:3.12-slim AS runtime

# curl is used by container HEALTHCHECK; tini gives us proper PID1 signal handling.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl tini \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system app && useradd --system --gid app --home /app app

ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PORT=8000

COPY --from=builder /opt/venv /opt/venv

WORKDIR /app
COPY --chown=app:app pulseops ./pulseops
COPY --chown=app:app migrations ./migrations
COPY --chown=app:app alembic.ini gunicorn_conf.py ./

# Build-time version stamp (git SHA), surfaced in logs, /health and metrics.
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION}

USER app
EXPOSE 8000

# tini reaps zombies and forwards SIGTERM for graceful shutdown.
ENTRYPOINT ["/usr/bin/tini", "--"]

# Default command runs the API; the worker overrides this.
HEALTHCHECK --interval=15s --timeout=3s --start-period=20s --retries=3 \
  CMD curl -fsS http://localhost:8000/health/live || exit 1

CMD ["gunicorn", "pulseops.api:app", "-c", "gunicorn_conf.py"]
