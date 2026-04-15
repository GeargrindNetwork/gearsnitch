# Apple Watch Companion & Cross-Platform Continuity — Implementation Plan

## Execution Summary

### Step 1: PRD & Spec (done)

- PRD covering Watch app, WatchConnectivity, backend extensions, web health dashboard
- Technical spec with architecture diagram, message contracts, API contracts, implementation plans

### Step 2: WatchConnectivity Layer (done)

- `WatchSyncPayloads.swift` — shared message types (WatchAppContext, PhoneAppContext, message types, session actions)
- `WatchSyncManager.swift` — iPhone-side WCSessionDelegate with state push, HR forwarding, session/alert updates, Watch command handling, Combine-based observation of session/HR changes
- `WatchSessionManager.swift` — Watch-side WCSessionDelegate with published state from iPhone context, command sending, live message handling

### Step 3: Watch App (done)

- `GearSnitchWatchApp.swift` — Watch app entry point with WatchSessionManager environment object
- `ContentView.swift` — Vertical tab navigation across 4 tabs
- `HeartRateView.swift` — Live BPM display with zone-colored radial gradient, zone label, source device, empty state
- `SessionView.swift` — Active/inactive session display with start/end controls, live timer
- `AlertsView.swift` — Alert count with latest message, all-clear empty state
- `QuickActionsView.swift` — Start/end session and HR monitoring toggle buttons
- `GearSnitchWatch.entitlements` — App group + APS entitlements
- `Info.plist` — Companion app bundle identifier

### Step 4: Backend Extensions (done)

- `Device.ts` — Added `'watch'` to device type enum
- `EventLog.ts` — Added `'watchos'` to event source enum
- `health/routes.ts` — Added `GET /health/dashboard` endpoint aggregating latest HR, today's HR stats, today's sessions, device fleet, source attribution
- `shared/schemas/index.ts` — Added `'watch'` to device schemas, added health dashboard response schemas (latest HR, today HR, session, device, source)

### Step 5: Web Health Dashboard (done)

- `HeartRateSummaryCard.tsx` — Latest BPM with zone color, today's min/avg/max, zone distribution bar chart with legend
- `ConnectedDevicesCard.tsx` — Device fleet grid with type icons, status badges, health-capable indicator, last seen
- `HealthSourcesCard.tsx` — Data source attribution with sample counts and last data timestamps
- `api.ts` — Added `getHealthDashboard()` function and `HealthDashboardResponse` type
- `MetricsPage.tsx` — Integrated health dashboard cards in responsive grid above existing cycle summary

### Step 6: Xcode Project Config (done)

- `project.yml` — Added `GearSnitchWatch` target (watchOS 10.0), shared source groups, entitlements, embedded in main app

### Step 7: Product Docs (done)

- Updated `product-roadmap.md` with Phase 7 (Watch + continuity)
- Created track metadata, plan

## Remaining Work

- Wire `WatchSyncManager.shared.startObserving()` into iOS app lifecycle after auth
- Wire `HeartRateMonitor` updates to `WatchSyncManager.sendHeartRateUpdate()` in the HR monitoring loop
- Add Watch notification token registration flow
- Add Watch-specific complications (BPM on watch face)
- Integration testing of WatchConnectivity message delivery
- End-to-end testing of web health dashboard with live backend data
