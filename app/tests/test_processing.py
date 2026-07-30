from pulseops.processing import transform


def test_transform_uppercases():
    assert transform("hello platform") == "HELLO PLATFORM"


def test_transform_empty():
    assert transform("") == ""


def test_transform_is_idempotent():
    once = transform("abc")
    assert transform(once) == once
