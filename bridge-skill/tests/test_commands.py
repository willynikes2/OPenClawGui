"""Tests for command channel — polling, acknowledgment, and background polling."""

import json
import textwrap
import threading
import time
from pathlib import Path
from unittest.mock import MagicMock

import httpx
import pytest

from companion_bridge import CompanionBridge, compute_hmac


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
        poll_interval: 1
    """))
    return cfg


@pytest.fixture()
def bridge(config_file: Path) -> CompanionBridge:
    return CompanionBridge(config_file)


class TestPollCommands:
    def test_returns_empty_on_200(self, bridge: CompanionBridge, monkeypatch):
        def fake_get(url, *, headers):
            resp = MagicMock()
            resp.status_code = 200
            resp.json.return_value = {"commands": []}
            return resp

        monkeypatch.setattr(bridge._client, "get", fake_get)

        commands = bridge.poll_commands()
        assert commands == []

    def test_returns_commands_on_200(self, bridge: CompanionBridge, monkeypatch):
        fake_cmd = {
            "id": "11111111-2222-3333-4444-555555555555",
            "command_type": "pause",
            "payload": None,
            "status": "pending",
        }

        def fake_get(url, *, headers):
            resp = MagicMock()
            resp.status_code = 200
            resp.json.return_value = {"commands": [fake_cmd]}
            return resp

        monkeypatch.setattr(bridge._client, "get", fake_get)

        commands = bridge.poll_commands()
        assert len(commands) == 1
        assert commands[0]["command_type"] == "pause"

    def test_hmac_headers_present(self, bridge: CompanionBridge, monkeypatch):
        captured = {}

        def fake_get(url, *, headers):
            captured["headers"] = headers
            resp = MagicMock()
            resp.status_code = 200
            resp.json.return_value = {"commands": []}
            return resp

        monkeypatch.setattr(bridge._client, "get", fake_get)
        bridge.poll_commands()

        assert "X-Signature" in captured["headers"]
        assert "X-Timestamp" in captured["headers"]
        assert captured["headers"]["X-Instance-Id"] == "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

    def test_hmac_verifies_with_empty_payload(self, bridge: CompanionBridge, monkeypatch):
        captured = {}

        def fake_get(url, *, headers):
            captured["headers"] = headers
            resp = MagicMock()
            resp.status_code = 200
            resp.json.return_value = {"commands": []}
            return resp

        monkeypatch.setattr(bridge._client, "get", fake_get)
        bridge.poll_commands()

        sig = captured["headers"]["X-Signature"]
        ts = captured["headers"]["X-Timestamp"]
        expected = compute_hmac("test-secret-123", ts, "")
        assert sig == expected

    def test_returns_empty_on_error(self, bridge: CompanionBridge, monkeypatch):
        def fake_get(url, *, headers):
            resp = MagicMock()
            resp.status_code = 401
            resp.text = "Unauthorized"
            return resp

        monkeypatch.setattr(bridge._client, "get", fake_get)

        commands = bridge.poll_commands()
        assert commands == []

    def test_returns_empty_on_connection_error(self, bridge: CompanionBridge, monkeypatch):
        def fake_get(url, *, headers):
            raise httpx.ConnectError("connection refused")

        monkeypatch.setattr(bridge._client, "get", fake_get)

        commands = bridge.poll_commands()
        assert commands == []

    def test_correct_url(self, bridge: CompanionBridge, monkeypatch):
        captured = {}

        def fake_get(url, *, headers):
            captured["url"] = url
            resp = MagicMock()
            resp.status_code = 200
            resp.json.return_value = {"commands": []}
            return resp

        monkeypatch.setattr(bridge._client, "get", fake_get)
        bridge.poll_commands()

        assert captured["url"] == (
            "http://localhost:8000/instances/"
            "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee/commands/pending"
        )


class TestAcknowledgeCommand:
    def test_sends_ack_post(self, bridge: CompanionBridge, monkeypatch):
        captured = {}

        def fake_post(url, *, json, headers):
            captured["url"] = url
            captured["json"] = json
            captured["headers"] = headers
            resp = MagicMock()
            resp.status_code = 200
            resp.json.return_value = {"id": "cmd-id", "status": "completed"}
            return resp

        monkeypatch.setattr(bridge._client, "post", fake_post)

        result = bridge.acknowledge_command(
            "cmd-id-123", status="completed", result_message="Done"
        )

        assert result is not None
        assert captured["json"]["status"] == "completed"
        assert captured["json"]["result_message"] == "Done"
        assert "cmd-id-123/ack" in captured["url"]

    def test_returns_none_on_error(self, bridge: CompanionBridge, monkeypatch):
        def fake_post(url, *, json, headers):
            resp = MagicMock()
            resp.status_code = 404
            resp.text = "Not found"
            return resp

        monkeypatch.setattr(bridge._client, "post", fake_post)

        result = bridge.acknowledge_command("bad-id")
        assert result is None


class TestStartPolling:
    def test_polling_calls_handler(self, bridge: CompanionBridge, monkeypatch):
        fake_cmd = {
            "id": "cmd-111",
            "command_type": "test_run",
            "payload": None,
            "status": "pending",
        }

        call_count = 0
        handled_commands = []

        def fake_get(url, *, headers):
            nonlocal call_count
            call_count += 1
            resp = MagicMock()
            resp.status_code = 200
            # Return command only on first poll
            resp.json.return_value = {"commands": [fake_cmd] if call_count == 1 else []}
            return resp

        def fake_post(url, *, json, headers):
            resp = MagicMock()
            resp.status_code = 200
            resp.json.return_value = {}
            return resp

        monkeypatch.setattr(bridge._client, "get", fake_get)
        monkeypatch.setattr(bridge._client, "post", fake_post)

        def handler(cmd):
            handled_commands.append(cmd)
            return "handled"

        stop = bridge.start_polling(interval=1, handler=handler)

        # Wait for at least one poll cycle
        time.sleep(2.5)
        stop.set()
        time.sleep(0.5)

        assert len(handled_commands) == 1
        assert handled_commands[0]["command_type"] == "test_run"

    def test_stop_event_stops_polling(self, bridge: CompanionBridge, monkeypatch):
        poll_count = 0

        def fake_get(url, *, headers):
            nonlocal poll_count
            poll_count += 1
            resp = MagicMock()
            resp.status_code = 200
            resp.json.return_value = {"commands": []}
            return resp

        monkeypatch.setattr(bridge._client, "get", fake_get)

        stop = bridge.start_polling(interval=1)
        time.sleep(1.5)
        stop.set()
        count_at_stop = poll_count
        time.sleep(2)

        # Should not have polled much more after stop
        assert poll_count <= count_at_stop + 1

    def test_handler_error_acks_as_failed(self, bridge: CompanionBridge, monkeypatch):
        fake_cmd = {"id": "cmd-err", "command_type": "pause", "payload": None, "status": "pending"}
        ack_statuses = []

        call_count = 0

        def fake_get(url, *, headers):
            nonlocal call_count
            call_count += 1
            resp = MagicMock()
            resp.status_code = 200
            resp.json.return_value = {"commands": [fake_cmd] if call_count == 1 else []}
            return resp

        def fake_post(url, *, json, headers):
            ack_statuses.append(json.get("status"))
            resp = MagicMock()
            resp.status_code = 200
            resp.json.return_value = {}
            return resp

        monkeypatch.setattr(bridge._client, "get", fake_get)
        monkeypatch.setattr(bridge._client, "post", fake_post)

        def bad_handler(cmd):
            raise RuntimeError("Handler crashed")

        stop = bridge.start_polling(interval=1, handler=bad_handler)
        time.sleep(2.5)
        stop.set()

        assert "failed" in ack_statuses


class TestPollInterval:
    def test_config_loads_poll_interval(self, config_file: Path):
        b = CompanionBridge(config_file)
        assert b.config.poll_interval == 1
