"""FastAPI application: health + job endpoints."""
from __future__ import annotations

import logging
import time
import uuid

from fastapi import Depends, FastAPI, HTTPException, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest
from pydantic import BaseModel, Field
from sqlalchemy import select, text
from sqlalchemy.orm import Session

from . import metrics, queue
from .config import get_settings
from .db import Job, JobStatus, get_sessionmaker
from .logging_config import configure_logging, correlation_id

configure_logging()
log = logging.getLogger("pulseops.api")
settings = get_settings()

app = FastAPI(title="PulseOps API", version=settings.app_version)

# The frontend is served separately; allow it to call the API.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


def get_db() -> Session:
    session = get_sessionmaker()()
    try:
        yield session
    finally:
        session.close()


# --------------------------------------------------------------------------- #
# Schemas
# --------------------------------------------------------------------------- #
class JobCreate(BaseModel):
    input: str = Field(..., min_length=1, max_length=10_000)


class JobOut(BaseModel):
    id: str
    input: str
    status: str
    result: str | None = None
    error: str | None = None
    created_at: str | None = None
    updated_at: str | None = None


# --------------------------------------------------------------------------- #
# Middleware: correlation id + metrics
# --------------------------------------------------------------------------- #
@app.middleware("http")
async def observability_middleware(request: Request, call_next):
    cid = request.headers.get("x-correlation-id", str(uuid.uuid4()))
    correlation_id.set(cid)
    start = time.perf_counter()
    # Use route template (not raw path) to keep metric cardinality bounded.
    route = request.scope.get("route")
    path_label = getattr(route, "path", request.url.path)
    try:
        response = await call_next(request)
        status = response.status_code
    except Exception:
        metrics.http_requests_total.labels(request.method, path_label, "500").inc()
        log.exception("unhandled_error", extra={"path": path_label})
        raise
    duration = time.perf_counter() - start
    metrics.http_requests_total.labels(request.method, path_label, str(status)).inc()
    metrics.http_request_duration_seconds.labels(request.method, path_label).observe(duration)
    response.headers["x-correlation-id"] = cid
    return response


# --------------------------------------------------------------------------- #
# Health
# --------------------------------------------------------------------------- #
@app.get("/health/live")
def live():
    """Liveness: process is up. Cheap, never touches dependencies."""
    return {"status": "alive", "version": settings.app_version}


@app.get("/health/ready")
def ready(response: Response, db: Session = Depends(get_db)):
    """Readiness: can we serve traffic? Checks DB + Redis.

    Honours BREAK_READINESS to safely demonstrate the controlled-failure flow.
    """
    if settings.break_readiness:
        response.status_code = 503
        return {"status": "not_ready", "reason": "break_readiness flag enabled"}

    checks: dict[str, str] = {}
    healthy = True
    try:
        db.execute(text("SELECT 1"))
        checks["database"] = "ok"
    except Exception as exc:  # pragma: no cover - exercised in failure demo
        checks["database"] = f"error: {exc}"
        healthy = False
    try:
        queue.get_redis().ping()
        checks["redis"] = "ok"
    except Exception as exc:  # pragma: no cover
        checks["redis"] = f"error: {exc}"
        healthy = False

    if not healthy:
        response.status_code = 503
        return {"status": "not_ready", "checks": checks}
    return {"status": "ready", "checks": checks}


@app.get("/metrics")
def prometheus_metrics():
    metrics.queue_depth_gauge.set(_safe_queue_depth())
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


def _safe_queue_depth() -> int:
    try:
        return queue.queue_depth()
    except Exception:
        return 0


# --------------------------------------------------------------------------- #
# Jobs
# --------------------------------------------------------------------------- #
@app.post("/jobs", response_model=JobOut, status_code=201)
def create_job(payload: JobCreate, db: Session = Depends(get_db)):
    job_id = str(uuid.uuid4())
    correlation_id.set(job_id)
    job = Job(id=job_id, input=payload.input, status=JobStatus.QUEUED)
    db.add(job)
    db.commit()
    # Enqueue only after the DB row is durable.
    try:
        queue.enqueue(job_id)
    except Exception:
        # Roll the job to FAILED rather than leaving an orphan QUEUED row.
        job.status = JobStatus.FAILED
        job.error = "failed to enqueue"
        db.commit()
        log.exception("enqueue_failed")
        raise HTTPException(status_code=503, detail="queue unavailable") from None
    metrics.jobs_submitted_total.inc()
    log.info("job_submitted", extra={"job_id": job_id})
    return JobOut(**job.to_dict())


@app.get("/jobs", response_model=list[JobOut])
def list_jobs(db: Session = Depends(get_db), limit: int = 50):
    limit = max(1, min(limit, 200))
    rows = db.execute(select(Job).order_by(Job.created_at.desc()).limit(limit)).scalars().all()
    return [JobOut(**r.to_dict()) for r in rows]


@app.get("/jobs/{job_id}", response_model=JobOut)
def get_job(job_id: str, db: Session = Depends(get_db)):
    job = db.get(Job, job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="job not found")
    return JobOut(**job.to_dict())
