from pulseops import queue


def test_live(client):
    r = client.get("/health/live")
    assert r.status_code == 200
    assert r.json()["status"] == "alive"


def test_ready(client):
    r = client.get("/health/ready")
    assert r.status_code == 200
    assert r.json()["status"] == "ready"


def test_create_and_get_job(client):
    r = client.post("/jobs", json={"input": "hello platform"})
    assert r.status_code == 201
    body = r.json()
    assert body["status"] == "QUEUED"
    job_id = body["id"]

    # The job id should have been enqueued.
    assert queue.queue_depth() == 1

    r2 = client.get(f"/jobs/{job_id}")
    assert r2.status_code == 200
    assert r2.json()["input"] == "hello platform"


def test_list_jobs(client):
    client.post("/jobs", json={"input": "a"})
    client.post("/jobs", json={"input": "b"})
    r = client.get("/jobs")
    assert r.status_code == 200
    assert len(r.json()) >= 2


def test_get_missing_job_404(client):
    assert client.get("/jobs/does-not-exist").status_code == 404


def test_create_job_validation(client):
    assert client.post("/jobs", json={"input": ""}).status_code == 422


def test_metrics_endpoint(client):
    client.post("/jobs", json={"input": "x"})
    r = client.get("/metrics")
    assert r.status_code == 200
    assert b"pulseops_jobs_submitted_total" in r.content
