# CLAUDE.md — AgentCompanion Project

## Project Overview

AgentCompanion is an iOS-first mobile app (with future Android + Web) that connects to a user's OpenClaw/Clawdbot AI agent deployment. It provides: an output inbox, remote control/monitoring, security "agent antivirus" detection, and a polished Control Center experience. Privacy-first, encryption-everywhere.

Full specifications are in `docs/`. **Read these before building anything:**

- `docs/openclawguidesignspecclaude.txt` — Complete build spec (architecture, security, data model, milestones 1–6, acceptance criteria)
- `docs/OpenclawUiSpecification.txt` — Full UI/UX spec (screens, components, design tokens, accessibility, motion)
- `docs/openclawguiaddendum.txt` — Addendum: Unified Assistant (Chat), Human-in-the-Loop Approvals, Security Intel (VirusTotal/SkillShield/Red Council), milestones 7–10

---

## Monorepo Structure

```
agentcompanion/
├── CLAUDE.md              ← You are here
├── apps/
│   └── ios/               # SwiftUI app (iOS 17+)
│       ├── AgentCompanion/ 
│       │   ├── App/       # App entry, navigation, tabs
│       │   ├── DesignSystem/  # Tokens, spacing, typography, colors
│       │   ├── Components/    # Reusable views (AgentCardView, SeverityBadge, etc.)
│       │   ├── Features/      # Feature modules
│       │   │   ├── Onboarding/
│       │   │   ├── Inbox/
│       │   │   ├── Chat/        # M7: ChatHomeView, ChatThreadView, ChatViewModel
│       │   │   ├── EventDetail/
│       │   │   ├── Control/
│       │   │   ├── Security/
│       │   │   └── Settings/
│       │   ├── Services/      # API client, auth, push, local DB
│       │   ├── Models/        # Data models
│       │   └── Resources/     # Assets, localization
│       ├── AgentCompanion.xcodeproj
│       └── DailyBriefWidget/ # M6: WidgetKit extension
├── backend/               # FastAPI + Postgres + Redis
│   ├── app/
│   │   ├── main.py
│   │   ├── api/           # Route modules (ingest, auth, events, commands, alerts, chat, approvals)
│   │   ├── models/        # SQLAlchemy models (event, alert, command, thread, message, approval)
│   │   ├── schemas/       # Pydantic schemas
│   │   ├── services/      # Business logic (auth, ingest, detectors, PII scrubber, router, conversation, orchestrator, intel)
│   │   ├── security/      # HMAC verification, encryption, PII redaction
│   │   ├── core/          # Config, database, dependencies
│   │   └── resources/     # M9: Red Council pattern packs (JSON/YAML)
│   ├── alembic/           # DB migrations
│   ├── tests/
│   ├── requirements.txt
│   ├── Dockerfile
│   └── railway.toml       # Railway deployment config
├── bridge-skill/          # Python skill for OpenClaw/Clawdbot
│   ├── companion_bridge.py
│   ├── config.yaml
│   └── README.md          # Install instructions
├── sensor/                # Future: Go/Rust local daemon
├── docs/
│   ├── openclawguidesignspecclaude.txt
│   ├── OpenclawUiSpecification.txt
│   ├── openclawguiaddendum.txt  # Unified Assistant, Security Intel, Approvals spec
│   ├── THREAT_MODEL.md
│   ├── API.md
│   └── SECURITY_CHECKLIST.md
├── .github/
│   └── workflows/         # CI: lint + tests
├── .gitignore
├── LICENSE                # BSL 1.1 (private during MVP)
└── README.md
```

---

## Tech Stack

### Backend
- **Framework:** FastAPI (Python 3.11+)
- **Database:** PostgreSQL (via Railway)
- **Cache/Queue:** Redis (via Railway)
- **ORM:** SQLAlchemy (async) with Alembic migrations
- **Auth:** Email/password + JWT (short-lived access tokens, secure refresh tokens)
- **Push:** APNs (iOS), FCM later (Android)
- **Hosting:** Railway (free tier for MVP, scales to production)
- **Validation:** Pydantic v2

### iOS App
- **Framework:** SwiftUI (iOS 17+ minimum)
- **Architecture:** MVVM with observable objects
- **Local DB:** SwiftData or CoreData with SQLCipher encryption (choose at build time)
- **Networking:** URLSession with async/await
- **Auth storage:** Keychain Services
- **Search:** Basic text search on local DB (MVP), full-text on backend
- **Push:** APNs with silent push + fetch pattern

### Bridge Skill
- **Language:** Python
- **Runs inside:** OpenClaw/Clawdbot runtime
- **Output:** Structured JSON events POSTed to backend `/ingest`
- **Auth:** HMAC-SHA256 signed payloads

### Sensor Daemon (Post-MVP)
- **Language:** Go or Rust
- **Runs as:** macOS LaunchAgent / Linux systemd service

---

## Encryption & Security Rules

### MVP Encryption
- **In transit:** TLS everywhere, no exceptions
- **At rest (backend):** Application-level envelope encryption using Python `cryptography` library. Encryption keys stored in Railway environment variables. Design the encryption service with a clean interface so KMS provider can be swapped later (AWS KMS, GCP KMS, Vault)
- **On device:** Keychain for tokens/secrets. Encrypted local database (SQLCipher or iOS Data Protection)
- **Push notifications:** NEVER include sensitive content. Use generic "You have a new agent update" then fetch inside app

### Production Migration Path
- Swap to AWS KMS or GCP KMS for envelope encryption
- Add HSM-backed key storage
- The encryption service interface should not change

### HMAC Event Integrity
- Each instance gets a shared secret on creation
- Events signed: `HMAC-SHA256(secret, timestamp + JSON payload)`
- Backend verifies signature, rejects invalid events
- Support secret rotation + token revocation

### PII Scrubber (Must Implement)
- Runs as middleware before any event persistence
- Redacts by default: emails, phone numbers, addresses, API keys, JWTs, OAuth tokens
- Uses regex patterns + optional NER for names
- `pii_redacted: boolean` flag on every event
- User can toggle redaction level in settings (but cannot fully disable without warning)

### Data Minimization Defaults
- Store structured summaries, NOT raw text (raw is opt-in)
- Never store file contents, email bodies, or secrets by default
- Keep only metadata unless user explicitly opts into full capture
- Do not store full URLs with query strings by default
- Store metadata (counts/domains) rather than raw payloads
- All commands + approvals must be audited (who, when, what)

---

## Data Model (Backend Entities)

### Core Entities
- **User** — account, email, hashed password, MFA status
- **Device** — paired devices per user, trust status, revokable
- **Instance** — a Claw deployment, has shared secret, health status, mode (active/paused/safe)
- **IntegrationToken** — scoped per instance + per skill, revokable
- **Event** — agent output (see schema below)
- **Alert** — security detector output, linked to event
- **Skill** — declared + observed, trust status (trusted/untrusted/unknown)

### Event Schema
```
id: UUID
user_id: FK
instance_id: FK
source_type: enum (gateway | skill | telegram | sensor)
agent_name: string
skill_name: string
timestamp: datetime
title: string
body_raw: text (optional, encrypted)
body_structured_json: jsonb (optional)
tags: string[]
severity: enum (info | warn | critical)
pii_redacted: boolean
hmac_signature: string
created_at: datetime
```

### Chat & Conversation Models (Milestone 7+)
```
Thread:
  id: UUID
  user_id: FK
  instance_id: FK
  title: string (nullable, auto-generated)
  created_at: datetime
  updated_at: datetime

Message:
  id: UUID
  thread_id: FK
  message_type: enum (user_message | assistant_message | agent_message | structured_card_message | system_message | approval_request)
  sender_type: enum (user | assistant | agent | system)
  content: text (nullable)
  structured_json: jsonb (nullable)
  routing_plan_id: FK (nullable)
  correlation_id: UUID (nullable)
  event_id: FK (nullable, links to related Event)
  alert_id: FK (nullable, links to related Alert)
  tool_usage: jsonb (nullable, for tool transparency strip)
  created_at: datetime

RoutingPlan:
  id: UUID
  thread_id: FK
  instance_id: FK
  intent: enum (daily_brief | business_summary | explain_alert | general_qna | control_action | security_inquiry)
  targets: jsonb (array of {type, name, confidence, params})
  requires_approval: boolean
  safety_policy: enum (default | restricted | safe_mode)
  notes: text (nullable)
  created_at: datetime
```

### Approval Model (Milestone 8)
```
ApprovalRequest:
  id: UUID
  instance_id: FK
  thread_id: FK (nullable)
  skill_name: string
  action: enum (send_email | exec_shell | access_sensitive_path | new_domain | bulk_export)
  summary: string
  risk_level: enum (warning | critical)
  options: string[] (allow_once, allow_always, deny)
  evidence: jsonb
  status: enum (pending | approved | denied | expired)
  decided_by: FK (nullable, User)
  decided_at: datetime (nullable)
  expires_at: datetime
  created_at: datetime
```

### Skill Intel Fields (Milestone 9)
```
Skill (extended fields):
  vt_verdict: enum (clean | suspicious | malicious | unknown) (nullable)
  vt_score: int (nullable)
  vt_last_checked_at: datetime (nullable)
  skillshield_score: int (nullable, 0-100)
  skillshield_findings: jsonb (nullable, array of finding objects)
  skillshield_report_url: string (nullable)
  skillshield_last_checked_at: datetime (nullable)
  risk_score: int (computed, 0-100)
  trust_status: enum (trusted | unknown | risky | blocked) (computed)
```

---

## Security Detectors (MVP — Implement All 5)

1. **New domain contacted** — first-seen domain in event data
2. **Shell spawned** — bash/zsh/powershell/cmd/python invoked unexpectedly
3. **Sensitive path access** — SSH keys, browser profiles, crypto wallet dirs
4. **High-frequency loop** — same action repeated rapidly (threshold configurable)
5. **Unexpected secret pattern** — API keys, JWTs found in output/logs

Each detector produces:
- `severity`: info / warn / critical
- `explanation`: human-readable description
- `recommended_action`: disable skill / pause instance / investigate
- Linked to one-tap containment button in UI

---

## iOS UI Rules (Non-Negotiable)

### Design System Tokens
```swift
// Spacing (8pt grid)
Space.xs = 4
Space.sm = 8
Space.md = 12
Space.lg = 16
Space.xl = 24
Space.xxl = 32

// Corner Radius
Radii.card = 16
Radii.pill = 999 (capsule)
Radii.button = 12
Radii.sheet = system default

// Typography — USE ONLY Dynamic Type styles
.title2, .headline, .subheadline, .body, .caption, .caption2
// NEVER use fixed font sizes
```

### Component Library (Must Build)
- `AgentCardView` — universal card for events, alerts, status blocks
- `SeverityBadge` — pill capsule with icon + text (info/warning/critical)
- `InstancePicker` — top pill showing current instance, tap opens sheet
- `PrimaryActionBar` — sticky bottom bar for destructive actions
- `EmptyStateView` — illustration + CTA for empty states
- `SkeletonCardView` — loading placeholder with shimmer

### Hard Rules
- NO hardcoded colors — use system colors (.primary, .secondary, .tertiary)
- NO fixed font sizes — Dynamic Type must scale everything
- NO custom gestures that fight iOS norms
- Dark mode must look intentional (test it)
- All touch targets >= 44x44pt
- Never encode information with color only — always pair with icon + text
- VoiceOver labels on all interactive elements
- Support Reduce Motion setting
- Localization-ready strings everywhere (use String Catalogs or NSLocalizedString)
- State handling on every screen: loading / empty / error / success

### Navigation
- **Milestones 1–6:** 4-tab TabView: Inbox, Control, Security, Settings
- **Milestones 7+:** 5-tab TabView: Inbox, Chat, Control, Security — Settings accessible via gear icon in Inbox/Chat toolbar
- SF Symbols for tab icons, labels visible
- Instance context visible at top of Inbox/Chat/Control/Security tabs

### Motion & Haptics
- Haptics: success = light, warning = medium, destructive = heavy
- Use sparingly. Motion clarifies state, does not entertain.
- All animations respect Reduce Motion

---

## Build Order (Milestones)

### Milestone 0 — Repo Scaffold ✅
Monorepo layout, CI setup, README, CLAUDE.md, specs in docs/

### Milestone 1 — Backend MVP
- Auth (email/password + JWT)
- Instance creation + integration token generation
- `/ingest` endpoint with HMAC verification
- Event storage with encryption
- Event query API (pagination + filters)
- PII scrubber middleware
- APNs push pipeline (silent push + fetch)
- Railway deployment config

### Milestone 2 — iOS MVP
- Design system module (tokens + components)
- Onboarding + pairing flow
- Inbox feed (pagination, pull to refresh)
- Event detail view (structured + raw toggle)
- Search + filter chips
- Offline cache (encrypted local DB)
- Push notification handling

### Milestone 3 — Bridge Skill MVP
- Minimal Python skill for OpenClaw/Clawdbot
- Wraps outputs into Event schema JSON
- HMAC signs and POSTs to backend `/ingest`
- Install instructions in README

### Milestone 4 — Security MVP
- 5 detectors running on ingested events
- Alert creation + storage
- Security tab UI (alerts list, risk summary, skill trust list)
- Containment endpoints (disable skill, pause instance)

### Milestone 5 — Control Surface MVP
- Kill switch endpoints (revoke token, pause instance, reject ingest)
- Control tab UI (system status, quick actions, routing toggles)
- Command channel to bridge skill (polling)

### Milestone 6 — Premium UX Polish
- Animations, haptics, typography audit
- Full accessibility audit
- iOS widget v1 (daily brief)
- TTS readout on event detail

### Milestone 7 — Chat & Unified Assistant
- **Navigation change:** 5-tab TabView: Inbox / Chat / Control / Security, Settings via gear icon inside Inbox/Chat
- **Chat tab (iOS):**
  - `ChatHomeView` — single "Assistant" conversation with optional instance picker pill
  - `ChatThreadView` — message list supporting types: `user_message`, `assistant_message`, `agent_message`, `structured_card_message`, `system_message`, `approval_request`
  - Composer + send button
  - Message rendering: rich cards (same renderer as Inbox) for structured outputs, plain bubbles for text
- **Backend — RouterService:**
  - Deterministic keyword + classifier routing (MVP, no LLM):
    - "summary / brief / weather / calendar" → `daily_brief` skill
    - "money / revenue / invoices / sales" → `business_summary` skill
    - "why alert / explain / what happened" → `explain_alert` skill
    - "pause / stop / kill" → `control_action`
    - "is this skill safe / trust / malicious" → `security_inquiry`
    - Fallback: `general_qna` routed to default agent (safe mode)
  - Outputs a `RoutingPlan` with: thread_id, instance_id, intent, targets (type/name/confidence/params), requires_approval, safety_policy, notes
- **Backend — ConversationService:**
  - Stores messages, threads, and relations to events/alerts
  - Supports search and retention policies
- **Backend — OrchestratorService:**
  - Executes routing plans by issuing commands to the instance
  - Tracks correlation IDs and message linkage
- **Chat API endpoints (FastAPI):**
  - `POST /api/v1/chat/send` — send user message, returns routing plan + enqueues commands
  - `GET /api/v1/chat/thread/{thread_id}` — fetch thread messages
  - `POST /api/v1/chat/receive` — instance sends agent response back (HMAC auth)
  - `GET /api/v1/chat/threads` — list user's threads
  - `POST /api/v1/chat/attach_context` — attach event/alert reference to next message
- **Chat message execution flow:**
  1. App → `POST /chat/send`
  2. Backend stores user msg, generates routing_plan
  3. Backend enqueues command(s) to instance: `run_skill` with params OR `chat_message` to agent
  4. Bridge skill receives, forwards to OpenClaw
  5. Responses come back as `POST /chat/receive` and/or `POST /ingest`
  6. Backend pushes "new message available" (no content) → app fetches
- **New data models:**
  - `Thread` — id, user_id, instance_id, title, created_at, updated_at
  - `Message` — id, thread_id, message_type (enum), sender_type, content, structured_json, routing_plan_json, correlation_id, event_id (FK nullable), alert_id (FK nullable), created_at
  - `RoutingPlan` — id, thread_id, instance_id, intent, targets (JSONB), requires_approval, safety_policy, notes, created_at
- **Command channel extension:**
  - New command types: `chat_message`, `run_skill`
  - Commands include `correlation_id` and `expires_at`
- **Bridge skill extension:**
  - Handle `chat_message` and `run_skill` command types
  - Forward to OpenClaw runtime, return results via `POST /chat/receive`
- **Tests:** Router intent classification, conversation CRUD, chat send/receive flow, routing plan generation

### Milestone 8 — Human-in-the-Loop Approvals
- **Approval request model:**
  - `ApprovalRequest` — approval_id, instance_id, skill_name, action (enum: `send_email`, `exec_shell`, `access_sensitive_path`, `new_domain`, `bulk_export`), summary, risk_level (warning/critical), options (`allow_once`, `allow_always`, `deny`), expires_at, evidence (JSONB), status, decided_by, decided_at, created_at
- **Bridge skill creates approval requests** when agent attempts sensitive actions:
  - Sending email to multiple recipients
  - Accessing sensitive directories
  - Executing shell commands
  - Contacting new/untrusted domains
  - Exporting large data
- **Chat approval cards (iOS):**
  - `ApprovalCardView` — displays in chat as a card with: skill name, action summary, risk level badge, evidence preview, three buttons: "Allow Once" / "Always Allow" / "Deny"
  - Tapping a button sends `approve_action` command back to instance
  - Expired approvals show as disabled with "Expired" label
- **Backend:**
  - `POST /api/v1/approvals` — bridge skill creates approval request (HMAC auth)
  - `POST /api/v1/approvals/{id}/decide` — user decides (JWT auth), forwards `approve_action` command
  - `GET /api/v1/approvals?instance_id=...&status=pending` — list pending approvals
  - Approval decisions audited: who, when, what, from which device
- **Command flow:**
  1. Bridge skill detects sensitive action → creates approval request
  2. Backend stores request, pushes "approval needed" notification
  3. App shows approval card in chat thread
  4. User taps Allow/Deny → `POST /approvals/{id}/decide`
  5. Backend creates `approve_action` command with decision
  6. Bridge skill receives decision, allows or blocks the action
- **Tests:** Approval creation, decision flow, expiry handling, audit trail, chat card rendering data

### Milestone 9 — Security Intel Integration
- **VirusTotal integration:**
  - For each skill artifact: compute SHA-256 hash, query VT reputation
  - Store on Skill model: `vt_verdict` (clean/suspicious/malicious/unknown), `vt_score`, `vt_last_checked_at`
  - Alert rules: malicious → Critical + recommend disable + kill switch CTA; suspicious → Warning + recommend restrict; verdict change clean→suspicious/malicious → Critical/Warning
  - UI: Skill row shows "VirusTotal: Clean / Suspicious / Malicious" badge
  - **Never upload user secrets** — only scan skill artifact hashes
- **SkillShield integration:**
  - Query SkillShield for trust score (0–100) and finding categories
  - Store on Skill model: `skillshield_score`, `skillshield_findings[]`, `skillshield_report_url`, `skillshield_last_checked_at`
  - Alert rules: score drop ≥15 → Warning; score drop ≥30 or new high severity finding → Critical; new findings hash → Info
  - UI: "SkillShield: 82/100" badge + "View report" link
- **Red Council integration:**
  - A) Offline test corpus (MVP): ship curated pattern packs as JSON/YAML in `backend/resources/redcouncil/`
    - Categories: `prompt_injection`, `secret_exfiltration`, `tool_abuse`, `data_poisoning_signals`
  - B) Canary checks (Pro/optional): periodic safe probes in sandbox mode; if response matches exfiltration/jailbreak patterns → Critical alert
  - UI: Detector settings adds optional detectors: "Canary: Prompt injection", "Canary: Secret exfiltration"; Alerts show source "Red Council Canary"
- **Unified risk scoring (per skill):**
  - Start at 100, subtract: -60 VT malicious, -30 VT suspicious, -(80 - skillshield_score) * 0.5 (cap 40), -25 shell spawned unexpectedly, -25 secret pattern detected, -15 new domain + no allowlist, -40 canary exfiltration hit
  - Trust status: 80–100 Trusted, 50–79 Unknown, 20–49 Risky, <20 or VT malicious → Blocked
  - Auto-policy (optional): Blocked → backend recommends disable, surfaces Kill Switch CTA
- **API changes:**
  - `GET /api/v1/skills` extended with vt + skillshield fields
  - `POST /api/v1/skills/{id}/rescan_intel` — trigger re-scan of VT + SkillShield
  - `GET /api/v1/alerts` extended with source filter: `runtime|virustotal|skillshield|redcouncil`
- **Tests:** VT verdict → alert generation, SkillShield score drop → alert, Red Council pattern matching, risk score calculation, trust status thresholds

### Milestone 10 — Premium Chat Polish
- **Tool transparency strip:**
  - For each assistant/agent response, display a collapsible strip showing:
    - Tools used: WebSearch / Email / Files / Shell / Network (icons)
    - Domains contacted: count + top 3 domains (redacted)
    - Duration
    - Risk flags (if any detectors triggered during execution)
  - `ToolTransparencyStrip` SwiftUI component
- **Quick chips above composer:**
  - Horizontally scrollable chip row: "Run Daily Brief", "Business Summary", "Explain this alert", "Pause instance"
  - Tapping a chip inserts it as a message and auto-sends
  - Chips contextualize: if viewing an alert, show "Explain this alert" chip
- **Attach context:**
  - "Attach last event", "Attach this alert", "Attach last 24h activity summary"
  - Shows as a small preview card above the composer
  - Sends attached reference IDs with the message via `POST /chat/attach_context`
- **Rich card rendering in chat:**
  - `structured_card_message` renders using same card components as Inbox (AgentCardView, SeverityBadge)
  - KPI cards, daily brief cards, weather cards — all using `body_structured_json`
  - System messages render as centered gray text
  - Agent messages show "Routed to: {skill_name}" subtitle
- **Accessibility:** VoiceOver for all chat elements, tool strip, chips, approval cards
- **Haptics:** Send message = light, approval decision = medium/heavy, chip tap = selection
- **Tests:** Chat UI snapshot data, tool strip rendering, chip insertion logic

---

## API Design Conventions

- RESTful endpoints, versioned: `/api/v1/...`
- Auth header: `Authorization: Bearer <jwt>`
- HMAC ingest header: `X-Signature: <hmac>`, `X-Timestamp: <unix>`
- Pagination: cursor-based (`?cursor=xxx&limit=20`)
- Error responses: `{ "error": "message", "code": "ERROR_CODE" }`
- All timestamps: ISO 8601 UTC

### API Endpoints by Milestone

**Milestones 1–6 (existing):**
- `POST /api/v1/auth/register`, `POST /api/v1/auth/login`, `POST /api/v1/auth/refresh`
- `POST /api/v1/ingest` (HMAC auth)
- `GET /api/v1/events`, `GET /api/v1/events/{id}`
- `GET /api/v1/instances`, `GET /api/v1/instances/{id}`
- `POST /api/v1/instances/{id}/pause`, `POST /api/v1/instances/{id}/resume`, `POST /api/v1/instances/{id}/kill-switch`
- `POST /api/v1/instances/{id}/commands`, `GET /api/v1/instances/{id}/commands`
- `GET /api/v1/instances/{id}/commands/pending` (HMAC auth, for bridge skill polling)
- `POST /api/v1/instances/{id}/commands/{cmd_id}/ack` (HMAC auth)
- `GET /api/v1/instances/{id}/alerts`, `GET /api/v1/instances/{id}/alerts/{id}`
- `GET /api/v1/instances/{id}/risk-summary`
- `GET /api/v1/instances/{id}/skills`, `POST /api/v1/instances/{id}/skills/{name}/disable`

**Milestone 7 — Chat:**
- `POST /api/v1/chat/send` — JWT auth, send user message + get routing plan
- `GET /api/v1/chat/threads` — JWT auth, list user threads
- `GET /api/v1/chat/thread/{thread_id}` — JWT auth, fetch thread messages
- `POST /api/v1/chat/receive` — HMAC auth, instance sends agent response
- `POST /api/v1/chat/attach_context` — JWT auth, attach event/alert ref

**Milestone 8 — Approvals:**
- `POST /api/v1/approvals` — HMAC auth, bridge skill creates approval request
- `GET /api/v1/approvals?instance_id=...&status=pending` — JWT auth, list approvals
- `POST /api/v1/approvals/{id}/decide` — JWT auth, approve/deny decision

**Milestone 9 — Security Intel:**
- `GET /api/v1/skills` extended with VT + SkillShield fields
- `POST /api/v1/skills/{id}/rescan_intel` — JWT auth, trigger VT + SkillShield re-scan
- `GET /api/v1/alerts` extended with `?source=runtime|virustotal|skillshield|redcouncil` filter

---

## Testing Requirements

- **Backend:** pytest with async support. Unit tests for auth, HMAC verification, PII scrubber, each detector. Integration tests for ingest pipeline.
- **iOS:** XCTest for view models and services. UI tests for critical flows (onboarding, inbox navigation). Snapshot tests optional.
- **Bridge Skill:** pytest for event formatting and HMAC signing.
- **CI:** GitHub Actions — lint + test on every PR.

---

## Git Workflow

- `main` branch is protected
- Feature branches: `milestone-X-description` (e.g., `milestone-1-backend-mvp`)
- PR required before merging to main
- CI must pass before merge

---

## Hosting & Deployment

- **Backend:** Railway (auto-deploy from GitHub `main` branch)
  - Postgres addon
  - Redis addon
  - Environment variables for secrets, encryption keys, APNs certs
- **iOS:** Xcode → TestFlight for beta, App Store for release
- **Bridge Skill:** Distributed as installable Python package / marketplace listing

---

## License

BSL 1.1 (Business Source License) — private repo during MVP phase.
Source visible but commercial use restricted. Converts to open source after chosen time period.
Final license decision before public release.

---

## Acceptance Criteria (MVP Complete When — Milestones 1–6)

1. User can install bridge skill, pair iOS app, see agent outputs in inbox
2. Outputs are stored, searchable, and available offline
3. No PII in push notification payloads
4. HMAC signed ingest prevents event spoofing
5. All 5 security detectors flag obvious bad patterns
6. Kill switch stops new data ingest immediately
7. UI feels native, clean, fast — passes accessibility audit
8. Dark mode works correctly throughout
9. All destructive actions have confirmation sheets

## Acceptance Criteria (Milestones 7–10)

10. User can type in Chat and get routed execution without picking agents manually
11. Routing plan is visible in UI ("Routed to …") and logged server-side
12. Responses render as rich cards when structured output exists
13. Tool transparency strip shows tools/domains used (metadata only)
14. Approvals appear in chat and can stop sensitive actions before they execute
15. Approval decisions are audited (who, when, what, from which device)
16. Security tab shows VT + SkillShield + Red Council-derived alerts and trust status
17. Unified risk score computed per skill from all intel sources
18. No PII in push notifications, aggressive redaction of secrets in logs and evidence
19. All commands + approvals audited with full traceability

---

## Important: Ask Before Deciding

When building, ask me (the developer) before making these decisions:
- Choosing between SwiftData vs CoreData vs Realm for local persistence
- Specific KMS provider if envelope encryption needs a cloud service
- Any third-party dependencies not listed in this doc
- Push notification certificate setup (requires Apple Developer account)
- Any architectural change that deviates from the spec documents
