"""RouterService — deterministic keyword-based intent classification (MVP).

Routes user messages to the appropriate agent/skill based on keyword matching.
No LLM required for MVP; simple classifier rules per spec.
"""

from __future__ import annotations

import re
import uuid
from dataclasses import dataclass, field

from app.models.routing_plan import RoutingIntent, SafetyPolicy


@dataclass
class RoutingTarget:
    type: str  # "skill" or "agent"
    name: str
    confidence: float
    params: dict = field(default_factory=dict)


@dataclass
class RoutingResult:
    intent: RoutingIntent
    targets: list[RoutingTarget]
    requires_approval: bool = False
    safety_policy: SafetyPolicy = SafetyPolicy.default
    notes: str = ""


# Keyword → intent mapping. Order matters: first match wins.
_KEYWORD_RULES: list[tuple[list[str], RoutingIntent, str, SafetyPolicy]] = [
    # Control actions — must match before general keywords
    (
        ["pause instance", "pause", "stop instance", "stop everything", "kill", "kill switch", "emergency stop"],
        RoutingIntent.control_action,
        "control",
        SafetyPolicy.default,
    ),
    # Security inquiries
    (
        ["is this skill safe", "is it safe", "trust", "malicious", "suspicious", "security status",
         "skill trust", "is this trusted", "check security"],
        RoutingIntent.security_inquiry,
        "security",
        SafetyPolicy.default,
    ),
    # Explain alert
    (
        ["why alert", "explain alert", "what happened", "what triggered", "explain this",
         "why was this flagged", "alert detail", "what does this alert mean"],
        RoutingIntent.explain_alert,
        "explain_alert",
        SafetyPolicy.default,
    ),
    # Daily brief / summary
    (
        ["summary", "brief", "daily brief", "daily summary", "run daily brief",
         "weather", "calendar", "morning brief", "overview", "what happened today",
         "today's summary", "recap"],
        RoutingIntent.daily_brief,
        "daily_brief",
        SafetyPolicy.default,
    ),
    # Business summary
    (
        ["money", "revenue", "invoices", "sales", "business", "profit", "earnings",
         "financial", "budget", "expenses", "business summary", "kpi", "metrics"],
        RoutingIntent.business_summary,
        "business_summary",
        SafetyPolicy.default,
    ),
]


def classify_intent(message: str) -> RoutingResult:
    """Classify a user message into a routing intent using keyword matching.

    Returns a RoutingResult with the matched intent, target skill/agent,
    confidence score, and safety policy.
    """
    lower = message.lower().strip()

    for keywords, intent, skill_name, policy in _KEYWORD_RULES:
        for keyword in keywords:
            if _keyword_match(lower, keyword):
                confidence = _compute_confidence(lower, keyword)
                target = RoutingTarget(
                    type="skill" if intent != RoutingIntent.control_action else "control",
                    name=skill_name,
                    confidence=confidence,
                )
                return RoutingResult(
                    intent=intent,
                    targets=[target],
                    safety_policy=policy,
                    notes=f"Matched keyword '{keyword}' → {intent.value}",
                )

    # Fallback: general Q&A with safe mode
    return RoutingResult(
        intent=RoutingIntent.general_qna,
        targets=[RoutingTarget(type="agent", name="default", confidence=0.3)],
        safety_policy=SafetyPolicy.safe_mode,
        notes="No keyword match; routing to default agent in safe mode.",
    )


def _keyword_match(text: str, keyword: str) -> bool:
    """Check if keyword appears in text as a word or phrase boundary."""
    pattern = r"(?:^|\b)" + re.escape(keyword) + r"(?:\b|$)"
    return bool(re.search(pattern, text))


def _compute_confidence(text: str, keyword: str) -> float:
    """Simple confidence heuristic based on keyword coverage of the message."""
    keyword_words = len(keyword.split())
    text_words = max(len(text.split()), 1)
    ratio = keyword_words / text_words
    # More specific matches get higher confidence
    base = 0.6
    return min(base + ratio * 0.4, 0.95)
