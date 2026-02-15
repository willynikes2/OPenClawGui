# OpenClaw GUI (Mobile Companion)

A native mobile companion for *OpenClaw / Clawdbot* that turns agent outputs into a first-class mobile experience — with an Inbox, remote Control Center, and Security monitoring.

---

## 🚀 Overview

OpenClaw GUI is designed to be the **go-to mobile interface** for users running autonomous AI agents. Instead of dumping outputs into Telegram or Discord, this app gives:

- 📥 A structured **Inbox** of agent output
- 🛠️ A **Control Center** to monitor and manage instances
- 🛡️ A **Security dashboard** to detect anomalous agent behavior
- 💡 Polished UI with haptics, accessibility support, and clear feedback

---

## 🧠 Key Features

### 🕹️ Control Center
- Instance health overview (status, modes)
- Active run list with progress
- Quick actions: Pause, Resume, Kill Switch, Test Run
- Output routing toggles (In-App, Telegram, Email, Structured)

### 🔒 Security Monitoring
- Daily risk summary (“Alerts Today”)
- Filterable alerts list (Info / Warning / Critical)
- Per-skill trust status with Allowlist / Disable controls
- Detector settings with sensitivity levels

### 👁️ UX Highlights
- Confirmation dialogs explaining “why this matters”
- Haptic feedback throughout
- Accessibility support (VoiceOver, dynamic type, contrast)
- Clean onboarding and future pairing flows

---

## 📌 Current Status (MVP)

Completed:
- ✔ Control tab
- ✔ Security tab
- ✔ Accessibility & haptics foundation

In progress / next:
- ◼ iOS WidgetKit daily brief
- ◻ Polished TTS readout
- Inbox + pairing + ingestion pipeline (bridge skill / webhook / Gateway)
- Push notifications
- Backend event storage & sync

---

## 📐 Architecture (planned)

- **Mobile app:** iOS (SwiftUI) first
- **Integration layers:**
  - Primary: OpenClaw Gateway where available
  - Fallback: Bridge skill → Webhook → Backend
  - Optional: Telegram bridge
- **Security telemetry:** Optional local sensor daemon
- **Backend:** FastAPI event ingest + storage + push routing + policy engine

---

## 🔐 Privacy & Security Goals

This project prioritizes **minimal and safe data handling**:
- Push notifications never contain sensitive content
- Structured summaries preferred over raw text
- Telemetry focuses on metadata (domains, process names, timestamps)
- Configurable retention and redaction controls

---

## 🧪 Getting Started

### Requirements
- Xcode (latest)
- iOS 16+ (recommended)
- (Optional) OpenClaw instance for live testing

### Run Locally
1. Clone the repo
2. Open the Xcode project
3. Build & run on simulator or device

---

## 📅 Roadmap

- 📥 Inbox + Event Detail (structured + raw)
- 🔗 Pairing flow (QR/token)
- 🧠 Bridge skill (webhook sender)
- 🔔 Push notifications
- 🧩 Widgets + TTS readout
- 🔐 Policy controls (safe mode, allowlists)
- 🤖 Android & Web dashboard (future)

---

## 💬 Contributing

Contributions are welcome! If you’re adding UI or backend features:
- Follow existing architectural patterns
- Keep accessibility in mind
- Write clear component tests

---

## 📌 About

OpenClaw GUI — a companion app that makes autonomous agents *usable, safe, and delightful* on mobile.
