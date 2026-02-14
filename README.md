# OpenClaw GUI (Mobile Companion)

A native mobile companion for OpenClaw/Clawdbot that turns agent output into a first-class mobile experience — with an Inbox, remote Control Center, and Security monitoring.

## What it does

- **Inbox for agent output**: store, search, and view agent updates in a clean card UI (instead of chat logs).
- **Control Center**: monitor instance health, view active runs, start/stop runs, and use a kill switch.
- **Security / “Agent Antivirus”**: detect suspicious behaviors (new domains, shell execution, secret patterns, etc.) and take one-tap containment actions.
- **Polished UX**: confirmation dialogs with “why this matters”, haptics, accessibility-first UI.

## Current status

✅ Control tab implemented  
✅ Security tab implemented  
🔜 Inbox + pairing + ingestion (bridge skill / webhook / gateway)  
🔜 Push notifications + widgets + voice readout

## Screens

### Control
- System Status (health + mode + last seen)
- Active Runs (progress, stop, completion states)
- Quick Actions (pause/resume, kill switch, test run, refresh)
- Output Routing (In-App, Telegram, Email, Structured mode)

### Security
- Today’s risk summary
- Alerts list + alert detail
- Skill trust list (trusted vs untrusted/unknown)
- Detector settings (required detectors cannot be disabled; per-detector sensitivity)

## Architecture (planned)

- **Mobile app**: iOS (SwiftUI) first
- **Integration**: OpenClaw Gateway when available; fallback via bridge skill + webhook; optional Telegram bridge
- **Security telemetry**: optional local “sensor” daemon for higher-signal monitoring
- **Backend**: event ingest + storage + push routing + policy/allowlist (minimal, privacy-first)

## Privacy & security

This project is designed with data minimization in mind:
- Push notifications should never contain sensitive content.
- Outputs can be stored as structured summaries; raw text capture can be optional.
- Telemetry focuses on high-level signals (domains, process names, timestamps), not file contents.

## Getting started

### Requirements
- Xcode (latest stable)
- iOS 16+ (recommended)
- (Optional) OpenClaw/Clawdbot instance for live integration

### Run locally
1. Clone the repo
2. Open the Xcode project
3. Build + run on simulator or device

## Roadmap

- [ ] Inbox + Event Detail (structured + raw)
- [ ] Pairing flow (QR/token)
- [ ] Bridge skill (webhook sender)
- [ ] Push notifications
- [ ] Widgets + voice readout
- [ ] Policy controls (safe mode, allowlists)
- [ ] Android + Web dashboard (later)

## Contributing

PRs welcome. If you’re adding new UI, follow the existing component + design system patterns and keep accessibility in mind.
