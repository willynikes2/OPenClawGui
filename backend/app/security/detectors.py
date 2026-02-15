"""Security detectors — analyze ingested events and produce alerts.

Each detector receives the event data (pre-PII-scrubbing body for analysis,
post-scrubbing for storage) and returns zero or more ``DetectorResult``s.

The 5 MVP detectors:
1. NewDomainDetector — flags first-seen domains in event data
2. ShellSpawnedDetector — flags shell process invocations
3. SensitivePathDetector — flags access to SSH keys, wallets, browser profiles
4. HighFrequencyLoopDetector — flags rapid repeated actions
5. SecretPatternDetector — flags API keys, JWTs, secrets in output
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any

from app.models.event import Severity


@dataclass
class DetectorResult:
    """Output of a single detector match."""

    detector_name: str
    severity: Severity
    explanation: str
    recommended_action: str
    evidence: dict[str, Any] = field(default_factory=dict)


# ---------------------------------------------------------------------------
# Helper: extract all text from an event for scanning
# ---------------------------------------------------------------------------

def _event_text(
    title: str,
    body_raw: str | None,
    body_structured_json: dict | None,
    tags: list[str] | None,
) -> str:
    """Concatenate all textual event content for pattern scanning."""
    parts = [title]
    if body_raw:
        parts.append(body_raw)
    if body_structured_json:
        parts.append(_flatten_dict(body_structured_json))
    if tags:
        parts.extend(tags)
    return "\n".join(parts)


def _flatten_dict(d: dict, prefix: str = "") -> str:
    """Recursively flatten dict values into a single string."""
    parts: list[str] = []
    for key, value in d.items():
        if isinstance(value, str):
            parts.append(value)
        elif isinstance(value, dict):
            parts.append(_flatten_dict(value, f"{prefix}{key}."))
        elif isinstance(value, list):
            for item in value:
                if isinstance(item, str):
                    parts.append(item)
                elif isinstance(item, dict):
                    parts.append(_flatten_dict(item))
        else:
            parts.append(str(value))
    return " ".join(parts)


# ===================================================================
# 1. New Domain Contacted
# ===================================================================

# Matches URLs and bare domain patterns in text
_DOMAIN_PATTERNS = [
    re.compile(r"https?://([a-zA-Z0-9][-a-zA-Z0-9]*(?:\.[a-zA-Z0-9][-a-zA-Z0-9]*)+)"),
    re.compile(r"\b([a-zA-Z0-9][-a-zA-Z0-9]*\.(?:com|net|org|io|dev|xyz|ru|cn|tk|top|pw|cc|ws|info|biz|co)\b)"),
]

# Known benign domains that shouldn't trigger alerts
_BENIGN_DOMAINS = frozenset({
    "github.com", "gitlab.com", "bitbucket.org",
    "google.com", "googleapis.com", "gstatic.com",
    "microsoft.com", "azure.com", "windows.net",
    "amazon.com", "amazonaws.com", "aws.amazon.com",
    "python.org", "pypi.org", "npmjs.com",
    "stackoverflow.com", "reddit.com",
    "docker.com", "docker.io",
    "ubuntu.com", "debian.org",
    "cloudflare.com", "fastly.net",
    "apple.com", "icloud.com",
})


class NewDomainDetector:
    """Flags first-seen domains in event data.

    Maintains a per-instance set of known domains (passed in via
    ``known_domains``). Any domain not in that set triggers an alert.
    """

    name = "new_domain"

    def analyze(
        self,
        *,
        title: str,
        body_raw: str | None,
        body_structured_json: dict | None,
        tags: list[str] | None,
        skill_name: str,
        known_domains: set[str] | None = None,
    ) -> list[DetectorResult]:
        text = _event_text(title, body_raw, body_structured_json, tags)
        domains = set()
        for pattern in _DOMAIN_PATTERNS:
            for match in pattern.finditer(text):
                domain = match.group(1).lower()
                domains.add(domain)

        if not domains:
            return []

        known = known_domains or set()
        new_domains = domains - known - _BENIGN_DOMAINS
        if not new_domains:
            return []

        # Suspicious TLDs get higher severity
        suspicious_tlds = {".ru", ".cn", ".tk", ".top", ".pw", ".cc", ".ws"}
        has_suspicious = any(
            any(d.endswith(tld) for tld in suspicious_tlds) for d in new_domains
        )

        severity = Severity.critical if has_suspicious else Severity.warn
        domain_list = ", ".join(sorted(new_domains))

        return [DetectorResult(
            detector_name=self.name,
            severity=severity,
            explanation=(
                f"New domain(s) contacted that have not been seen before for this instance: "
                f"{domain_list}. "
                f"{'Includes domains with suspicious TLDs. ' if has_suspicious else ''}"
                f"Verify these domains are expected for skill '{skill_name}'."
            ),
            recommended_action="investigate" if not has_suspicious else "disable_skill",
            evidence={
                "new_domains": sorted(new_domains),
                "skill_name": skill_name,
                "suspicious_tlds": has_suspicious,
            },
        )]


# ===================================================================
# 2. Shell Spawned
# ===================================================================

_SHELL_PATTERNS = [
    re.compile(r"\b(?:bash|/bin/bash|/usr/bin/bash)\b", re.IGNORECASE),
    re.compile(r"\b(?:zsh|/bin/zsh|/usr/bin/zsh)\b", re.IGNORECASE),
    re.compile(r"\b(?:sh|/bin/sh|/usr/bin/sh)\b(?!\w)"),
    re.compile(r"\b(?:powershell|pwsh|powershell\.exe)\b", re.IGNORECASE),
    re.compile(r"\b(?:cmd\.exe|cmd)\b(?=\s|$|/)", re.IGNORECASE),
    re.compile(r"\bsubprocess\.(?:run|call|Popen|check_output|check_call)\b"),
    re.compile(r"\bos\.(?:system|popen|exec[lv]p?e?)\b"),
    re.compile(r"\bchild_process\.exec\b"),
    re.compile(r"\bRuntime\.getRuntime\(\)\.exec\b"),
]

_DANGEROUS_COMMANDS = [
    re.compile(r"\brm\s+-rf\b"),
    re.compile(r"\bchmod\s+777\b"),
    re.compile(r"\bcurl\s+.*\|\s*(?:bash|sh)\b"),
    re.compile(r"\bwget\s+.*\|\s*(?:bash|sh)\b"),
    re.compile(r"\bnc\s+-[elp]"),  # netcat listener
    re.compile(r"\b(?:nc|ncat)\s+.*\d+\.\d+\.\d+\.\d+"),
    re.compile(r"\breverse.?shell\b", re.IGNORECASE),
]


class ShellSpawnedDetector:
    """Flags shell process invocations (bash, zsh, powershell, cmd, subprocess)."""

    name = "shell_spawned"

    def analyze(
        self,
        *,
        title: str,
        body_raw: str | None,
        body_structured_json: dict | None,
        tags: list[str] | None,
        skill_name: str,
    ) -> list[DetectorResult]:
        text = _event_text(title, body_raw, body_structured_json, tags)

        shells_found: list[str] = []
        for pattern in _SHELL_PATTERNS:
            matches = pattern.findall(text)
            shells_found.extend(matches)

        if not shells_found:
            return []

        # Check for dangerous commands → escalate to critical
        dangerous_found: list[str] = []
        for pattern in _DANGEROUS_COMMANDS:
            matches = pattern.findall(text)
            dangerous_found.extend(matches)

        severity = Severity.critical if dangerous_found else Severity.warn

        explanation_parts = [
            f"Shell invocation detected: {', '.join(set(shells_found[:5]))}."
        ]
        if dangerous_found:
            explanation_parts.append(
                f"Dangerous command patterns found: {', '.join(set(dangerous_found[:3]))}."
            )
        explanation_parts.append(f"Skill '{skill_name}' may be executing arbitrary commands.")

        return [DetectorResult(
            detector_name=self.name,
            severity=severity,
            explanation=" ".join(explanation_parts),
            recommended_action="pause_instance" if dangerous_found else "disable_skill",
            evidence={
                "shells": list(set(shells_found[:10])),
                "dangerous_commands": list(set(dangerous_found[:5])),
                "skill_name": skill_name,
            },
        )]


# ===================================================================
# 3. Sensitive Path Access
# ===================================================================

_SENSITIVE_PATHS = [
    # SSH
    (re.compile(r"(?:/home/\w+|~)?/\.ssh/(?:id_rsa|id_ed25519|id_ecdsa|authorized_keys|known_hosts|config)"), "SSH key/config"),
    (re.compile(r"C:\\Users\\\w+\\\.ssh\\", re.IGNORECASE), "SSH directory (Windows)"),
    # GPG
    (re.compile(r"(?:/home/\w+|~)?/\.gnupg/"), "GPG keyring"),
    # Browser profiles
    (re.compile(r"(?:/home/\w+|~)?/\.(?:mozilla|config/google-chrome|config/chromium)/"), "Browser profile"),
    (re.compile(r"Library/Application Support/(?:Google/Chrome|Firefox|Brave)", re.IGNORECASE), "Browser profile (macOS)"),
    (re.compile(r"AppData\\(?:Local|Roaming)\\(?:Google\\Chrome|Mozilla\\Firefox|BraveSoftware)", re.IGNORECASE), "Browser profile (Windows)"),
    # Crypto wallets
    (re.compile(r"(?:/home/\w+|~)?/\.(?:bitcoin|ethereum|electrum|monero)/"), "Cryptocurrency wallet"),
    (re.compile(r"wallet\.dat\b", re.IGNORECASE), "Wallet file"),
    # System credentials
    (re.compile(r"/etc/shadow\b"), "/etc/shadow"),
    (re.compile(r"/etc/passwd\b"), "/etc/passwd"),
    (re.compile(r"(?:/home/\w+|~)?/\.(?:aws|azure|gcloud)/"), "Cloud provider credentials"),
    (re.compile(r"\.env\b"), ".env file"),
    (re.compile(r"(?:/home/\w+|~)?/\.(?:netrc|pgpass|my\.cnf)\b"), "Credentials file"),
    # Keychain
    (re.compile(r"Keychain/.*\.keychain", re.IGNORECASE), "macOS Keychain"),
]


class SensitivePathDetector:
    """Flags access to SSH keys, browser profiles, crypto wallets, and credentials."""

    name = "sensitive_path"

    def analyze(
        self,
        *,
        title: str,
        body_raw: str | None,
        body_structured_json: dict | None,
        tags: list[str] | None,
        skill_name: str,
    ) -> list[DetectorResult]:
        text = _event_text(title, body_raw, body_structured_json, tags)

        paths_found: list[tuple[str, str]] = []
        for pattern, label in _SENSITIVE_PATHS:
            matches = pattern.findall(text)
            for match in matches:
                paths_found.append((match, label))

        if not paths_found:
            return []

        labels = list(set(label for _, label in paths_found))
        path_strs = list(set(path for path, _ in paths_found))

        return [DetectorResult(
            detector_name=self.name,
            severity=Severity.critical,
            explanation=(
                f"Sensitive path access detected: {', '.join(labels[:5])}. "
                f"Skill '{skill_name}' is accessing protected system files or credentials. "
                f"This could indicate data exfiltration or unauthorized access."
            ),
            recommended_action="kill_switch",
            evidence={
                "paths": path_strs[:10],
                "categories": labels[:10],
                "skill_name": skill_name,
            },
        )]


# ===================================================================
# 4. High-Frequency Loop
# ===================================================================


class HighFrequencyLoopDetector:
    """Flags rapid repeated actions from the same skill.

    Checks recent event timestamps to determine if the same skill is
    sending events at an abnormal rate.
    """

    name = "high_loop"

    # Default: more than 20 events in 60 seconds is suspicious
    DEFAULT_THRESHOLD = 20
    DEFAULT_WINDOW_SECONDS = 60

    def analyze(
        self,
        *,
        skill_name: str,
        recent_event_timestamps: list[datetime],
        threshold: int | None = None,
        window_seconds: int | None = None,
        title: str = "",
        body_raw: str | None = None,
        body_structured_json: dict | None = None,
        tags: list[str] | None = None,
    ) -> list[DetectorResult]:
        threshold = threshold or self.DEFAULT_THRESHOLD
        window = window_seconds or self.DEFAULT_WINDOW_SECONDS

        if len(recent_event_timestamps) < threshold:
            return []

        now = datetime.now(timezone.utc)
        recent = [
            ts for ts in recent_event_timestamps
            if (now - ts).total_seconds() <= window
        ]

        if len(recent) < threshold:
            return []

        rate = len(recent) / window

        severity = Severity.critical if len(recent) >= threshold * 2 else Severity.warn

        return [DetectorResult(
            detector_name=self.name,
            severity=severity,
            explanation=(
                f"High-frequency event loop detected: skill '{skill_name}' sent "
                f"{len(recent)} events in the last {window} seconds "
                f"(rate: {rate:.1f}/s, threshold: {threshold}/{window}s). "
                f"This may indicate an infinite loop or runaway process."
            ),
            recommended_action="pause_instance",
            evidence={
                "skill_name": skill_name,
                "event_count": len(recent),
                "window_seconds": window,
                "rate_per_second": round(rate, 2),
                "threshold": threshold,
            },
        )]


# ===================================================================
# 5. Unexpected Secret Pattern
# ===================================================================

_SECRET_PATTERNS = [
    (re.compile(r"(?:sk|pk)[-_](?:live|test)[-_][a-zA-Z0-9]{20,}"), "Stripe-style API key"),
    (re.compile(r"AKIA[0-9A-Z]{16}"), "AWS Access Key ID"),
    (re.compile(r"(?:ghp|gho|ghu|ghs|ghr)_[a-zA-Z0-9]{36,}"), "GitHub token"),
    (re.compile(r"xox[bporas]-[a-zA-Z0-9-]{10,}"), "Slack token"),
    (re.compile(r"eyJ[a-zA-Z0-9_-]{10,}\.eyJ[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}"), "JWT"),
    (re.compile(r"-----BEGIN (?:RSA |EC |DSA )?PRIVATE KEY-----"), "Private key"),
    (re.compile(r"Bearer\s+[a-zA-Z0-9_.~+/=-]{40,}", re.IGNORECASE), "Bearer token (long)"),
    (re.compile(r"(?:password|passwd|pwd)\s*[:=]\s*\S{8,}", re.IGNORECASE), "Password assignment"),
    (re.compile(r"(?:api[_-]?key|apikey|secret[_-]?key)\s*[:=]\s*['\"]?[a-zA-Z0-9_/-]{16,}", re.IGNORECASE), "API key assignment"),
    (re.compile(r"mongodb(?:\+srv)?://[^\s]+:[^\s]+@"), "MongoDB connection string"),
    (re.compile(r"postgres(?:ql)?://[^\s]+:[^\s]+@"), "PostgreSQL connection string"),
    (re.compile(r"mysql://[^\s]+:[^\s]+@"), "MySQL connection string"),
]


class SecretPatternDetector:
    """Flags API keys, JWTs, private keys, and other secrets in event output."""

    name = "secret_pattern"

    def analyze(
        self,
        *,
        title: str,
        body_raw: str | None,
        body_structured_json: dict | None,
        tags: list[str] | None,
        skill_name: str,
    ) -> list[DetectorResult]:
        text = _event_text(title, body_raw, body_structured_json, tags)

        secrets_found: list[tuple[str, str]] = []
        for pattern, label in _SECRET_PATTERNS:
            matches = pattern.findall(text)
            for match in matches:
                # Truncate the matched value for evidence (don't store full secrets)
                truncated = match[:8] + "..." + match[-4:] if len(match) > 16 else match[:8] + "..."
                secrets_found.append((truncated, label))

        if not secrets_found:
            return []

        labels = list(set(label for _, label in secrets_found))

        # Private keys and connection strings are always critical
        critical_labels = {"Private key", "MongoDB connection string", "PostgreSQL connection string", "MySQL connection string"}
        has_critical = any(label in critical_labels for label in labels)

        severity = Severity.critical if has_critical else Severity.warn

        return [DetectorResult(
            detector_name=self.name,
            severity=severity,
            explanation=(
                f"Secret pattern(s) detected in output from skill '{skill_name}': "
                f"{', '.join(labels[:5])}. "
                f"Secrets in event output may be logged, cached, or transmitted insecurely."
            ),
            recommended_action="disable_skill" if has_critical else "investigate",
            evidence={
                "secret_types": labels,
                "count": len(secrets_found),
                "truncated_samples": [s for s, _ in secrets_found[:5]],
                "skill_name": skill_name,
            },
        )]


# ===================================================================
# Detector runner — runs all detectors on an event
# ===================================================================

# Singleton instances
_new_domain_detector = NewDomainDetector()
_shell_spawned_detector = ShellSpawnedDetector()
_sensitive_path_detector = SensitivePathDetector()
_high_frequency_loop_detector = HighFrequencyLoopDetector()
_secret_pattern_detector = SecretPatternDetector()


def run_detectors(
    *,
    title: str,
    body_raw: str | None,
    body_structured_json: dict | None,
    tags: list[str] | None,
    skill_name: str,
    known_domains: set[str] | None = None,
    recent_event_timestamps: list[datetime] | None = None,
) -> list[DetectorResult]:
    """Run all 5 detectors against event data and return combined results."""
    event_kwargs = {
        "title": title,
        "body_raw": body_raw,
        "body_structured_json": body_structured_json,
        "tags": tags,
        "skill_name": skill_name,
    }

    results: list[DetectorResult] = []

    # 1. New Domain
    results.extend(_new_domain_detector.analyze(
        **event_kwargs, known_domains=known_domains,
    ))

    # 2. Shell Spawned
    results.extend(_shell_spawned_detector.analyze(**event_kwargs))

    # 3. Sensitive Path
    results.extend(_sensitive_path_detector.analyze(**event_kwargs))

    # 4. High-Frequency Loop
    results.extend(_high_frequency_loop_detector.analyze(
        skill_name=skill_name,
        recent_event_timestamps=recent_event_timestamps or [],
        title=title,
        body_raw=body_raw,
        body_structured_json=body_structured_json,
        tags=tags,
    ))

    # 5. Secret Pattern
    results.extend(_secret_pattern_detector.analyze(**event_kwargs))

    return results
