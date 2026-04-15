# AirPods Pro 3 Heart Rate Integration — Implementation Plan

## Execution Order

### Step 1: Shared Schemas (done)

- Added `heartRateSampleSchema`, `heartRateBatchSchema`, `heartRateZoneDistributionSchema`, `heartRateSessionSummarySchema` to `shared/src/schemas/index.ts`

### Step 2: Backend Model & Routes (done)

- Extended `HealthMetric` model with `heart_rate` metric type and `airpods_pro` source
- Added ascending index for time-window queries
- Added `POST /health/heart-rate/batch` for bulk HR sample ingestion with deduplication
- Added `GET /health/heart-rate/session-summary` for min/max/avg/zone computation
- Extended `normalizeMetricType()` to handle `heart_rate` and `instantaneous_heart_rate`
- Extended `normalizeMetricSource()` to handle `airpods_pro`

### Step 3: iOS HealthKitManager Update (done)

- Added `HKQuantityTypeIdentifier.heartRate` to read types
- Added `HKQuantityTypeIdentifier.heartRateVariabilitySDNN` to read types

### Step 4: iOS HeartRateMonitor Service (done)

- New `HeartRateMonitor` singleton with `HKAnchoredObjectQuery` for live HR streaming
- `HeartRateZone` enum with 5-zone classification and SwiftUI color mapping
- Source device name extraction from `HKQuantitySample.device` and `sourceRevision`
- 30-second batch sync loop to `POST /health/heart-rate/batch`
- 2-second throttled Live Activity updates
- Bounded pending sample buffer (max 2000)

### Step 5: Live Activity & Dynamic Island (done)

- Extended `GymSessionAttributes.ContentState` with `heartRateBPM: Int?` and `heartRateZone: String?`
- Updated `LiveActivityManager` with `updateHeartRate(bpm:zone:)` method
- Updated all `ContentState` initializations to include HR fields
- Dynamic Island compact trailing: heart icon + BPM when available, timer fallback
- Dynamic Island expanded bottom: heart rate row with BPM, zone label, zone-colored dot
- Dynamic Island minimal: pulsing heart icon when HR active
- Lock screen: BPM display with heart icon and zone color, replaces timer when active

### Step 6: In-App Dashboard (done)

- New `HeartRateCard` component with active state (BPM, zone bar, source name) and waiting state
- Inserted into `DashboardView` after gym session card, before alerts

### Step 7: Product Docs (done)

- Created PRD at `conductor/tracks/airpods_pro3_heart_rate_20260415/prd.md`
- Created technical spec at `conductor/tracks/airpods_pro3_heart_rate_20260415/spec.md`
- Created metadata at `conductor/tracks/airpods_pro3_heart_rate_20260415/metadata.json`
- Updated `conductor/product-roadmap.md` with Phase 6 and follow-up track

## Remaining Work

- Wire `HeartRateMonitor.startMonitoring()` / `stopMonitoring()` into `GymSessionManager.startSession()` / `endSession()`
- Add `APIEndpoint.Health.heartRateBatch(body:)` to the iOS API endpoint definitions
- Add session HR summary fetch after gym session ends
- Unit tests for HeartRateZone classification
- Backend route tests for batch ingestion and session summary
- Integration test for Live Activity HR update delivery
