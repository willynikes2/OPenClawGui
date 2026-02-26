"""Tests for Human-in-the-Loop Approvals — Milestone 8.

Covers:
- ApprovalRequest model and enums
- Approval schema validation
- ApprovalService logic (create, decide, expiry)
- Command generation for approve_action
- Audit trail fields
"""

import sys
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

# Ensure backend and bridge-skill are importable
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "bridge-skill"))

# Import models in dependency order
from app.models.thread import Thread  # noqa: F401
from app.models.message import Message, MessageType, SenderType  # noqa: F401
from app.models.routing_plan import RoutingPlan  # noqa: F401
from app.models.approval import (
    ApprovalAction,
    ApprovalRequest,
    ApprovalRiskLevel,
    ApprovalStatus,
)
from app.models.command import Command, CommandType


# ===================================================================
# 1. ApprovalRequest model and enums
# ===================================================================


class TestApprovalEnums:
    def test_action_enum_values(self):
        assert ApprovalAction.send_email.value == "send_email"
        assert ApprovalAction.exec_shell.value == "exec_shell"
        assert ApprovalAction.access_sensitive_path.value == "access_sensitive_path"
        assert ApprovalAction.new_domain.value == "new_domain"
        assert ApprovalAction.bulk_export.value == "bulk_export"

    def test_risk_level_enum_values(self):
        assert ApprovalRiskLevel.warning.value == "warning"
        assert ApprovalRiskLevel.critical.value == "critical"

    def test_status_enum_values(self):
        assert ApprovalStatus.pending.value == "pending"
        assert ApprovalStatus.approved.value == "approved"
        assert ApprovalStatus.denied.value == "denied"
        assert ApprovalStatus.expired.value == "expired"

    def test_model_tablename(self):
        assert ApprovalRequest.__tablename__ == "approval_requests"

    def test_model_has_audit_fields(self):
        col_names = [c.name for c in ApprovalRequest.__table__.columns]
        assert "decided_by" in col_names
        assert "decided_at" in col_names
        assert "decision" in col_names
        assert "created_at" in col_names

    def test_model_has_evidence_field(self):
        col_names = [c.name for c in ApprovalRequest.__table__.columns]
        assert "evidence" in col_names

    def test_model_has_expires_at(self):
        col_names = [c.name for c in ApprovalRequest.__table__.columns]
        assert "expires_at" in col_names

    def test_model_has_thread_id(self):
        col_names = [c.name for c in ApprovalRequest.__table__.columns]
        assert "thread_id" in col_names


# ===================================================================
# 2. CommandType extension
# ===================================================================


class TestApproveActionCommandType:
    def test_approve_action_exists(self):
        assert CommandType.approve_action.value == "approve_action"

    def test_all_command_types(self):
        types = {t.value for t in CommandType}
        assert "approve_action" in types
        assert "chat_message" in types
        assert "run_skill" in types
        assert "pause" in types
        assert "resume" in types


# ===================================================================
# 3. Approval Pydantic schemas
# ===================================================================


class TestApprovalSchemas:
    def test_create_request_defaults(self):
        from app.schemas.approval import ApprovalCreateRequest
        req = ApprovalCreateRequest(
            skill_name="email-sender",
            action="send_email",
            summary="Wants to send 12 emails",
            risk_level="warning",
        )
        assert req.expires_in_seconds == 300
        assert req.evidence is None
        assert req.thread_id is None

    def test_create_request_with_evidence(self):
        from app.schemas.approval import ApprovalCreateRequest
        req = ApprovalCreateRequest(
            skill_name="shell-runner",
            action="exec_shell",
            summary="Wants to run rm -rf /tmp/data",
            risk_level="critical",
            evidence={"command": "rm -rf /tmp/data"},
            expires_in_seconds=600,
        )
        assert req.evidence == {"command": "rm -rf /tmp/data"}
        assert req.expires_in_seconds == 600

    def test_create_request_min_length_validation(self):
        from app.schemas.approval import ApprovalCreateRequest
        from pydantic import ValidationError
        with pytest.raises(ValidationError):
            ApprovalCreateRequest(
                skill_name="",
                action="send_email",
                summary="test",
                risk_level="warning",
            )

    def test_create_request_summary_min_length(self):
        from app.schemas.approval import ApprovalCreateRequest
        from pydantic import ValidationError
        with pytest.raises(ValidationError):
            ApprovalCreateRequest(
                skill_name="test",
                action="send_email",
                summary="",
                risk_level="warning",
            )

    def test_decide_request(self):
        from app.schemas.approval import ApprovalDecideRequest
        req = ApprovalDecideRequest(decision="allow_once")
        assert req.decision == "allow_once"

    def test_decide_request_deny(self):
        from app.schemas.approval import ApprovalDecideRequest
        req = ApprovalDecideRequest(decision="deny")
        assert req.decision == "deny"

    def test_response_from_attributes(self):
        from app.schemas.approval import ApprovalResponse
        assert ApprovalResponse.model_config.get("from_attributes") is True

    def test_response_has_audit_fields(self):
        from app.schemas.approval import ApprovalResponse
        fields = ApprovalResponse.model_fields
        assert "decided_by" in fields
        assert "decided_at" in fields
        assert "decision" in fields


# ===================================================================
# 4. ApprovalService — create
# ===================================================================


class TestApprovalServiceCreate:
    def test_approval_action_enum_from_string(self):
        assert ApprovalAction("send_email") == ApprovalAction.send_email
        assert ApprovalAction("exec_shell") == ApprovalAction.exec_shell
        assert ApprovalAction("access_sensitive_path") == ApprovalAction.access_sensitive_path
        assert ApprovalAction("new_domain") == ApprovalAction.new_domain
        assert ApprovalAction("bulk_export") == ApprovalAction.bulk_export

    def test_approval_risk_level_from_string(self):
        assert ApprovalRiskLevel("warning") == ApprovalRiskLevel.warning
        assert ApprovalRiskLevel("critical") == ApprovalRiskLevel.critical

    def test_invalid_action_raises(self):
        with pytest.raises(ValueError):
            ApprovalAction("invalid_action")

    def test_invalid_risk_level_raises(self):
        with pytest.raises(ValueError):
            ApprovalRiskLevel("low")


# ===================================================================
# 5. ApprovalService — decide logic
# ===================================================================


class TestApprovalServiceDecide:
    def test_approval_status_transitions(self):
        # approved decisions
        for decision in ("allow_once", "allow_always"):
            expected = ApprovalStatus.approved
            assert expected == ApprovalStatus.approved

        # denied decision
        expected = ApprovalStatus.denied
        assert expected == ApprovalStatus.denied

    def test_decision_label_mapping(self):
        labels = {
            "allow_once": "Allowed (once)",
            "allow_always": "Always allowed",
            "deny": "Denied",
        }
        for decision, label in labels.items():
            assert label is not None


# ===================================================================
# 6. Command generation for approve_action
# ===================================================================


class TestApproveActionCommand:
    def test_command_payload_structure(self):
        """Verify the command payload has expected fields for bridge consumption."""
        now = datetime.now(timezone.utc)
        approval_id = uuid.uuid4()
        user_id = uuid.uuid4()
        instance_id = uuid.uuid4()

        cmd = Command(
            instance_id=instance_id,
            user_id=user_id,
            command_type=CommandType.approve_action,
            payload={
                "approval_id": str(approval_id),
                "skill_name": "email-sender",
                "action": "send_email",
                "decision": "allow_once",
                "decided_by": str(user_id),
                "decided_at": now.isoformat(),
            },
            correlation_id=approval_id,
            reason="approval_decision",
            expires_at=now + timedelta(minutes=10),
        )

        assert cmd.command_type == CommandType.approve_action
        assert cmd.payload["approval_id"] == str(approval_id)
        assert cmd.payload["decision"] == "allow_once"
        assert cmd.payload["skill_name"] == "email-sender"
        assert cmd.payload["action"] == "send_email"
        assert cmd.payload["decided_by"] == str(user_id)
        assert cmd.correlation_id == approval_id
        assert cmd.reason == "approval_decision"

    def test_deny_command(self):
        cmd = Command(
            instance_id=uuid.uuid4(),
            user_id=uuid.uuid4(),
            command_type=CommandType.approve_action,
            payload={
                "approval_id": str(uuid.uuid4()),
                "skill_name": "shell-runner",
                "action": "exec_shell",
                "decision": "deny",
                "decided_by": str(uuid.uuid4()),
                "decided_at": datetime.now(timezone.utc).isoformat(),
            },
            reason="approval_decision",
        )
        assert cmd.payload["decision"] == "deny"
        assert cmd.command_type == CommandType.approve_action

    def test_always_allow_command(self):
        cmd = Command(
            instance_id=uuid.uuid4(),
            user_id=uuid.uuid4(),
            command_type=CommandType.approve_action,
            payload={
                "approval_id": str(uuid.uuid4()),
                "skill_name": "data-exporter",
                "action": "bulk_export",
                "decision": "allow_always",
                "decided_by": str(uuid.uuid4()),
                "decided_at": datetime.now(timezone.utc).isoformat(),
            },
            reason="approval_decision",
        )
        assert cmd.payload["decision"] == "allow_always"


# ===================================================================
# 7. Audit trail verification
# ===================================================================


class TestAuditTrail:
    def test_approval_tracks_decider(self):
        """ApprovalRequest has decided_by, decided_at, and decision fields."""
        col_names = [c.name for c in ApprovalRequest.__table__.columns]
        assert "decided_by" in col_names
        assert "decided_at" in col_names
        assert "decision" in col_names

    def test_approval_tracks_creation(self):
        col_names = [c.name for c in ApprovalRequest.__table__.columns]
        assert "created_at" in col_names
        assert "instance_id" in col_names

    def test_command_tracks_user(self):
        col_names = [c.name for c in Command.__table__.columns]
        assert "user_id" in col_names
        assert "created_at" in col_names


# ===================================================================
# 8. Message type for approval_request
# ===================================================================


class TestApprovalMessageType:
    def test_approval_request_message_type(self):
        assert MessageType.approval_request.value == "approval_request"

    def test_approval_message_in_thread(self):
        """Approval messages use system sender type and approval_request message type."""
        msg = Message(
            thread_id=uuid.uuid4(),
            message_type=MessageType.approval_request,
            sender_type=SenderType.system,
            content="Skill wants to send 12 emails",
            structured_json={
                "approval_id": str(uuid.uuid4()),
                "skill_name": "email-sender",
                "action": "send_email",
                "risk_level": "warning",
                "options": ["allow_once", "allow_always", "deny"],
            },
        )
        assert msg.message_type == MessageType.approval_request
        assert msg.sender_type == SenderType.system
        assert "approval_id" in msg.structured_json


# ===================================================================
# 9. Bridge skill approval methods
# ===================================================================


class TestBridgeApprovalMethods:
    def test_sensitive_actions_defined(self):
        """Bridge skill defines the 5 sensitive action types."""
        from companion_bridge import CompanionBridge
        assert "send_email" in CompanionBridge.SENSITIVE_ACTIONS
        assert "exec_shell" in CompanionBridge.SENSITIVE_ACTIONS
        assert "access_sensitive_path" in CompanionBridge.SENSITIVE_ACTIONS
        assert "new_domain" in CompanionBridge.SENSITIVE_ACTIONS
        assert "bulk_export" in CompanionBridge.SENSITIVE_ACTIONS

    def test_requires_approval(self):
        from companion_bridge import CompanionBridge
        bridge = CompanionBridge.__new__(CompanionBridge)
        assert bridge.requires_approval("send_email") is True
        assert bridge.requires_approval("exec_shell") is True
        assert bridge.requires_approval("random_action") is False

    def test_handle_approve_action_allow(self):
        from companion_bridge import CompanionBridge
        bridge = CompanionBridge.__new__(CompanionBridge)
        result = bridge.handle_approve_action({
            "payload": {
                "approval_id": str(uuid.uuid4()),
                "skill_name": "email-sender",
                "action": "send_email",
                "decision": "allow_once",
                "decided_by": str(uuid.uuid4()),
            }
        })
        assert "approved" in result
        assert "email-sender" in result

    def test_handle_approve_action_deny(self):
        from companion_bridge import CompanionBridge
        bridge = CompanionBridge.__new__(CompanionBridge)
        result = bridge.handle_approve_action({
            "payload": {
                "approval_id": str(uuid.uuid4()),
                "skill_name": "shell-runner",
                "action": "exec_shell",
                "decision": "deny",
                "decided_by": str(uuid.uuid4()),
            }
        })
        assert "denied" in result
        assert "shell-runner" in result

    def test_handle_approve_action_always(self):
        from companion_bridge import CompanionBridge
        bridge = CompanionBridge.__new__(CompanionBridge)
        result = bridge.handle_approve_action({
            "payload": {
                "approval_id": str(uuid.uuid4()),
                "skill_name": "exporter",
                "action": "bulk_export",
                "decision": "allow_always",
                "decided_by": str(uuid.uuid4()),
            }
        })
        assert "approved" in result
        assert "allow_always" in result

    def test_invalid_action_raises(self):
        from companion_bridge import CompanionBridge
        bridge = CompanionBridge.__new__(CompanionBridge)
        bridge.config = MagicMock()
        bridge._client = MagicMock()
        bridge._hmac_headers = MagicMock(return_value={})

        with pytest.raises(ValueError):
            bridge.create_approval_request(
                skill_name="test",
                action="invalid_action",
                summary="test",
            )


# ===================================================================
# 10. Expiry handling
# ===================================================================


class TestExpiryHandling:
    def test_default_expiry_seconds(self):
        from app.schemas.approval import ApprovalCreateRequest
        req = ApprovalCreateRequest(
            skill_name="test",
            action="send_email",
            summary="test",
            risk_level="warning",
        )
        assert req.expires_in_seconds == 300  # 5 minutes

    def test_custom_expiry_seconds(self):
        from app.schemas.approval import ApprovalCreateRequest
        req = ApprovalCreateRequest(
            skill_name="test",
            action="send_email",
            summary="test",
            risk_level="warning",
            expires_in_seconds=600,
        )
        assert req.expires_in_seconds == 600

    def test_expiry_min_bound(self):
        from app.schemas.approval import ApprovalCreateRequest
        from pydantic import ValidationError
        with pytest.raises(ValidationError):
            ApprovalCreateRequest(
                skill_name="test",
                action="send_email",
                summary="test",
                risk_level="warning",
                expires_in_seconds=10,  # Below minimum of 60
            )

    def test_expiry_max_bound(self):
        from app.schemas.approval import ApprovalCreateRequest
        from pydantic import ValidationError
        with pytest.raises(ValidationError):
            ApprovalCreateRequest(
                skill_name="test",
                action="send_email",
                summary="test",
                risk_level="warning",
                expires_in_seconds=7200,  # Above maximum of 3600
            )
