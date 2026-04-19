# GearSnitch Architecture Documentation

> Comprehensive architectural overview of the GearSnitch monorepo.
> Last updated: 2026-04-13

---

## 1. Overview

GearSnitch is a **fitness-and-security lifestyle platform** built as a multi-service application. The core product combines:

- **BLE gear tracking** (earbuds, trackers, bags, belts) with anti-theft alerts
- **Gym geofencing** and session tracking
- **Health & fitness tracking** (workouts, runs, nutrition, HealthKit integration)
- **E-commerce** (gear store with cart, checkout, and subscriptions)
- **Referral program** with subscription reward days

The codebase is organized as a **Turborepo monorepo** with distinct packages for the backend API, web frontend, iOS native app, realtime WebSocket service, background job worker, and shared internal libraries.

---

## 2. System Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              CLIENTS                                        │
├─────────────────────────────┬───────────────────────────────────────────────┤
│  GearSnitch iOS App         │  GearSnitch Web App                           │
│  (SwiftUI, iOS 17+)         │  (React 19 + Vite + Tailwind v4)              │
│  Primary user interface     │  Marketing site + browser dashboard           │
└───────────┬─────────────────┴─────────────────┬─────────────────────────────┘
            │ REST /api/v1                      │ REST /api/v1
            │ WebSocket /ws                     │ WebSocket /ws
            ▼                                   ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           PLATFORM LAYER                                    │
├─────────────────────┬─────────────────────┬─────────────────────────────────┤
│  API Service        │  Realtime Service   │  Worker Service                 │
│  (Express + MongoDB)│  (Socket.IO)        │  (BullMQ)                       │
│  Port: 3000         │  Port: 3002         │  Port: 3000 (health only)       │
└──────────┬──────────┴──────────┬──────────┴──────────┬──────────────────────┘
           │                     │                     │
           ▼                     ▼                     ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         DATA & MESSAGING LAYER                              │
├─────────────────────────────┬───────────────────────────────────────────────┤
│  MongoDB Atlas              │  Redis Cloud                                  │
│  (Primary database)         │  (Sessions, queues, pub/sub, presence)        │
└─────────────────────────────┴───────────────────────────────────────────────┘
```

---

## 3. Technology Stack Summary

| Package | Runtime | Framework | Language | Database | Key Libraries |
|---------|---------|-----------|----------|----------|---------------|
| `api` | Node.js 20+ | Express 4 | TypeScript 5.7 | MongoDB (Mongoose 8) | Zod, BullMQ, IORedis, Winston, Stripe |
| `web` | Browser | React 19.2 | TypeScript 6.0 | — (API consumer) | Vite 8, Tailwind v4, shadcn/ui, React Query v5 |
| `client-ios` | iOS 17+ | SwiftUI | Swift 5.9 | — (API consumer) | CoreBluetooth, CoreLocation, HealthKit, StoreKit |
| `realtime` | Node.js 20+ | Socket.IO 4 | TypeScript | MongoDB (Mongoose 8) | IORedis, Redis Adapter, Winston |
| `worker` | Node.js 20+ | BullMQ 5 | TypeScript | MongoDB (Mongoose 8) | IORedis, Winston |
| `shared` | Node.js / TS | — | TypeScript | — | Zod |

---

## 4. Package-by-Package Breakdown

### 4.1 API Service (`/api/`)

The API is the central backend hub. It exposes a REST API under `/api/v1` and handles authentication, business logic, and database persistence.

#### Entry Points
- **`src/server.ts`** — Bootstraps the server, connects MongoDB and Redis, starts HTTP, handles graceful shutdown.
- **`src/app.ts`** — Express factory: security middleware, rate limiting, route mounting, error handling.

#### Directory Structure
```
api/src/
├── server.ts               # Bootstrap
├── app.ts                  # Express app factory
├── config/index.ts         # Centralized env config
├── loaders/
│   ├── mongoose.ts         # MongoDB connection with retry
│   └── redis.ts            # Redis connection (prefix: gs:)
├── middleware/
│   ├── auth.ts             # JWT verification, RBAC, scopes
│   ├── errorHandler.ts     # Global error envelope
│   ├── rateLimiter.ts      # Redis-backed rate limiting
│   ├── validate.ts         # Zod body/param validators
│   ├── requestId.ts        # Correlation ID injection
│   └── clientRelease.ts    # Client release enforcement
├── models/                 # 28 Mongoose models
├── modules/                # 22 domain route modules
│   ├── admin/
│   ├── alerts/
│   ├── auth/
│   ├── calendar/
│   ├── calories/
│   ├── config/
│   ├── content/
│   ├── cycles/
│   ├── devices/
│   ├── dosing/
│   ├── events/
│   ├── gyms/
│   ├── health/
│   ├── notifications/
│   ├── referrals/
│   ├── runs/
│   ├── sessions/
│   ├── store/
│   ├── subscriptions/
│   ├── support/
│   ├── users/
│   └── workouts/
├── routes/index.ts         # Route aggregator
├── services/
│   ├── AuthService.ts      # OAuth, token issuance, rotation
│   ├── OrderService.ts     # Order processing logic
│   └── PaymentService.ts   # Payment handling logic
└── utils/
    ├── logger.ts
    ├── response.ts
    └── permissionsState.ts
```

#### Key Route Groups

| Domain | Base Path | Key Capabilities |
|--------|-----------|------------------|
| Auth | `/auth` | Google/Apple OAuth, refresh, logout, sessions |
| Users | `/users` | Profile, avatar, export, deletion |
| Devices | `/devices` | CRUD, status, events, locations |
| Gyms | `/gyms` | Geofenced gyms, default gym, events |
| Subscriptions | `/subscriptions` | List, validate Apple JWS receipts |
| Store | `/store` | Products, cart, orders |
| Referrals | `/referrals` | QR code, generate, redeem |
| Workouts | `/workouts` | CRUD + metrics |
| Runs | `/runs` | Start, complete, list active |
| Health | `/health` | Health check + client log ingestion |
| Health Data | `/health-data` | Apple Health metric sync, normalization, history |
| Cycles | `/cycles` | Cycle CRUD with compound plans (peptide/steroid/support/PCT), entry logging, day/month/year views |
| Dosing | `/dosing` | 15 preset substances, reconstitution calculator, syringe-unit conversion, dosing history |
| Events | `/events` | Batch event ingestion (up to 50 events, 13 types), dual-write to MongoDB + Redis Streams |
| Calendar | `/calendar` | Unified month/day aggregation of GymSession, Meal, StoreOrder, WaterLog, Workout, and Run |
| Content | `/content` | **Stub** — returns `501 Not Implemented` |
| Admin | `/admin` | **Stub** — returns `501 Not Implemented` (requires `admin` role) |

#### Authentication & Authorization

- **JWT-based session management**
  - Access tokens: 15-minute expiry
  - Refresh tokens: 7-day expiry
  - Signing: RS256 in production (asymmetric), HS256 in development
- **Redis session whitelist**
  - `session:{userId}:{jti}` validates access tokens
  - `refresh:{userId}:{jti}` validates refresh tokens
- **OAuth providers**
  - Google Sign-In via `google-auth-library`
  - Apple Sign In via JWKS verification
  - Account linking by provider ID or SHA-256 email hash
  - Provisioning guard: new accounts only from iOS/watchOS

#### Key Business Services

- **`AuthService`** — OAuth flow orchestration, token issuance, refresh rotation, logout
- **`DeviceService`** — BLE gear CRUD, auto-favorite first device, status snapshots
- **`GymService`** — Geofenced gym CRUD, auto-default first gym
- **`SubscriptionService`** — Apple StoreKit 2 JWS transaction decoding and tier mapping
- **`StoreService`** — Product catalog, cart, orders (tax + shipping computed at serialization)
- **`ReferralService`** — Code generation, redemption, qualification/reward logic

> **Dormant / Stub Modules:** `content` and `admin` are currently placeholder modules returning `501 Not Implemented`. They are reserved for future CMS and admin-dashboard functionality.

#### Testing
- **Runner:** Jest (`jest.config.cjs`)
- **Tests:** Located in `api/tests/**/*.test.cjs` (20 suites)
- **Style:** Contract/regression tests that assert source code patterns (e.g., routes wired to live services)

---

### 4.2 Web Frontend (`/web/`)

The web package is a **single-page application (SPA)** built with Vite. It serves as both the public marketing site and an authenticated browser dashboard.

#### Technology Stack
- **Framework:** React 19.2 + TypeScript 6.0
- **Build Tool:** Vite 8
- **Router:** `react-router-dom` v7
- **Styling:** Tailwind CSS v4 (CSS-native config, no `tailwind.config.js`)
- **UI Library:** shadcn/ui (`base-nova` style) + `@base-ui/react` primitives
- **State Management:** TanStack React Query v5 (server state); React Context (auth, release)
- **Payments:** Stripe Elements
- **Analytics:** Google Analytics 4 (`react-ga4`)

#### Entry Sequence
```
index.html → src/main.tsx → <App /> (providers + routes)
```

**Provider hierarchy:**
```
QueryClientProvider
  └─ AuthProvider
      └─ ReleaseProvider
          └─ BrowserRouter
              └─ Routes / Toaster
```

#### Routes

| Route | Component | Auth Required |
|-------|-----------|---------------|
| `/` | `LandingPage` | No |
| `/store/*` | `StorePage` | No (checkout requires auth) |
| `/sign-in` | `SignInPage` | No |
| `/account/*` | `AccountPage` | **Yes** |
| `/metrics` | `MetricsPage` | **Yes** |
| `/runs` | `RunMapPage` | **Yes** |
| `/privacy` | `PrivacyPolicyPage` | No |
| `/terms` | `TermsOfServicePage` | No |
| `/support` | `SupportPage` | No |
| `/delete-account` | `DeleteAccountPage` | No |
| `*` | `NotFoundPage` | No |

Protected routes are wrapped in `<ProtectedAppRoute>` which enforces `<RequireAuth>` → `<RequireSupportedRelease>`.

#### API Communication
- **`src/lib/api.ts`** — Custom `ApiClient` class wrapping `fetch`
  - Base URL: `VITE_API_URL` (default `http://localhost:3001/api/v1`)
  - Automatic 401 retry via `/auth/refresh`
  - Injects `X-Request-ID`, `X-Client-Platform: web`, version/build headers
  - Also contains cycle-tracking domain helpers (`getCycles`, `getCycleMonthSummary`, etc.)
- **`src/lib/auth.tsx`** — Session bootstrap, OAuth (Google/Apple), in-memory token storage
- **`src/lib/release.tsx`** — Version compatibility gate against `/config/app`
- **`src/lib/logger.ts`** — Client log buffering and forwarding to `POST /client-logs`
- **`src/lib/analytics.ts`** — GA4 initialization and page-view tracking
- **Additional utilities:** `release-context.ts`, `release-meta.ts`, `utils.ts`

#### Build & Deployment
- Vite injects compile-time globals from `config/release-policy.json` and git metadata:
  - `__APP_VERSION__`
  - `__APP_RELEASE_PUBLISHED_AT__`
  - `__APP_BUILD_ID__`
  - `__APP_BUILD_TIME__`
  - `__APP_GIT_SHA__`
- Output: static SPA in `web/dist/` served via nginx in production
- Static assets in `web/public/` include `icon-192.png`, `icon-512.png`, `apple-touch-icon.png`, and `favicon.svg` (PWA-ready but no formal `manifest.json` yet)

#### Testing
- **No test framework is currently configured** in the `web` package.

---

### 4.3 iOS Client (`/client-ios/`)

The iOS app is the **primary end-user interface** for GearSnitch. It is a feature-based SwiftUI application with deep native integrations.

#### Technology Stack
- **UI Framework:** SwiftUI (dark-mode-first)
- **Language:** Swift 5.9
- **Minimum iOS:** 17.0
- **Build Tool:** XcodeGen (`project.yml` generates `.xcodeproj`)
- **Dependency Manager:** Swift Package Manager
- **External Packages:** `GoogleSignIn-iOS` 9.0.0

#### App Structure
```
GearSnitch/
├── App/                    # Entry point, coordinator, root view
├── Core/                   # Services, managers, network, BLE, etc.
├── Features/               # Feature-based SwiftUI views + view models
├── Shared/                 # Models, extensions, reusable components
├── Resources/              # Assets, Info.plist, GeoJSON
└── Configuration/          # StoreKit configuration
```

#### Core Services

Core services are organized into nested subdirectories under `GearSnitch/Core/` (46 files across 17 subdirectories). The table below highlights the most critical services.

| Service | Path | Responsibility |
|---------|------|----------------|
| `APIClient` | `Core/Network/APIClient.swift` | Actor-based `URLSession` wrapper with auto token refresh on 401 |
| `AuthManager` | `Core/Auth/AuthManager.swift` | Sign In with Apple, Google Sign-In, session restore |
| `TokenStore` | `Core/Auth/TokenStore.swift` | Secure token persistence |
| `KeychainStore` | `Core/Auth/KeychainStore.swift` | Secure keychain persistence |
| `BLEManager` | `Core/BLE/BLEManager.swift` | CoreBluetooth central manager with state restoration |
| `LocationManager` | `Core/Location/LocationManager.swift` | Core Location wrapper, gym geofencing |
| `HealthKitManager` | `Core/HealthKit/HealthKitManager.swift` | Reads weight, height, BMI, calories, steps, resting HR |
| `SocketClient` | `Core/Realtime/SocketClient.swift` | Actor-based `URLSessionWebSocketTask` with backoff reconnect |
| `StoreKitManager` | `Core/Payments/StoreKitManager.swift` | In-app purchases & subscription validation |
| `ReleaseGateManager` | `Core/Config/ReleaseGateManager.swift` | Force-update/version gate enforcement |

#### Tab Structure (`MainTabView`)
1. Dashboard
2. Workouts
3. Health
4. Store
5. Profile

> The `Features/` directory contains **16 additional feature modules** beyond the main 5 tabs (Dashboard, Workouts, Health, Store, Profile), for a total of 21 feature directories. Examples: Alerts, Auth, Calendar, Calories, Cycles, DeviceMap, Devices, Gyms, Onboarding, Referrals, RunTracking, Settings, Stopwatch, Widgets, DosingCalculator, Release.

#### Native Framework Integrations

- **CoreBluetooth** — BLE scanning, connection, state restoration, disconnect alerts
- **CoreLocation** — Always-on location, geofencing (up to 20 regions), gym enter/exit
- **HealthKit** — Body metrics and workout sync to backend
- **Apple Push Notifications** — Critical alerts for device disconnects
- **StoreKit** — In-app subscriptions with JWS receipt validation
  - Products defined in `GearSnitch.storekit`:
    | Product | Price |
    |---------|-------|
    | Lifetime | $99.99 |
    | Monthly | $4.99 |
    | Annual | $59.99 |
- **WidgetKit / ActivityKit** — Home screen widgets and Live Activities for gym sessions
  - `LiveActivityManager.swift` in `Features/Widgets/` manages ActivityKit attributes and start/end/update flows
  - Note: Widget extension target is not yet configured in `project.yml`; Widget files are excluded from the main app target compile sources
- **App Intents** — `StopGymSessionIntent` for lock-screen actions
- **Universal Links / Associated Domains** — `applinks:gearsnitch.com` configured in entitlements
- **Background Modes** — 9 modes declared in `Info.plist`:
  - `bluetooth-central`, `bluetooth-peripheral`, `location`, `remote-notification`, `audio`, `fetch`, `processing`, `external-accessory`, `nearby-interaction`
- **BGTask Scheduler** — Background refresh/sync task identifiers configured for periodic updates

#### API Communication
- Base URL merged from config; deduplicates `/api/v1` if already present in base URL
- Standard headers: `Authorization`, `X-Client-Platform: ios`, `X-Client-Version`, `X-Request-ID`
- Response envelope: `{ success, data, meta, error }`
- Realtime: WebSocket to `wss://ws.gearsnitch.com/ws?token=...` with exponential backoff

#### Testing
- **GearSnitchTests** — Unit tests (3 files)
  - `RequestBuilderTests.swift`
  - `ResponseDecoderTests.swift`
  - `ReleaseGateManagerTests.swift`
- **GearSnitchUITests** — UI tests (parallelizable)

---

### 4.4 Realtime Service (`/realtime/`)

The realtime service provides **bidirectional WebSocket communication** for live updates across web and iOS clients.

#### Technology Stack
- **Transport:** Socket.IO v4
- **Scaling:** Redis Adapter + IORedis
- **Pub/Sub:** Redis (dedicated pub/sub clients)
- **Database:** Mongoose 8 (direct collection access for devices, alerts, shares)
- **Auth:** JWT verification + Redis session whitelist check

#### Key Files
- **`src/index.ts`** — Bootstraps HTTP + Socket.IO server, wires Redis pub/sub
- **`src/utils/socketAuth.ts`** — JWT socket authentication
- **`src/utils/runtimeEvents.ts`** — Redis pub/sub channel definitions and Zod envelopes

#### Namespaces & Rooms
- **Default namespace (`/`):** Authenticated sockets join `user:{userId}`
- **`/user` namespace:** Presence and alert actions
- **`/devices` namespace:** Device sync and status updates; sockets join `devices:{userId}`

#### Live Events
- `device:status:update` — Updates MongoDB, publishes to `events:device-status`
- `device:sync` — Pushes full visible device list (owner + shared)
- `alerts:ack` — Acknowledges alerts in MongoDB
- `user:presence` — Sets Redis online presence key (`presence:user:{id}`)

#### Integration
- Subscribes to 5 Redis channels published by the **Worker** service:
  - `events:device-status`
  - `events:alert`
  - `events:subscription`
  - `events:referral`
  - `events:store-order`
- Broadcasts to Socket.IO rooms so connected clients receive live updates.

#### Deployment
- **GCP Cloud Run** (`cloud_run_realtime.tf`)
  - `session_affinity = true` (required for WebSockets)
  - Scales `0–3` instances
  - Port `3001` in the Docker image, though the service code defaults to `3002` locally

---

### 4.5 Worker Service (`/worker/`)

The worker service runs **background jobs** asynchronously using BullMQ so the API remains responsive.

#### Technology Stack
- **Job Queue:** BullMQ v5
- **Redis:** IORedis
- **Database:** Mongoose 8 (native collection access)

#### Key Files
- **`src/index.ts`** — Starts health server, connects MongoDB, spins up BullMQ workers
- **`src/utils/jobRuntime.ts`** — Queue management, idempotency locking, runtime event publishing

#### Active Job Processors (7 of 13 planned)

| Queue | Processor | Purpose |
|-------|-----------|---------|
| `alert-fanout` | `alertFanout.ts` | Alert processing, push notification enqueueing |
| `push-notifications` | `pushNotification.ts` | Logs push dispatches |
| `referral-qualification` | `referralQualification.ts` | Checks qualifying subscriptions |
| `referral-reward` | `referralReward.ts` | Extends referrer subscription expiry |
| `subscription-validation` | `subscriptionValidation.ts` | Decodes Apple StoreKit JWT receipts |
| `store-order-processing` | `storeOrder.ts` | Order status advancement |
| `data-export` | `dataExport.ts` | GDPR-style data snapshot |

*Reserved (unimplemented):* `subscription-reconciliation`, `emergency-contact-alert`, `device-event-processing`, `store-inventory-sync`, `audit-export`, `analytics-events`

#### Reliability
- **Idempotency:** Every processor wraps execution in `withIdempotency()`, atomically claiming a Redis key (`gs:worker:{queueName}:{dedupeKey}`) with a 1-hour TTL.
- **Retries:** Jobs are enqueued with `attempts: 3` and exponential backoff starting at a 1-second initial delay (`enqueueJob()` in `jobRuntime.ts`).
- **Worker Config:** `concurrency: 1` and a rate limiter of `max: 10` jobs per `duration: 1000` ms (10 jobs/sec) per worker.
- **Job Cleanup:** `removeOnComplete: 50`, `removeOnFail: 100`.

#### Integration
- Publishes runtime events to Redis channels that the **Realtime** service subscribes to.
- The API package includes `bullmq` as a dependency but currently does not enqueue jobs directly from the source (integration likely in progress).

#### Deployment
- **GCP Cloud Run** (`cloud_run_worker.tf`)
  - `ingress = "INGRESS_TRAFFIC_INTERNAL_ONLY"`
  - Scales `0–2` instances

---

### 4.6 Shared Package (`/shared/`)

A TypeScript-only internal package serving as the **single source of truth** for cross-package contracts.

#### Contents
- **`src/types/index.ts`** — Domain TypeScript interfaces (`IUser`, `IDevice`, `IGym`, etc.) and `ApiResponse<T>`
- **`src/schemas/index.ts`** — Zod validation schemas (auth, device, gym, nutrition, workout, emergency contact)
- **`src/constants/index.ts`** — Business constants and const-array enums

#### Consumption
- Consumed by `api`, `worker`, and `realtime` via TypeScript path mapping (`@gearsnitch/shared` → `../shared/src`)
- The `web` frontend **does not currently use `@gearsnitch/shared`**

---

## 5. Infrastructure & DevOps

### 5.1 Cloud Platform
All production workloads run on **Google Cloud Platform**.

### 5.2 Terraform (`/infrastructure/terraform/`)

| File | Resources |
|------|-----------|
| `main.tf` | GCS backend, GCP APIs, service account, IAM |
| `artifact_registry.tf` | Docker repository with cleanup policy |
| `secret_manager.tf` | 16 secrets (MongoDB, Redis, JWT keys, OAuth, APNS, Stripe, etc.) |
| `cloud_run_api.tf` | `gearsnitch-api` — 0–5 instances, 512Mi |
| `cloud_run_web.tf` | `gearsnitch-web` — 0–3 instances, nginx on port 8080 |
| `cloud_run_worker.tf` | `gearsnitch-worker` — 0–2 instances, internal ingress only |
| `cloud_run_realtime.tf` | `gearsnitch-realtime` — 0–3 instances, session affinity |
| `monitoring.tf` | Alert policies: 5xx rate, p95 latency, worker backlog |

> **Note:** The three monitoring alert policies currently have empty notification channels (`notification_channels = []`).

**Additional files present but not listed above:** `outputs.tf`, `providers.tf`, `variables.tf`, `terraform.tfvars`, `tfplan-foundation`, `tfplan-full`, and `environments/`.

### 5.3 Docker (`/infrastructure/docker/`)

| Dockerfile | Service | Notes |
|------------|---------|-------|
| `api.Dockerfile` | API | Multi-stage Node 20 Alpine, exposes port 3000 |
| `worker.Dockerfile` | Worker | Multi-stage Node 20 Alpine, no exposed port |
| `realtime.Dockerfile` | Realtime | Multi-stage Node 20 Alpine, exposes port 3001 |
| `web.Dockerfile` | Web | Node 20 Alpine builder, `nginx:alpine` runner serving static SPA |
| `nginx.conf` | — | Standalone nginx config (currently unused by `web.Dockerfile`, which inlines its own config) |

### 5.4 CI/CD

**GitHub Actions — `ci.yml`**
- Runs on every PR/push: `lint`, `type-check`, `test`, `build`

**GitHub Actions — `deploy.yml`**
- Triggered on `push` to `main`
- Authenticates to GCP via Workload Identity Federation
- Resolves live Cloud Run URLs and 5 GCP secrets (`google-oauth-client-id`, `apple-service-id`, `apple-redirect-uri`, and placeholders for Stripe/Apple Pay configs)
- Includes placeholder-guard logic to strip dummy values before injecting them into the web build
- Submits Cloud Build pipeline

**Cloud Build — `cloudbuild.yaml`**
- Uses `E2_HIGHCPU_8` machine type for faster parallel builds
- Configured with `logging: CLOUD_LOGGING_ONLY`
- Builds all 4 Docker images in parallel
- Pushes to Artifact Registry
- Deploys each to Cloud Run sequentially

### 5.5 Monorepo Configuration

**Root `package.json`**
- Package manager: `npm@11.12.1`
- Node engine: `>=20.0.0`
- Workspaces: `api`, `web`, `shared`, `worker`, `realtime`

**`turbo.json`**
```json
{
  "globalDependencies": ["**/.env.*local"],
  "tasks": {
    "build": { "dependsOn": ["^build"], "outputs": ["dist/**"] },
    "lint":   { "dependsOn": ["^build"] },
    "type-check": { "dependsOn": ["^build"] },
    "dev":    { "cache": false, "persistent": true },
    "test":   { "dependsOn": ["build"] }
  }
}
```

---

## 6. Key Data Flows

### 6.1 Device Disconnect Alert
```
[iOS App]
   BLE disconnect detected
   → POST /api/v1/alerts/device-disconnected
   → MongoDB: alerts collection
   → (future) enqueue alert-fanout job
[Worker]
   processes alert-fanout
   → publishes events:alert to Redis
[Realtime]
   subscribes to events:alert
   → broadcasts alert:new to user:{userId} room
[iOS / Web]
   receives live alert notification
```

### 6.2 Device Status Update
```
[iOS App]
   emits device:status:update on /devices namespace
[Realtime]
   updates MongoDB devices collection
   → publishes events:device-status to Redis
   → broadcasts device:status to devices:{userId} room
[Other Clients]
   receive live status update
```

### 6.3 Referral Reward
```
[API or Worker]
   detects qualifying subscription
   → enqueue referral-qualification
[Worker]
   referral-qualification passes
   → enqueue referral-reward
   → extends referrer subscription expiry in MongoDB
   → publishes events:referral to Redis
[Realtime]
   subscribes to events:referral
   → broadcasts referral:update to referrer's socket room
```

### 6.4 Subscription Validation
```
[iOS App]
   completes StoreKit purchase
   → POST /subscriptions/validate-apple (JWS receipt)
[API or Worker]
   → enqueue subscription-validation
[Worker]
   decodes Apple JWT, upserts Subscription record
   → publishes events:subscription to Redis
[Realtime]
   → broadcasts subscription:update to user socket room
```

---

## 7. Development Conventions

### 7.1 Backend Conventions
- **Envelope-based JSON responses:** `{ success, data, error }`
- **Zod validation** at the HTTP edge (`validate.ts` middleware)
- **Service-oriented architecture:** routes → services → models
- **Redis-backed session state** for distributed deployments
- **Path mapping** to `@gearsnitch/shared` for types/schemas

### 7.2 Frontend Conventions
- **Web:** Dark-first aesthetic, `cn()` utility from `clsx` + `tailwind-merge`, path alias `@/*`
- **iOS:** Feature-based folder structure, `@MainActor` for UI coordination, Swift Actors for network layer

### 7.3 Shared Conventions
- All backend Dockerfiles compile `shared/` before the service code
- Secrets are fully externalized to Google Secret Manager
- No secrets baked into Docker images

---

## 8. Testing Matrix

| Package | Framework | Test Location | Coverage Notes |
|---------|-----------|---------------|----------------|
| `api` | Jest | `api/tests/**/*.test.cjs` | 21 contract/regression test suites |
| `web` | — | — | No tests configured |
| `client-ios` | XCTest | `GearSnitchTests/` | 3 unit test files |
| `realtime` | — | — | No tests |
| `worker` | — | — | No tests |
| `shared` | — | — | No tests |

---

## 9. Key Files Quick Reference

| File | Purpose |
|------|---------|
| `api/src/server.ts` | API bootstrap |
| `api/src/app.ts` | Express factory |
| `api/src/services/AuthService.ts` | Core auth/OAuth logic |
| `web/src/App.tsx` | Web route tree |
| `web/src/lib/api.ts` | HTTP client |
| `client-ios/GearSnitch/App/RootView.swift` | iOS root view |
| `client-ios/GearSnitch/Core/Network/APIClient.swift` | iOS network layer |
| `realtime/src/index.ts` | Socket.IO server bootstrap |
| `worker/src/index.ts` | BullMQ worker bootstrap |
| `shared/src/index.ts` | Shared exports |
| `turbo.json` | Turborepo pipeline |
| `infrastructure/cloudbuild/cloudbuild.yaml` | Deployment pipeline |
| `config/release-policy.json` | App version source of truth |
| `docs/HANDOFF.md` | Live infrastructure URLs and credentials |

---

## 10. Related Documentation

- [`index.md`](./index.md) — Documentation hub and quick links
- [`getting-started.md`](./getting-started.md) — Developer onboarding guide
- [`HANDOFF.md`](./HANDOFF.md) — Live infrastructure URLs, credentials, and launch checklist
- [`device-pairing-architecture.md`](./device-pairing-architecture.md) — BLE discovery and account persistence deep-dive
- [`/conductor/`](../conductor/) — File-backed project management and loop workflow
