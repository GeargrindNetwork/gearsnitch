# GearSnitch Documentation

Welcome to the GearSnitch documentation hub.

## 📖 Core Documentation

| Document | Description |
|----------|-------------|
| **[Getting Started](./getting-started.md)** | Developer onboarding guide: prerequisites, env setup, local development, common commands |
| **[Architecture](./architecture.md)** | Comprehensive system architecture, package breakdowns, data flows, and technology stacks |
| **[HANDOFF.md](./HANDOFF.md)** | Live infrastructure URLs, credentials, launch checklist, and project state |
| **[Device Pairing Architecture](./device-pairing-architecture.md)** | Deep-dive into BLE discovery, account persistence, and pinning semantics |
| **[Apple Sign In Manual](./apple-sign-in-manual.md)** | End-to-end runbook for Apple login across iOS, web, backend, Apple Developer, and GCP secrets |

## 🚀 Quick Links

### Development
- [API Service](../api/) — Express backend (`api/src/server.ts`)
- [Web Frontend](../web/) — React SPA (`web/src/App.tsx`)
- [iOS Client](../client-ios/) — SwiftUI app (`client-ios/project.yml`)
- [Realtime Service](../realtime/) — Socket.IO server (`realtime/src/index.ts`)
- [Worker Service](../worker/) — BullMQ background jobs (`worker/src/index.ts`)
- [Shared Package](../shared/) — Cross-package types and schemas

### Infrastructure
- [Terraform](../infrastructure/terraform/) — GCP infrastructure as code
- [Docker](../infrastructure/docker/) — Multi-stage service images
- [Cloud Build](../infrastructure/cloudbuild/) — CI/CD pipeline
- [GitHub Workflows](../.github/workflows/) — PR validation and deployment automation

### Project Management
- [Conductor](../conductor/) — File-backed `/loop` workflow and track registry
- [Scripts](../scripts/) — Development utilities, launch checkers, and log streaming
- [Release Policy](../config/release-policy.json) — App version source of truth

## 🏗️ System at a Glance

```
┌─────────────┐      ┌─────────────┐
│  iOS App    │      │  Web App    │
│  (SwiftUI)  │      │  (React)    │
└──────┬──────┘      └──────┬──────┘
       │                    │
       └────────┬───────────┘
                │ REST /api/v1
                │ WebSocket /ws
       ┌────────┴───────────┐
       ▼                    ▼
┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│     API     │      │  Realtime   │      │    Worker   │
│  (Express)  │◄────►│ (Socket.IO) │◄────►│   (BullMQ)  │
└──────┬──────┘      └──────┬──────┘      └──────┬──────┘
       │                    │                    │
       └────────┬───────────┴────────┬───────────┘
                ▼                    ▼
        ┌───────────────┐    ┌───────────────┐
        │  MongoDB Atlas │    │  Redis Cloud  │
        └───────────────┘    └───────────────┘
```

## 📝 Contributing to Docs

When making architectural changes, please update:
1. This index if you add new documents
2. [`architecture.md`](./architecture.md) for any package or infrastructure changes
3. [`HANDOFF.md`](./HANDOFF.md) for infrastructure URLs, credentials, or launch state changes
