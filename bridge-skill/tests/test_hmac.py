"""Tests for HMAC signing — must stay in sync with backend/app/security/hmac_verify.py."""

import hashlib
import hmac as hmac_mod

from companion_bridge import compute_hmac


def _reference_hmac(secret: str, timestamp: str, payload: str) -> str:
    """Reference implementation copied from the backend for cross-check."""
    message = f"{timestamp}{payload}"
    return hmac_mod.new(
        secret.encode("utf-8"),
        message.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()


class TestComputeHMAC:
    def test_basic_signature(self):
        sig = compute_hmac("mysecret", "1700000000", '{"key":"value"}')
        assert isinstance(sig, str)
        assert len(sig) == 64  # SHA-256 hex digest

    def test_matches_backend_reference(self):
        secret = "test-secret-abc123"
        ts = "1700000000"
        payload = '{"agent_name":"bot","skill_name":"ping","title":"hello"}'

        bridge_sig = compute_hmac(secret, ts, payload)
        backend_sig = _reference_hmac(secret, ts, payload)
        assert bridge_sig == backend_sig

    def test_different_secrets_different_sigs(self):
        ts = "1700000000"
        payload = '{"a":"b"}'
        sig1 = compute_hmac("secret1", ts, payload)
        sig2 = compute_hmac("secret2", ts, payload)
        assert sig1 != sig2

    def test_different_timestamps_different_sigs(self):
        secret = "same"
        payload = '{"a":"b"}'
        sig1 = compute_hmac(secret, "1000", payload)
        sig2 = compute_hmac(secret, "2000", payload)
        assert sig1 != sig2

    def test_empty_payload(self):
        sig = compute_hmac("secret", "123", "")
        assert isinstance(sig, str)
        assert len(sig) == 64

    def test_deterministic(self):
        args = ("secret", "1700000000", '{"x":1}')
        assert compute_hmac(*args) == compute_hmac(*args)
