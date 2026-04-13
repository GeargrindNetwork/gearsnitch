# GearSnitch — Session Handoff & Action Plan

**Date:** April 11, 2026
**Session:** Initial build plus post-QA integration-gap closure and re-verification
**Repo:** https://github.com/GeargrindNetwork/gearsnitch (30 commits on main)

---

## Update — April 11, 2026

The original QA closure was too optimistic. A follow-on audit found remaining internal client or backend contract gaps in alerts, referrals, account deletion, support, store checkout, Apple Pay, and BLE disconnect handling. Those gaps are now closed in source and revalidated.

### Verified in this follow-up

- `npm test --workspace=api` — PASS (`5` suites / `25` tests)
- `npm run type-check` — PASS
- `npm run test` — PASS
- `npm run launch:check` — PASS (`21/21`)
- `xcodebuild -project client-ios/GearSnitch.xcodeproj -target GearSnitch -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build` — PASS

### Internal launch-path fixes now landed

- Alerts ship live list, disconnect, and acknowledge routes instead of `501` stubs.
- Referrals ship live `/referrals/me` and `/referrals/qr` contracts with persisted referral codes.
- Delete-account and support pages now submit real API-backed requests.
- The web store uses live catalog and cart data, and checkout finalizes real backend orders.
- iOS Apple Pay now creates and confirms real payment intents against the same cart-backed order contract.
- BLE reconnect timeout now invokes the real disconnect haptic and alert helpers, and BLE service filtering is configurable through app config.

## Current State

### Infrastructure — All Live

| System | Status | URL / Details |
|--------|--------|---------------|
| **Website** | 200 LIVE | https://gearsnitch.com |
| **Privacy Policy** | 200 LIVE | https://gearsnitch.com/privacy |
| **Terms of Service** | 200 LIVE | https://gearsnitch.com/terms |
| **Support** | 200 LIVE | https://gearsnitch.com/support |
| **Delete Account** | 200 LIVE | https://gearsnitch.com/delete-account |
| **API** | 200 LIVE | https://api.gearsnitch.com (launch-critical routes are implemented; some non-launch modules remain outside the current slice) |
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
gearsnitch/ (30 commits, ~300 files, ~40k lines)
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
├── worker/                       # BullMQ (13 queues, launch-path processors live, some deferred follow-up work)
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
| Apple Pay | Yes | Yes (Stripe) | Yes (Elements) | **Partial** (code paths are live; merchant setup and live verification remain external) |
| StoreKit subscriptions | Yes | Yes (JWS validate) | — | **No** (needs StoreKit config) |
| Gym CRUD | Yes (UI) | Yes | — | **Partial** |
| Device CRUD | Yes (UI) | Yes | — | **Partial** |
| User profile / account basics | Yes (UI) | Yes | Yes (UI) | **Partial** |
| Sessions | Yes (UI) | Routes built | — | **Partial** (routes exist but not deployed) |
| Calendar | Yes (UI) | Routes built | Yes (UI) | **Partial** |
| Health metrics | Yes (UI) | **501 stub** | — | **No** |
| Calories/meals | Yes (UI) | **501 stub** | — | **No** |
| Workouts | Yes (UI) | Yes | — | **Partial** |
| Store products / cart / checkout | Yes (UI) | Yes | Yes (UI) | **Partial** (live merchant verification still external) |
| Referrals | Yes (UI) | Yes | — | **YES** |
| Event logging | — | Routes built | — | **Partial** |
| Push notifications | Yes (handler) | Token registration | — | **No** (needs APNs cert) |
| WebSocket realtime | Yes (client) | Yes (server) | — | **Deployed but untested** |
| Run tracking | Yes | Yes | Yes | **Partial** (physical-device GPS QA still manual) |
| Web metrics dashboard | **N/A** | Yes | Yes | **YES** |

---

## Launch Action Plan — Priority Order

### P0: External Launch Verification

These are the remaining blockers for true end-to-end launch validation. They are outside the code already landed in this repo.

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

### P1: Redeploy And Smoke Test Current Revisions

If production is still running an older image revision, redeploy from the current repo state and verify these launch paths against live services:

1. `cd /Users/shawn/Documents/GearSnitch && gcloud builds submit --project=gearsnitch --region=us-central1 --config=infrastructure/cloudbuild/cloudbuild.yaml --substitutions=_TAG=v1.0.0`
2. Verify browser sign-in bootstrap, support ticket submission, delete-account flow, store catalog load, Stripe checkout, and referral/account surfaces against the deployed API.
3. Verify iOS sign-in, alert list, referrals, cart, Apple Pay, and BLE disconnect behavior against the deployed API plus worker/realtime services.

### P2: Remaining Non-Launch Product Follow-Up

- Finish non-launch modules that are still outside the current slice (`health-data`, `calories`, `content`, `admin`, `config`) if those surfaces are promoted to active client paths.
- Add the missing Widget Extension target so WidgetKit files are no longer parked in the app tree without a shipping target.
- Replace any remaining worker TODO processors that are not on the launch-critical path today but would matter for broader production hardening.

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
7. **StaticConfiguration widgets** shipped in a separate Widget Extension target generated by XcodeGen
8. **MultipeerConnectivity** for mesh chat instead of raw BLE — Apple's supported framework for P2P

---

## Known Issues

1. **Apple Sign-In still needs portal setup** — The entitlement is present in code, but live service/app identifier configuration is still external.
2. **Google OAuth still needs real client IDs** — Browser and iOS flows require Cloud Console credentials plus redirect verification.
3. **Push notifications still need APNs provisioning** — Repo wiring is in place, but live delivery cannot be validated without Apple credentials.
4. **Live Stripe and Apple Pay still need merchant validation** — The app code now uses the correct contracts, but real payment verification depends on live credentials and merchant certificates.
5. **Widget system now ships through a dedicated extension target** — session, device-status, calories, and Live Activity surfaces now read from the shared app group and require the generated widget target in Xcode.
6. **Some dormant modules remain outside the active launch slice** — `health-data`, `calories`, `content`, `admin`, and `config` still need dedicated follow-up if those surfaces become launch-critical.

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
