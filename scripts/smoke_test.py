#!/usr/bin/env python3
"""Post-deployment smoke test — validates the real business flow end to end.

Exits 0 ONLY when: readiness is green, a job can be submitted, it reaches
COMPLETED within the timeout, and the returned result matches expectation.
Any failure exits non-zero and prints actionable diagnostics.

Usage:
    python scripts/smoke_test.py --base-url http://localhost:8000
    python scripts/smoke_test.py --base-url https://api-staging.example.com --timeout 60

Only depends on the Python standard library so it runs anywhere (CI, laptop).
"""
from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.error
import urllib.request

DEFAULT_INPUT = "hello platform"
EXPECTED_RESULT = "HELLO PLATFORM"


def _req(method: str, url: str, body: dict | None = None, timeout: float = 10.0):
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Content-Type": "application/json"} if data else {}
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=timeout) as resp:  # noqa: S310
        return resp.status, json.loads(resp.read().decode() or "{}")


def fail(msg: str, detail: object = None) -> "NoReturn":  # type: ignore[name-defined]
    print(f"SMOKE FAIL: {msg}", file=sys.stderr)
    if detail is not None:
        print(f"  detail: {detail}", file=sys.stderr)
    sys.exit(1)


def wait_ready(base: str, timeout: float) -> None:
    deadline = time.monotonic() + timeout
    last = None
    while time.monotonic() < deadline:
        try:
            status, body = _req("GET", f"{base}/health/ready")
            if status == 200 and body.get("status") == "ready":
                print(f"readiness OK: {body}")
                return
            last = (status, body)
        except urllib.error.URLError as e:
            last = str(e)
        time.sleep(2)
    fail("API never became ready", last)


def submit_job(base: str, text: str) -> str:
    try:
        status, body = _req("POST", f"{base}/jobs", {"input": text})
    except urllib.error.HTTPError as e:
        fail("POST /jobs failed", f"{e.code} {e.read().decode()}")
    if status != 201 or "id" not in body:
        fail("POST /jobs returned unexpected response", body)
    print(f"submitted job {body['id']} (status={body['status']})")
    return body["id"]


def poll_completion(base: str, job_id: str, timeout: float) -> dict:
    deadline = time.monotonic() + timeout
    last = None
    while time.monotonic() < deadline:
        status, body = _req("GET", f"{base}/jobs/{job_id}")
        last = body
        state = body.get("status")
        if state == "COMPLETED":
            print(f"job {job_id} COMPLETED")
            return body
        if state == "FAILED":
            fail("job reached FAILED state", body)
        time.sleep(1)
    fail(f"job did not reach COMPLETED within {timeout}s", last)


def main() -> int:
    p = argparse.ArgumentParser(description="PulseOps post-deploy smoke test")
    p.add_argument("--base-url", required=True, help="API base URL, e.g. http://localhost:8000")
    p.add_argument("--timeout", type=float, default=60.0, help="overall per-phase timeout (s)")
    p.add_argument("--input", default=DEFAULT_INPUT)
    p.add_argument("--expected", default=EXPECTED_RESULT)
    args = p.parse_args()

    base = args.base_url.rstrip("/")
    print(f"== PulseOps smoke test against {base} ==")

    wait_ready(base, args.timeout)
    job_id = submit_job(base, args.input)
    job = poll_completion(base, job_id, args.timeout)

    result = job.get("result")
    if result != args.expected:
        fail("result did not match expected value", f"got={result!r} want={args.expected!r}")

    print(f"result validated: {result!r}")
    print("SMOKE PASS: full business flow succeeded")
    return 0


if __name__ == "__main__":
    sys.exit(main())
