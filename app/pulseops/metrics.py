"""Prometheus metrics shared across API and worker."""
from __future__ import annotations

from prometheus_client import Counter, Gauge, Histogram

# --- API metrics ---
http_requests_total = Counter(
    "pulseops_http_requests_total",
    "Total HTTP requests",
    ["method", "path", "status"],
)
http_request_duration_seconds = Histogram(
    "pulseops_http_request_duration_seconds",
    "HTTP request latency",
    ["method", "path"],
)

# --- Job / worker metrics ---
jobs_submitted_total = Counter("pulseops_jobs_submitted_total", "Jobs submitted via API")
jobs_processed_total = Counter(
    "pulseops_jobs_processed_total", "Jobs processed by worker", ["status"]
)
job_processing_seconds = Histogram(
    "pulseops_job_processing_seconds", "Time spent processing a job"
)
queue_depth_gauge = Gauge("pulseops_queue_depth", "Current queue backlog")
worker_last_success_timestamp = Gauge(
    "pulseops_worker_last_success_timestamp_seconds",
    "Unix time of the last successfully processed job",
)
