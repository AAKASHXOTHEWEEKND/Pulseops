from pulseops import queue
from pulseops.db import Job, JobStatus, get_sessionmaker
from pulseops.worker import process_one


def _make_job(input_text="hello platform"):
    import uuid

    job_id = str(uuid.uuid4())
    Session = get_sessionmaker()
    with Session() as db:
        db.add(Job(id=job_id, input=input_text, status=JobStatus.QUEUED))
        db.commit()
    return job_id


def test_process_one_completes_job():
    job_id = _make_job("hello platform")
    assert process_one(job_id) is True

    Session = get_sessionmaker()
    with Session() as db:
        job = db.get(Job, job_id)
        assert job.status == JobStatus.COMPLETED
        assert job.result == "HELLO PLATFORM"


def test_process_missing_job_returns_false():
    assert process_one("nonexistent") is False


def test_end_to_end_enqueue_then_process(client):
    r = client.post("/jobs", json={"input": "abc"})
    job_id = r.json()["id"]
    popped = queue.dequeue(timeout=1)
    assert popped == job_id
    assert process_one(job_id) is True
