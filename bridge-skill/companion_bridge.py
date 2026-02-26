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
import threading
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
        self.poll_interval: int = raw.get("poll_interval", 10)

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
    # Command Channel — poll for pending commands from backend
    # ------------------------------------------------------------------

    def poll_commands(self) -> list[dict]:
        """Poll the backend for pending commands. Returns list of command dicts.

        Each command has: id, command_type, payload, status, created_at, etc.
        """
        url = (
            f"{self.config.backend_url}/instances/"
            f"{self.config.instance_id}/commands/pending"
        )
        headers = self._hmac_headers("")

        try:
            resp = self._client.get(url, headers=headers)
            if resp.status_code == 200:
                data = resp.json()
                return data.get("commands", [])
            logger.warning("Poll commands failed: %d %s", resp.status_code, resp.text)
        except httpx.HTTPError as exc:
            logger.warning("Poll commands HTTP error: %s", exc)

        return []

    def acknowledge_command(
        self,
        command_id: str,
        status: str = "completed",
        result_message: str | None = None,
    ) -> dict | None:
        """Acknowledge a command back to the backend.

        Args:
            command_id: UUID of the command.
            status: One of "acknowledged", "completed", "failed".
            result_message: Optional message describing the result.
        """
        url = (
            f"{self.config.backend_url}/instances/"
            f"{self.config.instance_id}/commands/{command_id}/ack"
        )
        body = {"status": status}
        if result_message:
            body["result_message"] = result_message

        headers = self._hmac_headers("")
        headers["Content-Type"] = "application/json"

        try:
            resp = self._client.post(url, json=body, headers=headers)
            if resp.status_code == 200:
                logger.info("Command %s acknowledged as %s", command_id, status)
                return resp.json()
            logger.warning("Ack command failed: %d %s", resp.status_code, resp.text)
        except httpx.HTTPError as exc:
            logger.warning("Ack command HTTP error: %s", exc)

        return None

    def start_polling(
        self,
        interval: int = 10,
        handler: Callable[[dict], str | None] | None = None,
    ) -> threading.Event:
        """Start a background thread that polls for commands.

        Args:
            interval: Seconds between polls (default 10).
            handler: Callback ``fn(command) -> result_message``.
                Called for each pending command. If None, commands are
                logged and auto-acknowledged.

        Returns:
            A ``threading.Event`` — call ``.set()`` to stop the polling loop.
        """
        stop_event = threading.Event()

        def _default_handler(cmd: dict) -> str | None:
            cmd_type = cmd.get("command_type", "unknown")
            logger.info("Received command: %s (id=%s)", cmd_type, cmd.get("id"))
            return f"Auto-acknowledged: {cmd_type}"

        actual_handler = handler or _default_handler

        def _poll_loop() -> None:
            logger.info("Command polling started (interval=%ds)", interval)
            while not stop_event.is_set():
                try:
                    commands = self.poll_commands()
                    for cmd in commands:
                        cmd_id = cmd.get("id")
                        if not cmd_id:
                            continue
                        try:
                            result_msg = actual_handler(cmd)
                            self.acknowledge_command(
                                cmd_id, status="completed", result_message=result_msg,
                            )
                        except Exception as exc:
                            logger.error("Command handler error for %s: %s", cmd_id, exc)
                            self.acknowledge_command(
                                cmd_id, status="failed", result_message=str(exc),
                            )
                except Exception as exc:
                    logger.error("Poll loop error: %s", exc)

                stop_event.wait(interval)

            logger.info("Command polling stopped")

        thread = threading.Thread(target=_poll_loop, daemon=True, name="bridge-poll")
        thread.start()
        return stop_event

    # ------------------------------------------------------------------
    # Chat — send agent responses back to the conversation
    # ------------------------------------------------------------------

    def send_chat_response(
        self,
        *,
        thread_id: str,
        correlation_id: str,
        content: str | None = None,
        structured_json: dict[str, Any] | None = None,
        tool_usage: dict[str, Any] | None = None,
        skill_name: str | None = None,
    ) -> dict | None:
        """Send an agent response back to a chat thread.

        Args:
            thread_id: UUID of the chat thread.
            correlation_id: UUID correlating this response to the original command.
            content: Plain text response content.
            structured_json: Structured data for rich card rendering.
            tool_usage: Metadata about tools/skills used to produce the response.
            skill_name: Name of the skill that produced this response.
        """
        url = f"{self.config.backend_url}/chat/receive"
        body: dict[str, Any] = {
            "thread_id": thread_id,
            "correlation_id": correlation_id,
        }
        if content is not None:
            body["content"] = content
        if structured_json is not None:
            body["structured_json"] = structured_json
        if tool_usage is not None:
            body["tool_usage"] = tool_usage
        if skill_name is not None:
            body["skill_name"] = skill_name

        headers = self._hmac_headers("")
        headers["Content-Type"] = "application/json"

        try:
            resp = self._client.post(url, json=body, headers=headers)
            if resp.status_code == 201:
                logger.info(
                    "Chat response sent to thread %s (correlation=%s)",
                    thread_id, correlation_id,
                )
                return resp.json()
            logger.warning("Chat response failed: %d %s", resp.status_code, resp.text)
        except httpx.HTTPError as exc:
            logger.warning("Chat response HTTP error: %s", exc)

        return None

    def handle_chat_command(self, command: dict) -> str | None:
        """Handle a chat_message or run_skill command from the command channel.

        Subclass or override to implement actual agent/skill logic.
        Default implementation echoes the message back with routing info.

        Returns a result message string for command acknowledgement.
        """
        cmd_type = command.get("command_type", "")
        payload = command.get("payload", {})
        thread_id = payload.get("thread_id")
        correlation_id = command.get("correlation_id")

        if not thread_id or not correlation_id:
            return "Missing thread_id or correlation_id"

        if cmd_type == "chat_message":
            agent_name = payload.get("agent_name", "default")
            message = payload.get("message", "")
            self.send_chat_response(
                thread_id=thread_id,
                correlation_id=correlation_id,
                content=f"[{agent_name}] Received: {message}",
            )
            return f"Chat message handled by {agent_name}"

        if cmd_type == "run_skill":
            skill_name = payload.get("skill_name", "unknown")
            message = payload.get("message", "")
            self.send_chat_response(
                thread_id=thread_id,
                correlation_id=correlation_id,
                content=f"Skill '{skill_name}' executed for: {message}",
                skill_name=skill_name,
                tool_usage={"skill": skill_name, "status": "completed"},
            )
            return f"Skill {skill_name} executed"

        return f"Unknown chat command type: {cmd_type}"

    # ------------------------------------------------------------------
    # Approvals — request human approval for sensitive actions
    # ------------------------------------------------------------------

    # Actions that require approval
    SENSITIVE_ACTIONS = {
        "send_email",
        "exec_shell",
        "access_sensitive_path",
        "new_domain",
        "bulk_export",
    }

    def create_approval_request(
        self,
        *,
        skill_name: str,
        action: str,
        summary: str,
        risk_level: str = "warning",
        evidence: dict[str, Any] | None = None,
        thread_id: str | None = None,
        expires_in_seconds: int = 300,
    ) -> dict | None:
        """Create an approval request for a sensitive action.

        The backend will inject this into the chat thread as an approval card
        that the user can Allow/Deny from the mobile app.

        Args:
            skill_name: Name of the skill attempting the action.
            action: One of: send_email, exec_shell, access_sensitive_path,
                    new_domain, bulk_export.
            summary: Human-readable description of what the skill wants to do.
            risk_level: "warning" or "critical".
            evidence: Supporting evidence dict (e.g. recipient_count, path, domain).
            thread_id: Optional chat thread to display the approval card in.
            expires_in_seconds: How long until the request expires (default 5 min).
        """
        if action not in self.SENSITIVE_ACTIONS:
            raise ValueError(
                f"action must be one of {self.SENSITIVE_ACTIONS}, got {action!r}"
            )

        url = f"{self.config.backend_url}/approvals"
        body: dict[str, Any] = {
            "skill_name": skill_name,
            "action": action,
            "summary": summary,
            "risk_level": risk_level,
            "expires_in_seconds": expires_in_seconds,
        }
        if evidence is not None:
            body["evidence"] = evidence
        if thread_id is not None:
            body["thread_id"] = thread_id

        headers = self._hmac_headers("")
        headers["Content-Type"] = "application/json"

        try:
            resp = self._client.post(url, json=body, headers=headers)
            if resp.status_code == 201:
                data = resp.json()
                logger.info(
                    "Approval request created: %s (id=%s, action=%s)",
                    skill_name, data.get("id"), action,
                )
                return data
            logger.warning("Create approval failed: %d %s", resp.status_code, resp.text)
        except httpx.HTTPError as exc:
            logger.warning("Create approval HTTP error: %s", exc)

        return None

    def handle_approve_action(self, command: dict) -> str | None:
        """Handle an approve_action command received from the backend.

        Called when a user has decided on an approval request (allow/deny).
        Subclass and override to implement actual approval enforcement.
        Default logs the decision.

        Returns a result message for command acknowledgement.
        """
        payload = command.get("payload", {})
        approval_id = payload.get("approval_id")
        skill_name = payload.get("skill_name", "unknown")
        action = payload.get("action", "unknown")
        decision = payload.get("decision", "unknown")
        decided_by = payload.get("decided_by")

        logger.info(
            "Approval decision received: skill=%s action=%s decision=%s "
            "approval_id=%s decided_by=%s",
            skill_name, action, decision, approval_id, decided_by,
        )

        if decision == "deny":
            return f"Action '{action}' by skill '{skill_name}' was denied"
        if decision in ("allow_once", "allow_always"):
            return f"Action '{action}' by skill '{skill_name}' was approved ({decision})"

        return f"Unknown decision: {decision}"

    def requires_approval(self, action: str) -> bool:
        """Check if an action requires human approval."""
        return action in self.SENSITIVE_ACTIONS

    # ------------------------------------------------------------------
    # Internal
    # ------------------------------------------------------------------

    def _hmac_headers(self, payload: str = "") -> dict[str, str]:
        """Build HMAC authentication headers."""
        unix_ts = str(int(time.time()))
        signature = compute_hmac(self.config.instance_secret, unix_ts, payload)
        return {
            "X-Signature": signature,
            "X-Timestamp": unix_ts,
            "X-Instance-Id": self.config.instance_id,
        }

    def _post(self, payload: dict) -> dict:
        """Sign and POST the payload with retries."""
        payload_str = json.dumps(payload, separators=(",", ":"), sort_keys=True)
        headers = self._hmac_headers(payload_str)
        headers["Content-Type"] = "application/json"

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
