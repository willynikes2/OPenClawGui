# CLAUDE.md — AgentCompanion Project

## Project Overview

AgentCompanion is an iOS-first mobile app (with future Android + Web) that connects to a user's OpenClaw/Clawdbot AI agent deployment. It provides: an output inbox, remote control/monitoring, security "agent antivirus" detection, and a polished Control Center experience. Privacy-first, encryption-everywhere.

Full specifications are in `docs/`. **Read these before building anything:**

- `docs/openclawguidesignspecclaude.txt` — Complete build spec (architecture, security, data model, milestones, acceptance criteria)
- `docs/OpenclawUiSpecification.txt` — Full UI/UX spec (screens, components, design tokens, accessibility, motion)

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
│       │   │   ├── EventDetail/
│       │   │   ├── Control/
│       │   │   ├── Security/
│       │   │   └── Settings/
│       │   ├── Services/      # API client, auth, push, local DB
│       │   ├── Models/        # Data models
│       │   └── Resources/     # Assets, localization
│       └── AgentCompanion.xcodeproj
├── backend/               # FastAPI + Postgres + Redis
│   ├── app/
│   │   ├── main.py
│   │   ├── api/           # Route modules
│   │   ├── models/        # SQLAlchemy models
│   │   ├── schemas/       # Pydantic schemas
│   │   ├── services/      # Business logic (auth, ingest, detectors, PII scrubber)
│   │   ├── security/      # HMAC verification, encryption, PII redaction
│   │   └── core/          # Config, database, dependencies
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
- 4-tab TabView: Inbox, Control, Security, Settings
- SF Symbols for tab icons, labels visible
- Instance context visible at top of Inbox/Control/Security tabs

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

---

## API Design Conventions

- RESTful endpoints, versioned: `/api/v1/...`
- Auth header: `Authorization: Bearer <jwt>`
- HMAC ingest header: `X-Signature: <hmac>`, `X-Timestamp: <unix>`
- Pagination: cursor-based (`?cursor=xxx&limit=20`)
- Error responses: `{ "error": "message", "code": "ERROR_CODE" }`
- All timestamps: ISO 8601 UTC

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

## Acceptance Criteria (MVP Complete When)

1. User can install bridge skill, pair iOS app, see agent outputs in inbox
2. Outputs are stored, searchable, and available offline
3. No PII in push notification payloads
4. HMAC signed ingest prevents event spoofing
5. All 5 security detectors flag obvious bad patterns
6. Kill switch stops new data ingest immediately
7. UI feels native, clean, fast — passes accessibility audit
8. Dark mode works correctly throughout
9. All destructive actions have confirmation sheets

---

## Important: Ask Before Deciding

When building, ask me (the developer) before making these decisions:
- Choosing between SwiftData vs CoreData vs Realm for local persistence
- Specific KMS provider if envelope encryption needs a cloud service
- Any third-party dependencies not listed in this doc
- Push notification certificate setup (requires Apple Developer account)
- Any architectural change that deviates from the spec documents
