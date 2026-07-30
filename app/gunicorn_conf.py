"""Gunicorn config for the API. Uvicorn workers, graceful shutdown."""
import multiprocessing
import os

bind = f"0.0.0.0:{os.getenv('PORT', '8000')}"
workers = int(os.getenv("WEB_CONCURRENCY", max(2, multiprocessing.cpu_count())))
worker_class = "uvicorn.workers.UvicornWorker"
# Give in-flight requests time to finish on SIGTERM (rolling deploys).
graceful_timeout = 30
timeout = 60
keepalive = 5
accesslog = "-"
errorlog = "-"
