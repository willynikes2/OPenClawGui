"""HMAC-SHA256 verification for ingest event integrity."""

import hashlib
import hmac
import time


def compute_hmac(secret: str, timestamp: str, payload: str) -> str:
    message = f"{timestamp}{payload}"
    return hmac.new(
        secret.encode("utf-8"),
        message.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()


def verify_hmac(
    secret: str,
    timestamp: str,
    payload: str,
    signature: str,
    max_age_seconds: int = 300,
) -> bool:
    """Verify HMAC signature and check timestamp freshness."""
    # Check timestamp freshness
    try:
        ts = int(timestamp)
    except (ValueError, TypeError):
        return False

    now = int(time.time())
    if abs(now - ts) > max_age_seconds:
        return False

    expected = compute_hmac(secret, timestamp, payload)
    return hmac.compare_digest(expected, signature)
