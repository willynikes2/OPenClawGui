# AgentCompanion Bridge Skill

Python bridge skill that runs inside OpenClaw / Clawdbot and sends structured events to the AgentCompanion backend.

## Install

```bash
cd bridge-skill
pip install -r requirements.txt
```

## Configure

Copy and edit `config.yaml`:

```yaml
backend_url: "https://your-backend.railway.app"
instance_id: "your-instance-uuid"
instance_secret: "your-shared-secret"
```

The `instance_id` and `instance_secret` come from Settings > Instances in the AgentCompanion app.

## Usage

### Direct send

```python
from companion_bridge import CompanionBridge

bridge = CompanionBridge()  # loads ./config.yaml

bridge.send(
    agent_name="my-agent",
    skill_name="daily-summary",
    title="Daily summary for 2026-02-14",
    body_raw="All systems nominal.",
    severity="info",
    tags=["daily", "summary"],
)
```

### Structured data

```python
bridge.send(
    agent_name="my-agent",
    skill_name="web-scraper",
    title="Scrape results",
    body_structured_json={"url": "https://example.com", "items": 42},
    severity="info",
)
```

### Decorator (auto-wrap skill output)

```python
@bridge.skill("web-scraper", agent_name="my-agent")
def scrape(url: str) -> dict:
    # your skill logic here
    return {"url": url, "items": 42}

scrape("https://example.com")  # automatically sent as an event
```

If the decorated function returns a `dict`, it becomes `body_structured_json`. If it returns a `str`, it becomes `body_raw`.

### Batch send

```python
bridge.send_batch([
    {"agent_name": "bot", "skill_name": "s1", "title": "Event 1"},
    {"agent_name": "bot", "skill_name": "s2", "title": "Event 2"},
])
```

### Context manager

```python
with CompanionBridge() as bridge:
    bridge.send(agent_name="bot", skill_name="ping", title="Health check")
```

## Parameters

| Parameter | Required | Default | Description |
|---|---|---|---|
| `agent_name` | yes | — | Name of the agent sending the event |
| `skill_name` | yes | — | Name of the skill that produced the output |
| `title` | yes | — | Short event title |
| `body_raw` | no | `None` | Raw text body |
| `body_structured_json` | no | `None` | Structured JSON body (dict) |
| `tags` | no | `None` | List of string tags |
| `severity` | no | `"info"` | One of: `info`, `warn`, `critical` |
| `source_type` | no | config default | One of: `gateway`, `skill`, `telegram`, `sensor` |
| `timestamp` | no | now (UTC) | ISO 8601 datetime |

## Security

Events are HMAC-SHA256 signed before sending. The signature is computed as:

```
HMAC-SHA256(instance_secret, str(unix_timestamp) + json_payload)
```

The backend verifies the signature and rejects events older than 5 minutes.

## Tests

```bash
pip install pytest
cd bridge-skill
pytest tests/ -v
```
