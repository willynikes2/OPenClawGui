"""Tests for CompanionBridge — config loading, event formatting, and HTTP posting."""

import json
import textwrap
from pathlib import Path
from unittest.mock import MagicMock

import httpx
import pytest

from companion_bridge import CompanionBridge, ConfigError, IngestError, compute_hmac


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture()
def config_file(tmp_path: Path) -> Path:
    cfg = tmp_path / "config.yaml"
    cfg.write_text(textwrap.dedent("""\
        backend_url: "http://localhost:8000"
        instance_id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        instance_secret: "test-secret-123"
        default_source_type: "skill"
        timeout: 5
        retries: 1
    """))
    return cfg


@pytest.fixture()
def bridge(config_file: Path) -> CompanionBridge:
    return CompanionBridge(config_file)


# ---------------------------------------------------------------------------
# Config tests
# ---------------------------------------------------------------------------

class TestConfig:
    def test_loads_valid_config(self, config_file: Path):
        b = CompanionBridge(config_file)
        assert b.config.backend_url == "http://localhost:8000"
        assert b.config.instance_id == "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        assert b.config.instance_secret == "test-secret-123"
        assert b.config.retries == 1

    def test_missing_file_raises(self, tmp_path: Path):
        with pytest.raises(ConfigError, match="not found"):
            CompanionBridge(tmp_path / "nope.yaml")

    def test_missing_backend_url_raises(self, tmp_path: Path):
        cfg = tmp_path / "bad.yaml"
        cfg.write_text('instance_id: "x"\ninstance_secret: "y"\n')
        with pytest.raises(ConfigError, match="backend_url"):
            CompanionBridge(cfg)

    def test_missing_instance_id_raises(self, tmp_path: Path):
        cfg = tmp_path / "bad.yaml"
        cfg.write_text('backend_url: "http://x"\ninstance_secret: "y"\n')
        with pytest.raises(ConfigError, match="instance_id"):
            CompanionBridge(cfg)

    def test_missing_secret_raises(self, tmp_path: Path):
        cfg = tmp_path / "bad.yaml"
        cfg.write_text('backend_url: "http://x"\ninstance_id: "y"\n')
        with pytest.raises(ConfigError, match="instance_secret"):
            CompanionBridge(cfg)

    def test_trailing_slash_stripped(self, tmp_path: Path):
        cfg = tmp_path / "cfg.yaml"
        cfg.write_text(textwrap.dedent("""\
            backend_url: "http://localhost:8000/"
            instance_id: "x"
            instance_secret: "y"
        """))
        b = CompanionBridge(cfg)
        assert b.config.backend_url == "http://localhost:8000"


# ---------------------------------------------------------------------------
# Event formatting / validation
# ---------------------------------------------------------------------------

class TestSend:
    def test_invalid_severity_raises(self, bridge: CompanionBridge):
        with pytest.raises(ValueError, match="severity"):
            bridge.send(agent_name="a", skill_name="s", title="t", severity="unknown")

    def test_invalid_source_type_raises(self, bridge: CompanionBridge):
        with pytest.raises(ValueError, match="source_type"):
            bridge.send(agent_name="a", skill_name="s", title="t", source_type="bad")

    def test_post_called_with_correct_headers(self, bridge: CompanionBridge, monkeypatch):
        """Verify headers contain X-Signature, X-Timestamp, X-Instance-Id."""
        captured = {}

        def fake_post(url, *, content, headers):
            captured["url"] = url
            captured["headers"] = headers
            captured["content"] = content
            resp = MagicMock()
            resp.status_code = 201
            resp.json.return_value = {"id": "fake"}
            return resp

        monkeypatch.setattr(bridge._client, "post", fake_post)

        bridge.send(agent_name="bot", skill_name="ping", title="hello")

        assert captured["url"] == "http://localhost:8000/ingest"
        assert "X-Signature" in captured["headers"]
        assert "X-Timestamp" in captured["headers"]
        assert captured["headers"]["X-Instance-Id"] == "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        assert captured["headers"]["Content-Type"] == "application/json"

    def test_hmac_matches_payload(self, bridge: CompanionBridge, monkeypatch):
        """Verify the signature matches compute_hmac(secret, timestamp, payload)."""
        captured = {}

        def fake_post(url, *, content, headers):
            captured["headers"] = headers
            captured["content"] = content
            resp = MagicMock()
            resp.status_code = 201
            resp.json.return_value = {}
            return resp

        monkeypatch.setattr(bridge._client, "post", fake_post)

        bridge.send(agent_name="bot", skill_name="ping", title="test")

        sig = captured["headers"]["X-Signature"]
        ts = captured["headers"]["X-Timestamp"]
        payload = captured["content"]

        expected = compute_hmac("test-secret-123", ts, payload)
        assert sig == expected

    def test_payload_contains_required_fields(self, bridge: CompanionBridge, monkeypatch):
        captured = {}

        def fake_post(url, *, content, headers):
            captured["content"] = content
            resp = MagicMock()
            resp.status_code = 201
            resp.json.return_value = {}
            return resp

        monkeypatch.setattr(bridge._client, "post", fake_post)

        bridge.send(
            agent_name="bot",
            skill_name="ping",
            title="test event",
            body_raw="raw text",
            tags=["a", "b"],
            severity="warn",
        )

        body = json.loads(captured["content"])
        assert body["agent_name"] == "bot"
        assert body["skill_name"] == "ping"
        assert body["title"] == "test event"
        assert body["body_raw"] == "raw text"
        assert body["tags"] == ["a", "b"]
        assert body["severity"] == "warn"
        assert body["source_type"] == "skill"
        assert "timestamp" in body

    def test_optional_fields_omitted_when_none(self, bridge: CompanionBridge, monkeypatch):
        captured = {}

        def fake_post(url, *, content, headers):
            captured["content"] = content
            resp = MagicMock()
            resp.status_code = 201
            resp.json.return_value = {}
            return resp

        monkeypatch.setattr(bridge._client, "post", fake_post)

        bridge.send(agent_name="bot", skill_name="ping", title="minimal")

        body = json.loads(captured["content"])
        assert "body_raw" not in body
        assert "body_structured_json" not in body
        assert "tags" not in body

    def test_backend_error_raises_ingest_error(self, bridge: CompanionBridge, monkeypatch):
        def fake_post(url, *, content, headers):
            resp = MagicMock()
            resp.status_code = 401
            resp.text = "Invalid HMAC"
            return resp

        monkeypatch.setattr(bridge._client, "post", fake_post)

        with pytest.raises(IngestError, match="401"):
            bridge.send(agent_name="a", skill_name="s", title="t")

    def test_http_error_raises_ingest_error(self, bridge: CompanionBridge, monkeypatch):
        def fake_post(url, *, content, headers):
            raise httpx.ConnectError("connection refused")

        monkeypatch.setattr(bridge._client, "post", fake_post)

        with pytest.raises(IngestError, match="connection refused"):
            bridge.send(agent_name="a", skill_name="s", title="t")


# ---------------------------------------------------------------------------
# Decorator
# ---------------------------------------------------------------------------

class TestSkillDecorator:
    def test_decorator_sends_dict_as_structured(self, bridge: CompanionBridge, monkeypatch):
        captured = {}

        def fake_post(url, *, content, headers):
            captured["content"] = content
            resp = MagicMock()
            resp.status_code = 201
            resp.json.return_value = {}
            return resp

        monkeypatch.setattr(bridge._client, "post", fake_post)

        @bridge.skill("scraper", agent_name="test-agent")
        def my_scraper(url: str) -> dict:
            return {"url": url, "items": 5}

        result = my_scraper("https://example.com")

        assert result == {"url": "https://example.com", "items": 5}
        body = json.loads(captured["content"])
        assert body["skill_name"] == "scraper"
        assert body["agent_name"] == "test-agent"
        assert body["body_structured_json"] == {"url": "https://example.com", "items": 5}

    def test_decorator_sends_str_as_raw(self, bridge: CompanionBridge, monkeypatch):
        captured = {}

        def fake_post(url, *, content, headers):
            captured["content"] = content
            resp = MagicMock()
            resp.status_code = 201
            resp.json.return_value = {}
            return resp

        monkeypatch.setattr(bridge._client, "post", fake_post)

        @bridge.skill("logger")
        def log_msg() -> str:
            return "All clear"

        log_msg()

        body = json.loads(captured["content"])
        assert body["body_raw"] == "All clear"
        assert "body_structured_json" not in body

    def test_decorator_preserves_function_name(self, bridge: CompanionBridge):
        @bridge.skill("test")
        def my_function():
            pass

        assert my_function.__name__ == "my_function"


# ---------------------------------------------------------------------------
# Batch
# ---------------------------------------------------------------------------

class TestSendBatch:
    def test_sends_multiple_events(self, bridge: CompanionBridge, monkeypatch):
        call_count = 0

        def fake_post(url, *, content, headers):
            nonlocal call_count
            call_count += 1
            resp = MagicMock()
            resp.status_code = 201
            resp.json.return_value = {"id": str(call_count)}
            return resp

        monkeypatch.setattr(bridge._client, "post", fake_post)

        results = bridge.send_batch([
            {"agent_name": "a", "skill_name": "s1", "title": "event 1"},
            {"agent_name": "a", "skill_name": "s2", "title": "event 2"},
        ])

        assert len(results) == 2
        assert call_count == 2


# ---------------------------------------------------------------------------
# Context manager
# ---------------------------------------------------------------------------

class TestContextManager:
    def test_closes_client(self, bridge: CompanionBridge, monkeypatch):
        closed = False

        def fake_close():
            nonlocal closed
            closed = True

        monkeypatch.setattr(bridge._client, "close", fake_close)

        with bridge:
            pass

        assert closed
