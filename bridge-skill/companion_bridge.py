"""
AgentCompanion Bridge Skill — sends structured events to the AgentCompanion backend.

Runs inside the OpenClaw / Clawdbot runtime. Wraps skill outputs into the Event
schema, HMAC-SHA256 signs them, and POSTs to ``/ingest``.

Usage::

    from companion_bridge import CompanionBridge

    bridge = CompanionBridge()                     # loads config.yaml
    bridge = CompanionBridge("path/to/config.yaml")  # explicit path

    # Simple event
    bridge.send(
        agent_name="my-agent",
        skill_name="daily-summary",
        title="Daily summary for 2026-02-14",
        body_raw="All systems nominal.",
        severity="info",
        tags=["daily", "summary"],
    )

    # Decorator for automatic wrapping
    @bridge.skill("web-scraper")
    def scrape_website(url: str) -> dict:
        return {"url": url, "status": "ok", "items": 42}
"""

from __future__ import annotations

import hashlib
import hmac as hmac_mod
import json
import logging
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable

import httpx
import yaml

logger = logging.getLogger("companion_bridge")

_DEFAULT_CONFIG_PATH = Path(__file__).parent / "config.yaml"


class CompanionBridgeError(Exception):
    """Base exception for bridge errors."""


class ConfigError(CompanionBridgeError):
    """Raised when configuration is missing or invalid."""


class IngestError(CompanionBridgeError):
    """Raised when the backend rejects or cannot process an event."""


# ---------------------------------------------------------------------------
# HMAC helpers — must match backend/app/security/hmac_verify.py exactly
# ---------------------------------------------------------------------------

def compute_hmac(secret: str, timestamp: str, payload: str) -> str:
    """Compute HMAC-SHA256 matching the backend verification logic."""
    message = f"{timestamp}{payload}"
    return hmac_mod.new(
        secret.encode("utf-8"),
        message.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()


# ---------------------------------------------------------------------------
# Config loader
# ---------------------------------------------------------------------------

class BridgeConfig:
    """Typed wrapper around the YAML config file."""

    def __init__(self, path: str | Path = _DEFAULT_CONFIG_PATH) -> None:
        path = Path(path)
        if not path.exists():
            raise ConfigError(f"Config file not found: {path}")

        with open(path, "r") as f:
            raw = yaml.safe_load(f)

        if not isinstance(raw, dict):
            raise ConfigError("Config file must be a YAML mapping")

        self.backend_url: str = raw.get("backend_url", "").rstrip("/")
        self.instance_id: str = raw.get("instance_id", "")
        self.instance_secret: str = raw.get("instance_secret", "")
        self.default_source_type: str = raw.get("default_source_type", "skill")
        self.timeout: int = raw.get("timeout", 10)
        self.retries: int = raw.get("retries", 2)

        if not self.backend_url:
            raise ConfigError("backend_url is required in config")
        if not self.instance_id:
            raise ConfigError("instance_id is required in config")
        if not self.instance_secret:
            raise ConfigError("instance_secret is required in config")


# ---------------------------------------------------------------------------
# Bridge
# ---------------------------------------------------------------------------

class CompanionBridge:
    """Main bridge class that formats, signs, and sends events."""

    VALID_SEVERITIES = {"info", "warn", "critical"}
    VALID_SOURCE_TYPES = {"gateway", "skill", "telegram", "sensor"}

    def __init__(self, config_path: str | Path = _DEFAULT_CONFIG_PATH) -> None:
        self.config = BridgeConfig(config_path)
        self._client = httpx.Client(timeout=self.config.timeout)

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def send(
        self,
        *,
        agent_name: str,
        skill_name: str,
        title: str,
        body_raw: str | None = None,
        body_structured_json: dict[str, Any] | None = None,
        tags: list[str] | None = None,
        severity: str = "info",
        source_type: str | None = None,
        timestamp: datetime | None = None,
    ) -> dict:
        """Format, sign, and POST a single event to the backend.

        Returns the JSON response from the backend on success.
        Raises ``IngestError`` on failure.
        """
        severity = severity.lower()
        if severity not in self.VALID_SEVERITIES:
            raise ValueError(f"severity must be one of {self.VALID_SEVERITIES}, got {severity!r}")

        src = source_type or self.config.default_source_type
        if src not in self.VALID_SOURCE_TYPES:
            raise ValueError(f"source_type must be one of {self.VALID_SOURCE_TYPES}, got {src!r}")

        ts = timestamp or datetime.now(timezone.utc)

        payload = {
            "source_type": src,
            "agent_name": agent_name,
            "skill_name": skill_name,
            "timestamp": ts.isoformat(),
            "title": title,
            "severity": severity,
        }
        if body_raw is not None:
            payload["body_raw"] = body_raw
        if body_structured_json is not None:
            payload["body_structured_json"] = body_structured_json
        if tags is not None:
            payload["tags"] = tags

        return self._post(payload)

    def send_batch(self, events: list[dict]) -> list[dict]:
        """Send multiple events sequentially. Returns list of responses.

        Each dict in *events* should contain the same kwargs accepted by
        :meth:`send` (without the leading ``*``).
        """
        results = []
        for event_kwargs in events:
            results.append(self.send(**event_kwargs))
        return results

    def skill(self, skill_name: str, *, agent_name: str = "openclaw") -> Callable:
        """Decorator that wraps a function's return value into an event.

        The decorated function must return a ``dict`` (used as
        ``body_structured_json``) or a ``str`` (used as ``body_raw``).

        Example::

            @bridge.skill("web-scraper")
            def scrape(url: str) -> dict:
                return {"url": url, "items": 42}
        """
        def decorator(fn: Callable) -> Callable:
            def wrapper(*args: Any, **kwargs: Any) -> Any:
                result = fn(*args, **kwargs)
                title = f"{skill_name}: {fn.__name__}"

                send_kwargs: dict[str, Any] = {
                    "agent_name": agent_name,
                    "skill_name": skill_name,
                    "title": title,
                }

                if isinstance(result, dict):
                    send_kwargs["body_structured_json"] = result
                elif isinstance(result, str):
                    send_kwargs["body_raw"] = result
                elif result is not None:
                    send_kwargs["body_raw"] = str(result)

                self.send(**send_kwargs)
                return result
            wrapper.__name__ = fn.__name__
            wrapper.__doc__ = fn.__doc__
            return wrapper
        return decorator

    # ------------------------------------------------------------------
    # Internal
    # ------------------------------------------------------------------

    def _post(self, payload: dict) -> dict:
        """Sign and POST the payload with retries."""
        payload_str = json.dumps(payload, separators=(",", ":"), sort_keys=True)
        unix_ts = str(int(time.time()))
        signature = compute_hmac(self.config.instance_secret, unix_ts, payload_str)

        headers = {
            "Content-Type": "application/json",
            "X-Signature": signature,
            "X-Timestamp": unix_ts,
            "X-Instance-Id": self.config.instance_id,
        }

        url = f"{self.config.backend_url}/ingest"
        last_error: Exception | None = None

        for attempt in range(1, self.config.retries + 1):
            try:
                resp = self._client.post(url, content=payload_str, headers=headers)
                if resp.status_code == 201:
                    logger.info("Event ingested: %s (attempt %d)", payload.get("title"), attempt)
                    return resp.json()

                logger.warning(
                    "Ingest failed (attempt %d/%d): %d %s",
                    attempt, self.config.retries, resp.status_code, resp.text,
                )
                last_error = IngestError(
                    f"Backend returned {resp.status_code}: {resp.text}"
                )
            except httpx.HTTPError as exc:
                logger.warning("HTTP error (attempt %d/%d): %s", attempt, self.config.retries, exc)
                last_error = IngestError(str(exc))

        raise last_error  # type: ignore[misc]

    def close(self) -> None:
        """Close the underlying HTTP client."""
        self._client.close()

    def __enter__(self) -> CompanionBridge:
        return self

    def __exit__(self, *exc: Any) -> None:
        self.close()
