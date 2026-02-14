"""PII scrubber — redacts emails, phones, API keys, JWTs, addresses, OAuth tokens.

Runs before event persistence. Returns scrubbed text + whether redaction occurred.
"""

import re

# Patterns for common PII and sensitive data
_PATTERNS: list[tuple[str, re.Pattern]] = [
    ("EMAIL", re.compile(r"[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+")),
    ("PHONE", re.compile(r"\b(?:\+?1[-.\s]?)?(?:\(?\d{3}\)?[-.\s]?)?\d{3}[-.\s]?\d{4}\b")),
    ("API_KEY", re.compile(r"(?:sk|pk|api|key|token)[_-][a-zA-Z0-9]{20,}", re.IGNORECASE)),
    ("JWT", re.compile(r"eyJ[a-zA-Z0-9_-]{10,}\.eyJ[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}")),
    ("BEARER", re.compile(r"Bearer\s+[a-zA-Z0-9_.~+/=-]{20,}", re.IGNORECASE)),
    ("AWS_KEY", re.compile(r"AKIA[0-9A-Z]{16}")),
    ("PRIVATE_KEY", re.compile(r"-----BEGIN (?:RSA |EC )?PRIVATE KEY-----")),
    ("IP_ADDRESS", re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b")),
]

_REDACTION_PLACEHOLDER = "[REDACTED:{type}]"


def scrub_text(text: str) -> tuple[str, bool]:
    """Scrub PII from text. Returns (scrubbed_text, was_redacted)."""
    if not text:
        return text, False

    redacted = False
    result = text
    for pii_type, pattern in _PATTERNS:
        new_result = pattern.sub(_REDACTION_PLACEHOLDER.format(type=pii_type), result)
        if new_result != result:
            redacted = True
        result = new_result

    return result, redacted


def scrub_dict(data: dict) -> tuple[dict, bool]:
    """Recursively scrub PII from all string values in a dict."""
    if not data:
        return data, False

    any_redacted = False
    result = {}
    for key, value in data.items():
        if isinstance(value, str):
            scrubbed, was_redacted = scrub_text(value)
            result[key] = scrubbed
            any_redacted = any_redacted or was_redacted
        elif isinstance(value, dict):
            scrubbed, was_redacted = scrub_dict(value)
            result[key] = scrubbed
            any_redacted = any_redacted or was_redacted
        elif isinstance(value, list):
            scrubbed_list = []
            for item in value:
                if isinstance(item, str):
                    scrubbed, was_redacted = scrub_text(item)
                    scrubbed_list.append(scrubbed)
                    any_redacted = any_redacted or was_redacted
                elif isinstance(item, dict):
                    scrubbed, was_redacted = scrub_dict(item)
                    scrubbed_list.append(scrubbed)
                    any_redacted = any_redacted or was_redacted
                else:
                    scrubbed_list.append(item)
            result[key] = scrubbed_list
        else:
            result[key] = value

    return result, any_redacted
