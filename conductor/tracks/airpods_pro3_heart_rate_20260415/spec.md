# AirPods Pro 3 Heart Rate Integration — Technical Spec

## Reverse-Engineered Reuse Paths

### Backend

- `api/src/models/HealthMetric.ts` already stores health data with `metricType` and `unit` enums. Extend to support `heart_rate` type.
- `api/src/modules/health/routes.ts` already has sync, snapshot, and history endpoints. Add HR-specific batch and summary routes.
- `shared/src/schemas/index.ts` already has health metric schemas. Add HR batch and summary schemas.

### iOS

- `client-ios/GearSnitch/Core/HealthKit/HealthKitManager.swift` already handles HealthKit authorization and queries. Add `heartRate` and `heartRateVariabilitySDNN` to read types and add anchored query support.
- `client-ios/GearSnitch/Shared/Widgets/GymSessionActivityAttributes.swift` already defines `ContentState`. Extend with optional HR fields.
- `client-ios/GearSnitch/Features/Widgets/GymSessionLiveActivityWidget.swift` already renders Dynamic Island and lock screen views. Add HR display.
- `client-ios/GearSnitch/Core/Widgets/LiveActivityManager.swift` already manages Live Activity lifecycle. Add HR update method.
- `client-ios/GearSnitch/Features/Dashboard/DashboardView.swift` already renders the main dashboard. Add heart rate card.

## Architecture Overview

```
AirPods Pro 3 → HealthKit Store → HKAnchoredObjectQuery
                                         ↓
                                  HeartRateMonitor (new service)
                                    ↓          ↓           ↓
                          LiveActivityManager  Dashboard   Backend Sync
                          (update content)     (published)  (batch POST)
                                    ↓
                          Dynamic Island + Lock Screen
```

### Data Flow

1. AirPods Pro 3 optical sensor writes `HKQuantityType.heartRate` samples to HealthKit.
2. `HeartRateMonitor` runs an `HKAnchoredObjectQuery` that fires on each new sample.
3. On each new sample, `HeartRateMonitor` updates its `@Published` properties (currentBPM, zone, source device).
4. `LiveActivityManager` observes `HeartRateMonitor` and calls `Activity.update()` with new content state including HR data, throttled to once per 2 seconds.
5. `DashboardView` observes `HeartRateMonitor` directly and renders the heart rate card.
6. `HeartRateMonitor` batches samples and syncs to the backend every 30 seconds via `POST /health/heart-rate/batch`.

## Data Model

### Backend — HealthMetric Extension

Add `heart_rate` to the existing `metricType` enum and `bpm` is already a supported unit.

```typescript
// Existing HealthMetric model — add 'heart_rate' to metricType enum:
metricType: 'weight' | 'height' | 'bmi' | 'active_calories' | 'steps'
           | 'resting_heart_rate' | 'workout_session'
           | 'heart_rate'  // NEW — instantaneous HR from AirPods Pro 3

// Add 'airpods_pro' to source enum:
source: 'manual' | 'apple_health' | 'airpods_pro'
```

Add a compound index for efficient session queries:

```typescript
HealthMetricSchema.index({ userId: 1, metricType: 1, recordedAt: -1 });
// NEW — for session time-window queries:
HealthMetricSchema.index({ userId: 1, metricType: 1, recordedAt: 1 });
```

### iOS — HeartRateMonitor

New `@MainActor` observable service:

```swift
@MainActor
final class HeartRateMonitor: ObservableObject {
    static let shared = HeartRateMonitor()

    @Published private(set) var currentBPM: Int?
    @Published private(set) var currentZone: HeartRateZone?
    @Published private(set) var sourceDeviceName: String?
    @Published private(set) var isMonitoring: Bool = false
    @Published private(set) var lastUpdated: Date?

    func startMonitoring()
    func stopMonitoring()
}
```

### iOS — HeartRateZone

```swift
enum HeartRateZone: String, Codable, CaseIterable {
    case rest       // < 100 BPM
    case light      // 100-119 BPM
    case fatBurn    // 120-139 BPM
    case cardio     // 140-159 BPM
    case peak       // >= 160 BPM

    var label: String { ... }
    var color: Color { ... }
    var systemImage: String { "heart.fill" }

    static func from(bpm: Int) -> HeartRateZone
}
```

### iOS — GymSessionAttributes.ContentState Extension

```swift
struct ContentState: Codable, Hashable {
    let isActive: Bool
    let elapsedSeconds: Int
    // NEW
    let heartRateBPM: Int?
    let heartRateZone: String?  // Raw value of HeartRateZone
}
```

## Shared Schemas

Add to `shared/src/schemas/index.ts`:

```typescript
// ─── Heart Rate ─────────────────────────────────────────────────────────

export const heartRateSampleSchema = z.object({
  bpm: z.number().int().min(30).max(250),
  recordedAt: z.string().datetime(),
  source: z.string().max(120).optional().default('airpods_pro'),
});
export type HeartRateSampleInput = z.infer<typeof heartRateSampleSchema>;

export const heartRateBatchSchema = z.object({
  samples: z.array(heartRateSampleSchema).min(1).max(500),
  sessionId: z.string().optional(),
});
export type HeartRateBatchInput = z.infer<typeof heartRateBatchSchema>;

export const heartRateZoneDistributionSchema = z.object({
  rest: z.number().min(0).max(100),
  light: z.number().min(0).max(100),
  fatBurn: z.number().min(0).max(100),
  cardio: z.number().min(0).max(100),
  peak: z.number().min(0).max(100),
});
export type HeartRateZoneDistribution = z.infer<typeof heartRateZoneDistributionSchema>;

export const heartRateSessionSummarySchema = z.object({
  sessionId: z.string().optional(),
  from: z.string().datetime(),
  to: z.string().datetime(),
  sampleCount: z.number().int().min(0),
  minBPM: z.number().int().min(0),
  maxBPM: z.number().int().min(0),
  avgBPM: z.number().min(0),
  zoneDistribution: heartRateZoneDistributionSchema,
});
export type HeartRateSessionSummary = z.infer<typeof heartRateSessionSummarySchema>;
```

## API Contracts

### Batch Heart Rate Ingestion

```
POST /api/v1/health/heart-rate/batch
Authorization: Bearer <token>

Body:
{
  "samples": [
    { "bpm": 142, "recordedAt": "2026-04-15T14:30:00.000Z", "source": "airpods_pro" },
    { "bpm": 145, "recordedAt": "2026-04-15T14:30:05.000Z", "source": "airpods_pro" }
  ],
  "sessionId": "optional-gym-session-id"
}

Response 201:
{
  "success": true,
  "data": {
    "received": 2,
    "inserted": 2,
    "deduplicated": 0
  }
}
```

### Session Heart Rate Summary

```
GET /api/v1/health/heart-rate/session-summary?from=ISO&to=ISO&sessionId=optional
Authorization: Bearer <token>

Response 200:
{
  "success": true,
  "data": {
    "sessionId": "abc123",
    "from": "2026-04-15T14:00:00.000Z",
    "to": "2026-04-15T15:30:00.000Z",
    "sampleCount": 540,
    "minBPM": 72,
    "maxBPM": 178,
    "avgBPM": 138,
    "zoneDistribution": {
      "rest": 5.2,
      "light": 12.4,
      "fatBurn": 35.1,
      "cardio": 40.8,
      "peak": 6.5
    }
  }
}
```

### Health Routes Extension

Add to existing health routes normalization:

```typescript
// In normalizeMetricType:
case 'heart_rate':
case 'heartrate':
case 'instantaneous_heart_rate':
  return 'heart_rate';
```

## iOS Integration Plan

### 1. HeartRateMonitor Service

New file: `client-ios/GearSnitch/Core/HealthKit/HeartRateMonitor.swift`

- Singleton `@MainActor` class
- Uses `HKAnchoredObjectQuery` with update handler for live delivery
- Extracts source device name from `HKQuantitySample.sourceRevision.productType` to detect AirPods Pro 3
- Classifies BPM into `HeartRateZone`
- Batches samples into `pendingSamples` array, flushes to backend every 30 seconds
- Exposes `@Published` properties for SwiftUI observation
- Starts/stops monitoring coordinated with `GymSessionManager` and manual toggle

### 2. HealthKitManager Updates

File: `client-ios/GearSnitch/Core/HealthKit/HealthKitManager.swift`

- Add `HKQuantityTypeIdentifier.heartRate` to `readTypes`
- Add `HKQuantityTypeIdentifier.heartRateVariabilitySDNN` to `readTypes`
- Expose `healthStore` property for use by `HeartRateMonitor`

### 3. GymSessionAttributes Update

File: `client-ios/GearSnitch/Shared/Widgets/GymSessionActivityAttributes.swift`

- Add `heartRateBPM: Int?` and `heartRateZone: String?` to `ContentState`

### 4. LiveActivityManager Update

File: `client-ios/GearSnitch/Core/Widgets/LiveActivityManager.swift`

- Add `updateHeartRate(bpm: Int, zone: HeartRateZone)` method
- Throttle updates to once per 2 seconds using a timestamp check
- Build new `ContentState` with HR data and call `activity.update()`

### 5. GymSessionLiveActivityWidget Update

File: `client-ios/GearSnitch/Features/Widgets/GymSessionLiveActivityWidget.swift`

**Dynamic Island — Compact Trailing:**
- When `heartRateBPM` is non-nil: show heart.fill icon + BPM number, zone-colored
- When nil: show existing timer text

**Dynamic Island — Expanded Bottom:**
- Add heart rate row before "End Session" button
- Show heart.fill + BPM + zone label with zone-colored dot

**Lock Screen:**
- Add heart rate display between gym info and timer
- Heart icon with zone-colored tint + BPM in bold rounded font

**Minimal:**
- When HR active: pulsing heart.fill icon
- When not: existing gym icon

### 6. Dashboard Heart Rate Card

New file: `client-ios/GearSnitch/Features/Dashboard/HeartRateCard.swift`

- Observes `HeartRateMonitor.shared`
- Shows current BPM in large font, zone label, zone-colored accent bar
- Shows source device name and last update time
- Empty state when no HR data

### 7. DashboardView Update

File: `client-ios/GearSnitch/Features/Dashboard/DashboardView.swift`

- Add `@ObservedObject private var heartRateMonitor = HeartRateMonitor.shared`
- Insert `HeartRateCard()` after `gymSessionStatusCard`, before alerts banner

### 8. GymSessionManager Coordination

- On `startSession()`: call `HeartRateMonitor.shared.startMonitoring()`
- On `endSession()`: call `HeartRateMonitor.shared.stopMonitoring()`

## Backend Implementation Plan

### 1. HealthMetric Model Update

File: `api/src/models/HealthMetric.ts`

- Add `'heart_rate'` to `metricType` enum
- Add `'airpods_pro'` to `source` enum
- Add ascending index on `{ userId: 1, metricType: 1, recordedAt: 1 }` for time-window aggregation

### 2. Health Routes Extension

File: `api/src/modules/health/routes.ts`

- Add `heart_rate` case to `normalizeMetricType()`
- Add `handleHeartRateBatch()` handler for `POST /heart-rate/batch`
- Add `handleHeartRateSessionSummary()` handler for `GET /heart-rate/session-summary`
- Register new routes

### 3. Shared Schema Update

File: `shared/src/schemas/index.ts`

- Add `heartRateSampleSchema`, `heartRateBatchSchema`
- Add `heartRateZoneDistributionSchema`, `heartRateSessionSummarySchema`

## Validation, Privacy, And Policy

- Require authentication for all heart rate endpoints
- Enforce ownership on all queries
- Validate BPM range (30-250) on ingestion
- Cap batch size to 500 samples per request
- Heart rate data is health-sensitive; respect HealthKit authorization
- Include HR data in account export and deletion flows
- No heart rate data shared with other users

## Testing

- Backend: route tests for batch ingestion, deduplication, session summary aggregation, zone distribution calculation
- iOS: HeartRateMonitor unit tests for zone classification, sample buffering, monitoring lifecycle
- iOS: GymSessionAttributes ContentState encoding/decoding with optional HR fields
- Integration: verify Live Activity updates arrive with HR data during active session
