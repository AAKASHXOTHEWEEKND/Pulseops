"""Business logic for transforming a job's input into its result.

Kept deliberately simple (uppercase transform) and pure so it is trivial to
unit-test. The operational/infrastructure quality is the focus, not this logic.
"""
from __future__ import annotations


def transform(text: str) -> str:
    """Transform job input into its result.

    Example: "hello platform" -> "HELLO PLATFORM".
    """
    return text.upper()
