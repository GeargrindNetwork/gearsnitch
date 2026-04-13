# Getting Started

> Developer onboarding guide for the GearSnitch monorepo.

---

## Prerequisites

- **Node.js** `>=20.0.0`
- **npm** `>=11.12.1`
- **MongoDB** (local or Atlas)
- **Redis** (local or cloud)
- **Xcode** `15.0+` (for iOS development)
- **Swift** `5.9+`
- **Google Cloud SDK** (for deployments)

---

## Repository Structure

```
GearSnitch/
├── api/                    # Express backend
├── web/                    # React frontend
├── client-ios/             # SwiftUI iOS app
├── realtime/               # Socket.IO service
├── worker/                 # BullMQ background worker
├── shared/                 # Internal shared types/schemas
├── infrastructure/         # Terraform, Docker, Cloud Build
├── conductor/              # File-backed project management
├── config/                 # Release policy, shared config
├── scripts/                # Dev utilities
└── docs/                   # Documentation
```

---

## Installation

```bash
# Install all workspace dependencies
npm install
```

---

## Environment Setup

Copy and fill in environment files for each service:

```bash
cp api/.env.example api/.env
cp web/.env.example web/.env
```

### Required Variables (api/.env)

| Variable | Purpose |
|----------|---------|
| `PORT` | API server port (default: `3001`) |
| `MONGODB_URI` | MongoDB connection string |
| `REDIS_URL` | Redis connection string |
| `JWT_PRIVATE_KEY` | JWT signing key |
| `JWT_PUBLIC_KEY` | JWT verification key |
| `GOOGLE_CLIENT_ID` | Google OAuth client ID |
| `APPLE_SERVICE_ID` | Apple Sign In service ID |
| `STRIPE_SECRET_KEY` | Stripe API key |
| `STRIPE_WEBHOOK_SECRET` | Stripe webhook signing secret |

### Required Variables (web/.env)

| Variable | Purpose |
|----------|---------|
| `VITE_API_URL` | Backend API base URL |
| `VITE_WS_URL` | Realtime WebSocket URL |
| `VITE_GOOGLE_CLIENT_ID` | Google OAuth client ID |
| `VITE_APPLE_SERVICE_ID` | Apple Sign In service ID |
| `VITE_APPLE_REDIRECT_URI` | Apple OAuth redirect URI |

---

## Running Locally

### Start All Backend Services

```bash
# Terminal 1: API
npm run dev:api

# Terminal 2: Realtime service
npm run dev:realtime

# Terminal 3: Worker service
npm run dev:worker
```

### Start Web Frontend

```bash
npm run dev:web
```

### Start iOS App

```bash
# Generate Xcode project from project.yml
cd client-ios
xcodegen generate

# Open in Xcode
open GearSnitch.xcodeproj
```

Then build and run the `GearSnitch` target on a simulator or device.

---

## Common Commands

### Build

```bash
# Build all packages
npm run build

# Build specific package
npm run build:api
npm run build:web
npm run build:shared

# Build worker or realtime (via workspace flag)
npm run build --workspace=worker
npm run build --workspace=realtime
```

### Lint & Type Check

```bash
# All packages
npx turbo run lint
npx turbo run type-check
```

### Test

```bash
# All packages
npx turbo run test

# API only
npm run test --workspace=api
```

### Launch Preflight Check

```bash
node scripts/check-launch-config.mjs
```

Performs 21 specific validation checks across three categories:
- **Web environment** (`web/.env.example`): verifies 4 required keys (`VITE_API_URL`, `VITE_WS_URL`, `VITE_GOOGLE_CLIENT_ID`, `VITE_APPLE_SERVICE_ID`)
- **API environment** (`api/.env.example`): verifies 12 required keys (`PORT`, `MONGODB_URI`, `REDIS_URL`, `JWT_PRIVATE_KEY`, `JWT_PUBLIC_KEY`, `GOOGLE_CLIENT_ID`, `APPLE_SERVICE_ID`, `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `ENCRYPTION_KEY`, `APNS_KEY_ID`, `APNS_KEY`)
- **iOS configuration**: verifies `Info.plist` URL schemes, Google Sign-In reversed client ID, remote-notification background mode, APS environment, and Sign in with Apple entitlement

Exits non-zero if any required key or configuration is missing.

---

## Log Streaming

```bash
# Unified error-log tailer
npm run logs:feed
```

`scripts/feed-error-logs.sh` supports multiple modes:
- `summary` (default) — quick overview of recent errors
- `ios-stream` — live tail of iOS device logs
- `ios-last` — last N iOS log lines
- `api-errors` — recent API error logs
- `api-follow` — follow API error logs in real time

---

## Working with the Conductor (`/loop`)

The project uses a file-backed workflow system in `conductor/`.

```bash
# Check track status
node scripts/loop.mjs status

# Show next actions
node scripts/loop.mjs next

# Show a specific track
node scripts/loop.mjs show <track-id>
```

See [`conductor/workflow.md`](../conductor/workflow.md) for the full 6-step loop contract.

---

## Local Development URLs

| Service | Local URL |
|---------|-----------|
| API | `http://localhost:3001` |
| Web | `http://localhost:5173` |
| Realtime | `http://localhost:3002` |
| Worker Health | `http://localhost:3000/health` |

---

## API Quick Reference

All API routes are mounted under `/api/v1`.

### Health Check
```bash
curl http://localhost:3001/api/v1/health
```

### Authentication
```bash
# Google OAuth
curl -X POST http://localhost:3001/api/v1/auth/oauth/google \
  -H "Content-Type: application/json" \
  -d '{"idToken": "...", "clientId": "..."}'

# Apple OAuth
curl -X POST http://localhost:3001/api/v1/auth/oauth/apple \
  -H "Content-Type: application/json" \
  -d '{"identityToken": "...", "authorizationCode": "..."}'
```

---

## Deployment

Deployments are automated via GitHub Actions + Google Cloud Build.

1. Merge to `main`
2. GitHub Actions `deploy.yml` triggers
3. Cloud Build builds Docker images and deploys to Cloud Run

See [`infrastructure/cloudbuild/cloudbuild.yaml`](../infrastructure/cloudbuild/cloudbuild.yaml) for the full pipeline.

---

## Release Policy (`config/release-policy.json`)

`config/release-policy.json` is the source of truth for app version metadata. It is consumed by the web Vite build to inject compile-time globals.

| Field | Type | Purpose |
|-------|------|---------|
| `version` | string | Current app version (e.g., `1.0.0`) |
| `minimumSupportedVersion` | string | Oldest version still allowed to use the app |
| `forceUpgrade` | boolean | If `true`, outdated clients are hard-blocked |
| `publishedAt` | ISO date | Release publish timestamp |
| `releaseNotes` | string[] | Array of release note bullets |
| `environment` | string | Deployment environment (`development`, `staging`, `production`) |

---

## Troubleshooting

### MongoDB Connection Issues
- Ensure MongoDB is running locally or your `MONGODB_URI` points to a reachable instance
- Check IP allowlist if using MongoDB Atlas

### Redis Connection Issues
- Ensure Redis is running locally or your `REDIS_URL` is correct
- The API, Worker, and Realtime services all depend on Redis

### iOS Build Issues
- Run `xcodegen generate` in `client-ios/` if project structure seems out of sync
- Ensure you have the correct development team and signing certificates selected in Xcode

### Turborepo Cache Issues
```bash
# Clear turbo cache
rm -rf .turbo
rm -rf */.turbo
rm -rf */dist
```

---

## Next Steps

- Read the [Architecture Overview](./architecture.md) to understand the system
- Check [`HANDOFF.md`](./HANDOFF.md) for live infrastructure details
- Explore the [Conductor](../conductor/) for active tracks and project state
