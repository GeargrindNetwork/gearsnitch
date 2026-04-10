# GearSnitch — Session Handoff & Action Plan

**Date:** April 10, 2026
**Session:** Built from zero to deployed in one session (~12 hours)
**Repo:** https://github.com/GeargrindNetwork/gearsnitch (26 commits on main)

---

## Current State

### Infrastructure — All Live

| System | Status | URL / Details |
|--------|--------|---------------|
| **Website** | 200 LIVE | https://gearsnitch.com |
| **Privacy Policy** | 200 LIVE | https://gearsnitch.com/privacy |
| **Terms of Service** | 200 LIVE | https://gearsnitch.com/terms |
| **Support** | 200 LIVE | https://gearsnitch.com/support |
| **Delete Account** | 200 LIVE | https://gearsnitch.com/delete-account |
| **API** | 200 LIVE | https://api.gearsnitch.com (most routes return 501 stubs) |
| **Realtime** | 200 LIVE | https://gearsnitch-realtime-6okk4hvbdq-uc.a.run.app |
| **Worker** | Deployed | https://gearsnitch-worker-6okk4hvbdq-uc.a.run.app |
| **MongoDB Atlas** | Connected | Cluster: gearsnitch-dev (M0, us-east-1), DB user: gearsnitch-api |
| **Redis Cloud** | Connected | Shared with GGV3, key prefix `gs:` |
| **Stripe** | 5 products | HUSTLE, HWMF, BABY MOMMA, BPC-157, GearSnitch Annual |
| **GCP Project** | gearsnitch | Billing linked, all APIs enabled |
| **Cloudflare** | Active | Worker proxy routing gearsnitch.com, api.gearsnitch.com, ws.gearsnitch.com |
| **Artifact Registry** | 4 images | api, web, worker, realtime pushed |
| **Secret Manager** | 18 secrets | JWT keys, MongoDB, Redis, Stripe, OAuth, Apple, encryption |
| **TestFlight** | Build uploaded | v1.0.0 (build 3), App ID: 6761991800 |

### Credentials & IDs

| Resource | Value |
|----------|-------|
| GCP Project ID | gearsnitch (417098988395) |
| Atlas Project ID | 69d839cf8e17dcef631a0102 |
| Atlas Cluster | gearsnitch-dev.sqrsvda.mongodb.net |
| Atlas DB User | gearsnitch-api / 2Z8j3CmLRUFJkjPFXavbqAab |
| Redis URL | redis://default:cmZeD8lzisK0zXbbQlBERDgeLiAXushR@redis-19490.c259.us-central1-2.gce.cloud.redislabs.com:19490 |
| Cloudflare Zone ID | 067b7ff416f9a4ce060c4857ed919203 |
| Cloudflare API Key | 21a40ab8ac3c2670a1139cb52cf6b1a0cff39 (Global key, X-Auth-Email: shawnfrazier@gmail.com) |
| Apple Team ID | TUZYDM227C |
| Bundle ID | com.gearsnitch.app |
| Stripe Account | acct_1Rsa7dFs2X4Gu0V4 (shared with Geargrind, metadata[project]=gearsnitch) |
| Stripe Webhook | we_1TKXVgFs2X4Gu0V4sBumEnad → api.gearsnitch.com |
| Stripe Webhook Secret | whsec_KeRSSwFzIvrX6GAQF7YD7ogjZk46sTVf |
| Admin Account | admin@geargrind.net (in MongoDB users collection) |

### Stripe Products

| Product | ID | Price ID | Amount |
|---------|------|----------|--------|
| HUSTLE (monthly) | prod_UJJReyQEgKAUbc | price_1TKgoBFs2X4Gu0V4nleDKfbO | $4.99/mo |
| HWMF (annual) | prod_UJJRizOO8V00CG | price_1TKgoLFs2X4Gu0V40BHQBsNj | $60/yr |
| BABY MOMMA (lifetime) | prod_UJJR2tOPls2wsA | price_1TKgoUFs2X4Gu0V4ZxLMiAz5 | $99 one-time |
| BPC-157 Peptide | prod_UJ9oreLCEZJv67 | price_1TKXVNFs2X4Gu0V4OzgXnzDv | $49.99 |
| GearSnitch Annual (legacy) | prod_UJ9obpqoAcL0gG | price_1TKXV9Fs2X4Gu0V4siH5pmcj | $29.99/yr |

---

## Codebase Structure

```
gearsnitch/ (26 commits, ~300 files, ~40k lines)
├── api/                          # Express TypeScript API
│   ├── src/
│   │   ├── config/               # Env var config
│   │   ├── loaders/              # MongoDB + Redis connections
│   │   ├── middleware/           # Auth (JWT RS256), rate limiter, Zod validation, error handler
│   │   ├── models/               # 23 Mongoose models with indexes
│   │   ├── modules/              # 20 route modules (16 original + sessions, calendar, events, dosing)
│   │   ├── services/             # AuthService (Google+Apple), PaymentService (Stripe), OrderService, subscriptionService
│   │   ├── routes/               # Main router mounting all modules
│   │   └── utils/                # Logger (Winston), response envelope
│   └── .env                      # Local env with real MongoDB URI
├── web/                          # Vite + React + shadcn/ui + GA4
│   ├── src/
│   │   ├── components/           # shadcn UI + layout + account + checkout
│   │   ├── pages/                # Landing, Store, Account, Privacy, Terms, Support, DeleteAccount, 404
│   │   └── lib/                  # API client, analytics
├── shared/                       # Types, Zod schemas, constants
├── worker/                       # BullMQ (13 queues, 7 job processors — stubs)
├── realtime/                     # Socket.IO + Redis adapter
├── client-ios/                   # Native SwiftUI iOS app
│   ├── GearSnitch/
│   │   ├── App/                  # GearSnitchApp, AppDelegate, AppCoordinator, RootView, MainTabView
│   │   ├── Core/
│   │   │   ├── Auth/             # AuthManager, GoogleSignInManager, KeychainStore, TokenStore, SessionManager
│   │   │   ├── BLE/              # BLEManager (state restoration), BLESignalMonitor (5-level RSSI),
│   │   │   │                     # PanicAlarmManager (vibration+audio+AirPods), BLEAlarmSoundPlayer,
│   │   │   │                     # BLEScanner, BLEDevice, BLEStateObserver
│   │   │   ├── Location/         # LocationManager, GeofenceManager, GymRegionMonitor
│   │   │   ├── HealthKit/        # HealthKitManager, Permissions, SyncService
│   │   │   ├── Payments/         # ApplePayManager (PassKit), StoreKitManager (StoreKit 2),
│   │   │   │                     # PaymentService, PaymentModels, ApplePayButton
│   │   │   ├── Realtime/         # SocketClient, SocketEventHandler, RealtimeEventBus
│   │   │   ├── Persistence/      # SwiftData (LocalDevice, LocalGym, OfflineOperation), OfflineQueue
│   │   │   ├── Session/          # GymSessionManager (geofence auto-prompt, App Group)
│   │   │   ├── MeshChat/         # MeshNetworkManager (MultipeerConnectivity)
│   │   │   ├── Permissions/      # PermissionGateManager (runtime checks)
│   │   │   ├── Analytics/        # AnalyticsClient (23 event types)
│   │   │   ├── Config/           # RemoteConfigClient, FeatureFlags
│   │   │   └── Notifications/    # PushNotificationHandler, NotificationPermissionManager
│   │   ├── Features/
│   │   │   ├── Onboarding/       # 11-step gated flow (sign-in, subscriptions, permissions, gym, device)
│   │   │   ├── Auth/             # SignInView, SignInViewModel
│   │   │   ├── Dashboard/        # DashboardView with session card, signal indicators, calendar link
│   │   │   ├── Devices/          # List, detail, pairing (6 files)
│   │   │   ├── Gyms/             # List, detail, AddGymView (full-screen MapKit + search), MapSearchManager
│   │   │   ├── Alerts/           # List, detail, acknowledge (3 files)
│   │   │   ├── Workouts/         # Active session, history, detail (5 files)
│   │   │   ├── Health/           # Dashboard, HealthKit sync, metrics log, BMI calculator
│   │   │   ├── Calories/         # Daily summary, meal logging, nutrition goals, water tracker
│   │   │   ├── Referrals/        # QR code (CIFilter), sharing, history
│   │   │   ├── Store/            # Catalog, cart, checkout (Apple Pay + card), order history
│   │   │   ├── Profile/          # Profile (Apple Health import), emergency contacts, subscription
│   │   │   ├── Settings/         # Notification preferences
│   │   │   ├── Stopwatch/        # Timer with laps
│   │   │   ├── Calendar/         # HeatmapCalendar (5-level mint gradient)
│   │   │   ├── DosingCalculator/ # 15 substances, syringe units, dose history
│   │   │   ├── MeshChat/         # P2P anonymous gym chat
│   │   │   ├── DeviceMap/        # MapKit device location tracker
│   │   │   └── Widgets/          # WidgetKit (3 widgets), Live Activity, App Intents
│   │   ├── Shared/               # Components (buttons, badges, signal, empty state), extensions, models
│   │   └── Resources/            # Assets.xcassets (AppIcon 13 sizes + Logo), Info.plist, GeoJSON
│   ├── project.yml               # XcodeGen project definition
│   └── GearSnitch.xcodeproj      # Generated Xcode project
├── infrastructure/
│   ├── terraform/                # 11 .tf files (Cloud Run x4, secrets, monitoring, artifact registry)
│   ├── docker/                   # 4 Dockerfiles + nginx.conf
│   └── cloudbuild/               # cloudbuild.yaml for CI/CD
├── .github/workflows/            # ci.yml + deploy.yml
└── docs/                         # Architecture doc, plans, decisions
```

---

## What's Actually End-to-End Functional

| Feature | iOS | Backend | Web | E2E Working? |
|---------|-----|---------|-----|-------------|
| Website serving | — | — | Yes | **YES** |
| Compliance pages (privacy/terms/support/delete) | — | — | Yes | **YES** |
| iOS onboarding (11-step flow) | Yes | Partial | — | **iOS only** |
| BLE device scanning | Yes | — | — | **iOS only** |
| Progressive BLE alarm | Yes | — | — | **iOS only** (needs device testing) |
| Panic alarm (vibration + sound) | Yes | — | — | **iOS only** |
| Mesh chat (P2P) | Yes | — | — | **iOS only** (between 2 devices) |
| Dosing calculator (stateless) | Yes | Yes | — | **YES** |
| Stopwatch | Yes | — | — | **iOS only** |
| Auth (Google OAuth) | Yes | Yes (AuthService) | — | **Partial** (needs Google client ID) |
| Auth (Apple Sign-In) | Yes | Yes (JWKS verified) | — | **Partial** (needs Apple config) |
| Apple Pay | Yes | Yes (Stripe) | Yes (Elements) | **No** (needs Merchant ID cert) |
| StoreKit subscriptions | Yes | Yes (JWS validate) | — | **No** (needs StoreKit config) |
| Gym CRUD | Yes (UI) | **501 stub** | — | **No** |
| Device CRUD | Yes (UI) | **501 stub** | — | **No** |
| User profile | Yes (UI) | **501 stub** | Yes (UI) | **No** |
| Sessions | Yes (UI) | Routes built | — | **Partial** (routes exist but not deployed) |
| Calendar | Yes (UI) | Routes built | Yes (UI) | **Partial** |
| Health metrics | Yes (UI) | **501 stub** | — | **No** |
| Calories/meals | Yes (UI) | **501 stub** | — | **No** |
| Workouts | Yes (UI) | **501 stub** | — | **No** |
| Store products | Yes (UI) | **501 stub** | Yes (UI) | **No** |
| Referrals | Yes (UI) | **501 stub** | — | **No** |
| Event logging | — | Routes built | — | **Partial** |
| Push notifications | Yes (handler) | Token registration | — | **No** (needs APNs cert) |
| WebSocket realtime | Yes (client) | Yes (server) | — | **Deployed but untested** |
| Run tracking | **Not built** | **Not built** | **Not built** | **No** |
| Web metrics dashboard | **N/A** | **Not built** | **Not built** | **No** |

---

## Launch Action Plan — Priority Order

### P0: Backend Service Layer (blocks everything)

These API routes currently return 501. Need real Mongoose CRUD operations.

| Module | File to Create/Update | Routes |
|--------|-----------------------|--------|
| **Gyms** | `api/src/services/GymService.ts` | CRUD + evaluate-location |
| **Devices** | `api/src/services/DeviceService.ts` | CRUD + status + bulk-sync |
| **Users** | `api/src/services/UserService.ts` | GET/PATCH /me + preferences |
| **Health** | `api/src/services/HealthService.ts` | Metrics CRUD + Apple sync |
| **Calories** | `api/src/services/CalorieService.ts` | Daily + meals + water + goals |
| **Workouts** | `api/src/services/WorkoutService.ts` | CRUD + exercises |
| **Referrals** | `api/src/services/ReferralService.ts` | Code + QR + claim + reward |
| **Store** | `api/src/services/StoreService.ts` | Products + cart + checkout |
| **Notifications** | `api/src/services/NotificationService.ts` | Token registration + preferences |
| **Config** | Update existing | Return real feature flags |

Each service: import Mongoose model, implement CRUD, wire into existing route.
Then: redeploy API via Cloud Build.

### P1: Enhanced BLE Alarm (iOS)

**Files to modify:**
- `Core/BLE/BLESignalMonitor.swift` — Add half-strength detection with per-device baseline calibration
- `Core/BLE/PanicAlarmManager.swift` — Add "End Session" vs "Lost Gear" interactive notification
- `Core/BLE/BLEAlarmSoundPlayer.swift` — Add `.mixWithOthers` + `.duckOthers` for chirp over music
- `Core/BLE/BLEManager.swift` — Store GPS at disconnect, favorite device priority

**New files:**
- `Core/BLE/HapticPatternEngine.swift` — CHHapticEngine custom patterns for progressive vibration
- `Core/BLE/DeviceBatteryMonitor.swift` — BLE Battery Service (0x180F) reading

**Signal → Response mapping:**
```
100-50% RSSI: No alert
50% RSSI:     Phone vibrate (light) + slow chirp (1/3s) + AirPods chirp over music
30% RSSI:     Phone vibrate (medium) + faster chirp (1/2s) + AirPods faster chirp
15% RSSI:     Phone vibrate (heavy) + rapid chirp (1/s) + AirPods rapid chirp
Disconnect:   Notification: "End Session" | "Lost Gear"
              Lost Gear → max volume panic + GPS snapshot
              End Session → silent disarm + log session end
```

### P1: Run Tracking (NEW — iOS + Backend + Web)

**iOS files to create:**
- `Core/RunTracking/RunTrackingManager.swift` — CoreLocation continuous GPS, polyline recording, auto-pause
- `Core/RunTracking/RunSession.swift` — Model: id, startedAt, endedAt, distance, duration, pace, coordinates
- `Features/RunTracking/ActiveRunView.swift` — Live map with polyline, pace/distance/duration overlay
- `Features/RunTracking/RunHistoryView.swift` — List of past runs
- `Features/RunTracking/RunDetailView.swift` — Map with pace-colored polyline, splits

**Backend files:**
- `api/src/models/Run.ts` — userId, startedAt, endedAt, distance, duration, polyline (encoded), pace, calories
- `api/src/modules/runs/routes.ts` — POST start, PATCH end (with polyline), GET list, GET detail

**Web files:**
- `web/src/pages/RunMapPage.tsx` — Interactive run map viewer
- `web/src/components/maps/RunPolyline.tsx` — Leaflet/MapKit JS polyline renderer

### P1: Favorite/Pin Devices

- Add `isFavorite: Boolean` to Device model (MongoDB + iOS)
- Star toggle on DeviceListView
- Favorites shown first, get priority RSSI monitoring
- Device nickname editing

### P1: Session Logging & Calendar

- All session start/end times logged to GymSession collection
- "End Session" notification creates the record
- Calendar shows gym sessions (emerald) + runs (cyan) + purchases (gold dots)
- Metrics: average gym time, streak, total sessions

### P2: Web Metrics Dashboard

**New web page:** `web/src/pages/MetricsPage.tsx`
- Average gym session duration (rolling 30 days)
- Total sessions this week/month
- Current streak + longest streak
- Total distance run
- Peak workout hours chart
- Weekly trend arrows
- Device status cards with last-seen GPS
- Run map gallery

### P2: Redeploy API + Web

After backend service layer is implemented:
1. `cd /Users/shawn/Documents/GearSnitch && gcloud builds submit --project=gearsnitch --region=us-central1 --config=infrastructure/cloudbuild/cloudbuild.yaml --substitutions=_TAG=v1.0.0`
2. This rebuilds all 4 Docker images and deploys to Cloud Run

### P3: Manual Setup (Apple Developer + Google)

| Task | Where |
|------|-------|
| Enable "Sign In with Apple" for App ID com.gearsnitch.app | developer.apple.com/account |
| Create Apple Merchant ID (merchant.com.gearsnitch.app) | developer.apple.com/account |
| Upload Stripe payment processing cert for Merchant ID | dashboard.stripe.com |
| Create APNs push notification key | developer.apple.com/account |
| Create Google OAuth client ID for iOS | console.cloud.google.com/apis/credentials?project=gearsnitch |
| Add `gearsnitch://oauth/google/callback` as redirect URI | Same |
| Create StoreKit products in App Store Connect | appstoreconnect.apple.com |
| Add internal testers to TestFlight | appstoreconnect.apple.com |

### P3: Missed Opportunity Features (Post-Launch)

1. Workout summary push notification after session ends
2. Weekly digest notification (Sunday) with gym stats
3. Achievement badges (7-day streak, 30-day, 100 sessions, first run, first purchase)
4. Social sharing of run maps as images
5. Rest timer between sets (30s, 60s, 90s, custom)
6. Device battery level monitoring (BLE Battery Service 0x180F)
7. Signal history chart per device (RSSI over last 24h)
8. Gym check-in count via mesh ("3 users here")
9. Auto-pause run when stopped >60s
10. Split metrics for runs (per-mile pace)
11. App Store review prompting after qualifying events
12. Apple Watch companion app
13. Dating feature (swipe/match/chat) — backlog

---

## Architecture Decisions Made

1. **Native SwiftUI** over Expo/React Native — required for CoreBluetooth state restoration, HealthKit, background BLE
2. **OAuth-only auth** — no passwords, Apple + Google Sign-In only
3. **Shared Redis** with GGV3 using `gs:` key prefix — cost-effective for dev
4. **Cloudflare Worker proxy** instead of Cloud Run domain mapping — org policy blocked allUsers, domain verification would be needed
5. **Separate Stripe products** with metadata tagging instead of separate account — simpler management
6. **XcodeGen** for project generation — avoids merge conflicts in .xcodeproj
7. **StaticConfiguration widgets** excluded from main target — need separate Widget Extension target
8. **MultipeerConnectivity** for mesh chat instead of raw BLE — Apple's supported framework for P2P

---

## Known Issues

1. **API routes return 501** — Backend service layer not implemented for most modules
2. **Deployed API is old build** — Latest code (AuthService, payment routes) not redeployed
3. **Apple Sign-In error 1000** — Entitlement added but needs Apple Developer portal App ID config
4. **Google OAuth not configured** — Needs client ID creation in Cloud Console
5. **Widget Extension target missing** — WidgetKit files excluded from main app, need separate target
6. **Worker job processors are stubs** — All 7 BullMQ processors have TODO implementations
7. **Push notifications not functional** — No APNs certificate configured
8. **Web profile shows placeholder data** — API /auth/me needs to return real user data

---

## File Counts

| Layer | Files | Lines |
|-------|-------|-------|
| iOS (Swift) | ~135 | ~18,000 |
| API (TypeScript) | ~65 | ~8,000 |
| Web (React/TSX) | ~25 | ~5,000 |
| Shared (TypeScript) | 4 | ~1,200 |
| Worker (TypeScript) | 10 | ~500 |
| Realtime (TypeScript) | 3 | ~300 |
| Infrastructure (Terraform/Docker/YAML) | ~25 | ~2,000 |
| **Total** | **~270** | **~35,000** |
