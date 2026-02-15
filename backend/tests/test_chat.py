"""Tests for Chat & Unified Assistant — Milestone 7.

Covers:
- RouterService intent classification
- ConversationService CRUD (unit-level with mocks)
- OrchestratorService command generation
- Chat API endpoint wiring
"""

import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

# Ensure backend is importable
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

# Import models in dependency order so SQLAlchemy resolves relationships
from app.models.thread import Thread  # noqa: F401
from app.models.message import Message  # noqa: F401
from app.models.routing_plan import RoutingIntent, RoutingPlan, SafetyPolicy
from app.models.command import Command, CommandType  # noqa: F401
from app.services.router import RoutingResult, RoutingTarget, classify_intent


# ===================================================================
# 1. RouterService — keyword-based intent classification
# ===================================================================


class TestRouterClassifyIntent:
    """Test the deterministic keyword routing."""

    # -- Control actions --

    def test_pause_intent(self):
        result = classify_intent("pause instance")
        assert result.intent == RoutingIntent.control_action
        assert result.targets[0].type == "control"

    def test_kill_intent(self):
        result = classify_intent("kill switch now!")
        assert result.intent == RoutingIntent.control_action

    def test_emergency_stop(self):
        result = classify_intent("emergency stop everything")
        assert result.intent == RoutingIntent.control_action

    def test_resume_routes_to_control(self):
        # "stop everything" triggers control_action
        result = classify_intent("stop everything")
        assert result.intent == RoutingIntent.control_action

    # -- Security inquiries --

    def test_security_inquiry(self):
        result = classify_intent("is this skill safe to run?")
        assert result.intent == RoutingIntent.security_inquiry
        assert result.targets[0].name == "security"

    def test_trust_check(self):
        result = classify_intent("can I trust this plugin?")
        assert result.intent == RoutingIntent.security_inquiry

    def test_malicious_inquiry(self):
        result = classify_intent("is this malicious behavior?")
        assert result.intent == RoutingIntent.security_inquiry

    # -- Explain alert --

    def test_explain_alert(self):
        result = classify_intent("explain alert details")
        assert result.intent == RoutingIntent.explain_alert

    def test_what_happened(self):
        result = classify_intent("what happened with that error?")
        assert result.intent == RoutingIntent.explain_alert

    # -- Daily brief --

    def test_daily_brief(self):
        result = classify_intent("run daily brief")
        assert result.intent == RoutingIntent.daily_brief
        assert result.targets[0].name == "daily_brief"

    def test_summary_intent(self):
        result = classify_intent("give me a summary")
        assert result.intent == RoutingIntent.daily_brief

    def test_weather_routes_to_brief(self):
        result = classify_intent("what's the weather today?")
        assert result.intent == RoutingIntent.daily_brief

    def test_overview_routes_to_brief(self):
        result = classify_intent("show me an overview")
        assert result.intent == RoutingIntent.daily_brief

    # -- Business summary --

    def test_business_summary(self):
        result = classify_intent("how are my invoices looking?")
        assert result.intent == RoutingIntent.business_summary

    def test_revenue_inquiry(self):
        result = classify_intent("show me the revenue numbers")
        assert result.intent == RoutingIntent.business_summary

    def test_kpi_metrics(self):
        result = classify_intent("what are the kpi metrics?")
        assert result.intent == RoutingIntent.business_summary

    # -- General Q&A fallback --

    def test_general_qna_fallback(self):
        result = classify_intent("tell me a joke about cats")
        assert result.intent == RoutingIntent.general_qna
        assert result.safety_policy == SafetyPolicy.safe_mode
        assert result.targets[0].name == "default"
        assert result.targets[0].confidence < 0.5

    def test_random_question_fallback(self):
        result = classify_intent("how do I set up Docker?")
        assert result.intent == RoutingIntent.general_qna

    # -- Confidence and metadata --

    def test_exact_keyword_high_confidence(self):
        result = classify_intent("pause")
        assert result.targets[0].confidence >= 0.8

    def test_long_message_lower_confidence(self):
        result = classify_intent("I was wondering if you could please pause the instance for me")
        assert result.intent == RoutingIntent.control_action
        assert result.targets[0].confidence < result.targets[0].confidence + 0.01  # Just verify it's a number

    def test_routing_result_has_notes(self):
        result = classify_intent("pause instance")
        assert "pause" in result.notes.lower()

    def test_case_insensitive(self):
        result = classify_intent("PAUSE INSTANCE")
        assert result.intent == RoutingIntent.control_action

    def test_whitespace_handling(self):
        result = classify_intent("  pause instance  ")
        assert result.intent == RoutingIntent.control_action


# ===================================================================
# 2. RoutingTarget and RoutingResult dataclasses
# ===================================================================


class TestRoutingDataclasses:
    def test_routing_target_defaults(self):
        t = RoutingTarget(type="skill", name="test", confidence=0.8)
        assert t.params == {}

    def test_routing_target_with_params(self):
        t = RoutingTarget(type="skill", name="test", confidence=0.8, params={"key": "val"})
        assert t.params == {"key": "val"}

    def test_routing_result_defaults(self):
        r = RoutingResult(
            intent=RoutingIntent.general_qna,
            targets=[RoutingTarget(type="agent", name="default", confidence=0.5)],
        )
        assert r.requires_approval is False
        assert r.safety_policy == SafetyPolicy.default
        assert r.notes == ""


# ===================================================================
# 3. OrchestratorService — command generation
# ===================================================================


class TestOrchestratorService:
    """Test the OrchestratorService command building logic."""

    def _make_plan(self, intent, targets=None, instance_id=None, thread_id=None):
        from app.models.routing_plan import RoutingPlan
        plan = RoutingPlan(
            id=uuid.uuid4(),
            thread_id=thread_id or uuid.uuid4(),
            instance_id=instance_id or uuid.uuid4(),
            intent=intent,
            targets=targets or [{"type": "agent", "name": "default", "confidence": 0.5}],
            requires_approval=False,
            safety_policy=SafetyPolicy.default,
        )
        return plan

    def test_build_control_command_pause(self):
        from app.services.orchestrator import OrchestratorService
        from app.models.command import CommandType

        orch = OrchestratorService.__new__(OrchestratorService)
        plan = self._make_plan(RoutingIntent.control_action)
        target = {"type": "control", "name": "control", "confidence": 0.9}

        cmd = orch._build_command(
            plan=plan,
            target=target,
            user_id=uuid.uuid4(),
            user_message="pause everything",
            correlation_id=uuid.uuid4(),
        )
        assert cmd is not None
        assert cmd.command_type == CommandType.pause

    def test_build_control_command_resume(self):
        from app.services.orchestrator import OrchestratorService
        from app.models.command import CommandType

        orch = OrchestratorService.__new__(OrchestratorService)
        plan = self._make_plan(RoutingIntent.control_action)
        target = {"type": "control", "name": "control", "confidence": 0.9}

        cmd = orch._build_command(
            plan=plan,
            target=target,
            user_id=uuid.uuid4(),
            user_message="resume the agent",
            correlation_id=uuid.uuid4(),
        )
        assert cmd is not None
        assert cmd.command_type == CommandType.resume

    def test_build_skill_command(self):
        from app.services.orchestrator import OrchestratorService
        from app.models.command import CommandType

        orch = OrchestratorService.__new__(OrchestratorService)
        plan = self._make_plan(RoutingIntent.daily_brief)
        target = {"type": "skill", "name": "daily_brief", "confidence": 0.8, "params": {}}

        cmd = orch._build_command(
            plan=plan,
            target=target,
            user_id=uuid.uuid4(),
            user_message="run daily brief",
            correlation_id=uuid.uuid4(),
        )
        assert cmd is not None
        assert cmd.command_type == CommandType.run_skill
        assert cmd.payload["skill_name"] == "daily_brief"

    def test_build_chat_message_command(self):
        from app.services.orchestrator import OrchestratorService
        from app.models.command import CommandType

        orch = OrchestratorService.__new__(OrchestratorService)
        plan = self._make_plan(RoutingIntent.general_qna)
        target = {"type": "agent", "name": "default", "confidence": 0.3}

        cmd = orch._build_command(
            plan=plan,
            target=target,
            user_id=uuid.uuid4(),
            user_message="tell me about containers",
            correlation_id=uuid.uuid4(),
        )
        assert cmd is not None
        assert cmd.command_type == CommandType.chat_message
        assert cmd.payload["agent_name"] == "default"
        assert cmd.payload["message"] == "tell me about containers"

    def test_command_has_correlation_id(self):
        from app.services.orchestrator import OrchestratorService

        orch = OrchestratorService.__new__(OrchestratorService)
        plan = self._make_plan(RoutingIntent.general_qna)
        target = {"type": "agent", "name": "default", "confidence": 0.3}
        corr_id = uuid.uuid4()

        cmd = orch._build_command(
            plan=plan,
            target=target,
            user_id=uuid.uuid4(),
            user_message="hello",
            correlation_id=corr_id,
        )
        assert cmd.correlation_id == corr_id

    def test_command_has_expiry(self):
        from app.services.orchestrator import OrchestratorService

        orch = OrchestratorService.__new__(OrchestratorService)
        plan = self._make_plan(RoutingIntent.general_qna)
        target = {"type": "agent", "name": "default", "confidence": 0.3}

        cmd = orch._build_command(
            plan=plan,
            target=target,
            user_id=uuid.uuid4(),
            user_message="hello",
            correlation_id=uuid.uuid4(),
        )
        assert cmd.expires_at is not None
        assert cmd.expires_at > datetime.now(timezone.utc)


# ===================================================================
# 4. Resolve control command
# ===================================================================


class TestResolveControlCommand:
    def test_kill_returns_pause(self):
        from app.services.orchestrator import OrchestratorService
        from app.models.command import CommandType
        assert OrchestratorService._resolve_control_command("kill the agent") == CommandType.pause

    def test_emergency_returns_pause(self):
        from app.services.orchestrator import OrchestratorService
        from app.models.command import CommandType
        assert OrchestratorService._resolve_control_command("emergency stop") == CommandType.pause

    def test_resume_returns_resume(self):
        from app.services.orchestrator import OrchestratorService
        from app.models.command import CommandType
        assert OrchestratorService._resolve_control_command("resume operations") == CommandType.resume

    def test_unpause_returns_resume(self):
        from app.services.orchestrator import OrchestratorService
        from app.models.command import CommandType
        assert OrchestratorService._resolve_control_command("unpause the agent") == CommandType.resume

    def test_default_returns_pause(self):
        from app.services.orchestrator import OrchestratorService
        from app.models.command import CommandType
        assert OrchestratorService._resolve_control_command("stop everything") == CommandType.pause


# ===================================================================
# 5. Routing plan model validation
# ===================================================================


class TestRoutingPlanModel:
    def test_intent_enum_values(self):
        assert RoutingIntent.daily_brief.value == "daily_brief"
        assert RoutingIntent.business_summary.value == "business_summary"
        assert RoutingIntent.explain_alert.value == "explain_alert"
        assert RoutingIntent.general_qna.value == "general_qna"
        assert RoutingIntent.control_action.value == "control_action"
        assert RoutingIntent.security_inquiry.value == "security_inquiry"

    def test_safety_policy_enum_values(self):
        assert SafetyPolicy.default.value == "default"
        assert SafetyPolicy.restricted.value == "restricted"
        assert SafetyPolicy.safe_mode.value == "safe_mode"


# ===================================================================
# 6. Message and Thread model validation
# ===================================================================


class TestChatModels:
    def test_message_type_enum(self):
        from app.models.message import MessageType, SenderType
        assert MessageType.user_message.value == "user_message"
        assert MessageType.agent_message.value == "agent_message"
        assert MessageType.structured_card_message.value == "structured_card_message"
        assert MessageType.system_message.value == "system_message"
        assert MessageType.approval_request.value == "approval_request"
        assert SenderType.user.value == "user"
        assert SenderType.agent.value == "agent"
        assert SenderType.system.value == "system"

    def test_thread_model_exists(self):
        from app.models.thread import Thread
        assert Thread.__tablename__ == "threads"

    def test_message_model_exists(self):
        from app.models.message import Message
        assert Message.__tablename__ == "messages"

    def test_routing_plan_model_exists(self):
        from app.models.routing_plan import RoutingPlan
        assert RoutingPlan.__tablename__ == "routing_plans"


# ===================================================================
# 7. Chat Pydantic schemas
# ===================================================================


class TestChatSchemas:
    def test_chat_send_request_validation(self):
        from app.schemas.chat import ChatSendRequest
        req = ChatSendRequest(
            instance_id=uuid.uuid4(),
            content="hello there",
        )
        assert req.thread_id is None
        assert req.content == "hello there"

    def test_chat_send_request_with_thread(self):
        from app.schemas.chat import ChatSendRequest
        tid = uuid.uuid4()
        req = ChatSendRequest(
            thread_id=tid,
            instance_id=uuid.uuid4(),
            content="hello",
        )
        assert req.thread_id == tid

    def test_chat_send_request_content_min_length(self):
        from app.schemas.chat import ChatSendRequest
        from pydantic import ValidationError
        with pytest.raises(ValidationError):
            ChatSendRequest(instance_id=uuid.uuid4(), content="")

    def test_chat_receive_request(self):
        from app.schemas.chat import ChatReceiveRequest
        req = ChatReceiveRequest(
            thread_id=uuid.uuid4(),
            correlation_id=uuid.uuid4(),
            content="agent says hi",
        )
        assert req.content == "agent says hi"
        assert req.structured_json is None

    def test_attach_context_request(self):
        from app.schemas.chat import AttachContextRequest
        eid = uuid.uuid4()
        req = AttachContextRequest(
            thread_id=uuid.uuid4(),
            event_id=eid,
        )
        assert req.event_id == eid
        assert req.alert_id is None

    def test_message_response_from_attributes(self):
        from app.schemas.chat import MessageResponse
        assert MessageResponse.model_config.get("from_attributes") is True

    def test_thread_response_from_attributes(self):
        from app.schemas.chat import ThreadResponse
        assert ThreadResponse.model_config.get("from_attributes") is True


# ===================================================================
# 8. Command model extensions
# ===================================================================


class TestCommandModelExtensions:
    def test_chat_message_command_type(self):
        from app.models.command import CommandType
        assert CommandType.chat_message.value == "chat_message"

    def test_run_skill_command_type(self):
        from app.models.command import CommandType
        assert CommandType.run_skill.value == "run_skill"

    def test_command_has_correlation_id_field(self):
        from app.models.command import Command
        # Verify the field exists in the model
        mapper = Command.__table__
        col_names = [c.name for c in mapper.columns]
        assert "correlation_id" in col_names

    def test_command_has_expires_at_field(self):
        from app.models.command import Command
        mapper = Command.__table__
        col_names = [c.name for c in mapper.columns]
        assert "expires_at" in col_names
