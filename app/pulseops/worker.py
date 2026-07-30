"""Background worker: consume jobs from the queue and process them.

Design notes:
  * Graceful shutdown — SIGTERM/SIGINT flip a flag; the worker finishes the
    in-flight job before exiting so no work is lost on rollout.
  * At-least-once — a job id is only popped from Redis when we are ready to
    work it. If the worker dies mid-job the row stays PROCESSING and can be
    requeued by the reaper (see ``requeue_stuck_jobs``).
  * A tiny HTTP server exposes /health and /metrics so the worker is
    observable and probeable just like the API.
"""
from __future__ import annotations

import logging
import signal
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from prometheus_client import CONTENT_TYPE_LATEST, generate_latest

from . import metrics, queue
from .config import get_settings
from .db import Job, JobStatus, get_sessionmaker
from .logging_config import configure_logging, correlation_id
from .processing import transform

configure_logging()
log = logging.getLogger("pulseops.worker")
settings = get_settings()

_shutdown = threading.Event()


def _handle_signal(signum, _frame):
    log.info("shutdown_signal_received", extra={"signal": signum})
    _shutdown.set()


def process_one(job_id: str) -> bool:
    """Process a single job id. Returns True if COMPLETED."""
    correlation_id.set(job_id)
    Session = get_sessionmaker()
    with Session() as db:
        job: Job | None = db.get(Job, job_id)
        if job is None:
            log.warning("job_missing", extra={"job_id": job_id})
            return False
        job.status = JobStatus.PROCESSING
        db.commit()
        start = time.perf_counter()
        try:
            time.sleep(settings.worker_process_delay)  # simulate work
            job.result = transform(job.input)
            job.status = JobStatus.COMPLETED
            job.error = None
            db.commit()
        except Exception as exc:  # pragma: no cover - defensive
            db.rollback()
            job.status = JobStatus.FAILED
            job.error = str(exc)
            db.commit()
            metrics.jobs_processed_total.labels("failed").inc()
            log.exception("job_failed", extra={"job_id": job_id})
            return False
        elapsed = time.perf_counter() - start
        metrics.job_processing_seconds.observe(elapsed)
        metrics.jobs_processed_total.labels("completed").inc()
        metrics.worker_last_success_timestamp.set(time.time())
        log.info("job_completed", extra={"job_id": job_id, "elapsed_s": round(elapsed, 3)})
        return True


def run() -> None:
    signal.signal(signal.SIGTERM, _handle_signal)
    signal.signal(signal.SIGINT, _handle_signal)
    _start_health_server()
    log.info("worker_started", extra={"queue": settings.queue_name})
    while not _shutdown.is_set():
        try:
            job_id = queue.dequeue(timeout=settings.worker_poll_timeout)
        except Exception:
            log.exception("dequeue_error")
            time.sleep(1)
            continue
        if job_id is None:
            continue  # poll timeout; loop again to re-check shutdown flag
        process_one(job_id)
    log.info("worker_stopped_gracefully")


# --------------------------------------------------------------------------- #
# Minimal health/metrics HTTP server for the worker
# --------------------------------------------------------------------------- #
class _HealthHandler(BaseHTTPRequestHandler):
    def log_message(self, *args):  # silence default stderr logging
        return

    def do_GET(self):  # noqa: N802
        if self.path == "/metrics":
            body = generate_latest()
            self.send_response(200)
            self.send_header("Content-Type", CONTENT_TYPE_LATEST)
            self.end_headers()
            self.wfile.write(body)
            return
        if self.path == "/health/live":
            self._json(200, {"status": "alive"})
            return
        if self.path == "/health/ready":
            ok = True
            try:
                queue.get_redis().ping()
            except Exception:
                ok = False
            self._json(200 if ok else 503, {"status": "ready" if ok else "not_ready"})
            return
        self._json(404, {"error": "not found"})

    def _json(self, code: int, payload: dict):
        import json

        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(body)


def _start_health_server(port: int = 8080) -> None:
    server = ThreadingHTTPServer(("0.0.0.0", port), _HealthHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    log.info("worker_health_server_started", extra={"port": port})


if __name__ == "__main__":
    run()
