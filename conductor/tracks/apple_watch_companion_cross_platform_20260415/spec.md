# Apple Watch Companion & Cross-Platform Continuity — Technical Spec

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│                        APPLE WATCH                                  │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────────────┐   │
│  │ Heart    │ │ Session  │ │ Alerts   │ │ Quick Actions        │   │
│  │ Rate Tab │ │ Tab      │ │ Tab      │ │ Tab                  │   │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └──────────┬──────────┘   │
│       └─────────────┼───────────┼──────────────────┘              │
│                     ▼                                              │
│            WatchSyncManager (Watch side)                           │
└─────────────────────┬────────────────────────────────────────────┘
                      │ WatchConnectivity
                      │ (sendMessage / applicationContext / userInfo)
┌─────────────────────┼────────────────────────────────────────────┐
│                     ▼                                              │
│            WatchSyncManager (iPhone side)                          │
│                ↕          ↕            ↕          ↕               │
│        HeartRate    GymSession    BLEManager   PushNotification   │
│        Monitor      Manager       (alerts)     Handler           │
│                                                                    │
│                        iPhone App                                  │
└─────────────────────┬────────────────────────────────────────────┘
                      │ REST API + WebSocket
                      ▼
┌──────────────────────────────────────────────────────────────────────┐
│                     BACKEND                                         │
│  ┌───────────┐ ┌──────────┐ ┌───────────┐ ┌────────────────────┐   │
│  │ Health    │ │ Sessions │ │ Devices   │ │ Notifications      │   │
│  │ Module    │ │ Module   │ │ Module    │ │ Module             │   │
│  └───────────┘ └──────────┘ └───────────┘ └────────────────────┘   │
│                     ▲                                               │
└─────────────────────┼──────────────────────────────────────────────┘
                      │ REST API
┌─────────────────────┼──────────────────────────────────────────────┐
│                     │          WEB APP                              │
│  ┌─────────────────┐ ┌───────────────────┐ ┌──────────────────┐   │
│  │ HeartRate       │ │ Connected         │ │ Health           │   │
│  │ SummaryCard     │ │ DevicesCard       │ │ SourcesCard      │   │
│  └─────────────────┘ └───────────────────┘ └──────────────────┘   │
│                        Metrics Page                                │
└──────────────────────────────────────────────────────────────────────┘
```

## Reverse-Engineered Reuse Paths

### iOS

- `client-ios/GearSnitch/Core/BLE/PanicAlarmManager.swift` — already implements `WCSessionDelegate`, `sendMessage()`, and `transferUserInfo()`. Extend this pattern into a full `WatchSyncManager`.
- `client-ios/GearSnitch/Core/HealthKit/HeartRateMonitor.swift` — already publishes real-time BPM. Wire its output into `WatchSyncManager`.
- `client-ios/GearSnitch/Core/Session/GymSessionManager.swift` — already manages session lifecycle. Add Watch command handling.
- `client-ios/GearSnitch/Core/Widgets/WidgetSyncStore.swift` — app group data sharing pattern. Reuse for Watch.
- `client-ios/GearSnitch/Shared/` — shared models, colors, and components. Extend for Watch target.
- `client-ios/project.yml` — XcodeGen config. Add Watch target.

### Backend

- `api/src/models/Session.ts` — already supports `platform: 'watchos'`.
- `api/src/models/NotificationToken.ts` — already supports `platform: 'watchos'`.
- `api/src/models/Device.ts` — type enum needs `'watch'` addition.
- `api/src/models/EventLog.ts` — source enum needs `'watchos'` addition.
- `api/src/modules/health/routes.ts` — already has HR batch and summary. Add unified dashboard.

### Web

- `web/src/pages/MetricsPage.tsx` — already renders summary cards, distribution charts, device fleet. Add HR and health source cards.
- `web/src/lib/api.ts` — already has typed API client. Add health dashboard endpoint.
- `web/src/components/ui/` — shadcn components for cards, badges, etc.

## Data Model

### WatchConnectivity Message Contracts

**Application Context (persistent state, survives restarts):**

iPhone → Watch:
```swift
struct WatchAppContext: Codable {
    let isSessionActive: Bool
    let sessionGymName: String?
    let sessionStartedAt: Date?
    let sessionElapsedSeconds: Int?
    let heartRateBPM: Int?
    let heartRateZone: String?
    let heartRateSourceDevice: String?
    let activeAlertCount: Int
    let defaultGymId: String?
    let defaultGymName: String?
    let isHeartRateMonitoring: Bool
}
```

Watch → iPhone:
```swift
struct PhoneAppContext: Codable {
    let watchActive: Bool
    let lastInteractionAt: Date?
}
```

**Live Messages (real-time, only when both apps are active):**

iPhone → Watch:
```swift
// Heart rate update
["type": "heartRate", "bpm": 142, "zone": "cardio", "source": "AirPods Pro"]

// Session state change
["type": "sessionUpdate", "isActive": true, "gymName": "Planet Fitness", "elapsedSeconds": 1234]

// Alert count change
["type": "alertUpdate", "count": 2, "latestMessage": "AirPods Pro disconnected"]
```

Watch → iPhone:
```swift
// Session command
["type": "sessionCommand", "action": "start", "gymId": "abc123", "gymName": "Planet Fitness"]
["type": "sessionCommand", "action": "end"]

// Alert acknowledgment
["type": "alertAcknowledge", "alertId": "xyz789"]

// HR monitoring toggle
["type": "hrMonitoring", "enabled": true]
```

### Backend — Device Type Extension

```typescript
// Device.ts — add 'watch' to type enum
type: 'earbuds' | 'tracker' | 'belt' | 'bag' | 'watch' | 'other'
```

### Backend — Event Source Extension

```typescript
// EventLog.ts — add 'watchos' to source enum
source: 'ios' | 'web' | 'system' | 'widget' | 'watchos'
```

### Backend — Health Dashboard Response

```typescript
interface HealthDashboardResponse {
  heartRate: {
    latest: { bpm: number; recordedAt: string; source: string } | null;
    today: {
      sampleCount: number;
      minBPM: number;
      maxBPM: number;
      avgBPM: number;
      zoneDistribution: HeartRateZoneDistribution;
    } | null;
  };
  sessions: {
    today: Array<{
      _id: string;
      gymName: string;
      startedAt: string;
      endedAt: string | null;
      durationMinutes: number | null;
      heartRateSummary: HeartRateSessionSummary | null;
    }>;
    activeSession: { _id: string; gymName: string; startedAt: string } | null;
  };
  devices: Array<{
    _id: string;
    name: string;
    nickname: string | null;
    type: string;
    status: string;
    isFavorite: boolean;
    lastSeenAt: string | null;
    healthCapable: boolean;
  }>;
  sources: Array<{
    name: string;
    type: 'airpods_pro' | 'apple_watch' | 'apple_health' | 'manual';
    lastDataAt: string | null;
    sampleCountToday: number;
  }>;
}
```

## Shared Schemas

Add to `shared/src/schemas/index.ts`:

```typescript
// ─── Health Dashboard ──────────────────────────────────────────────────

export const healthDashboardLatestHRSchema = z.object({
  bpm: z.number().int().min(0),
  recordedAt: z.string().datetime(),
  source: z.string(),
});

export const healthDashboardTodayHRSchema = z.object({
  sampleCount: z.number().int().min(0),
  minBPM: z.number().int().min(0),
  maxBPM: z.number().int().min(0),
  avgBPM: z.number().min(0),
  zoneDistribution: heartRateZoneDistributionSchema,
});

export const healthDashboardSessionSchema = z.object({
  _id: z.string(),
  gymName: z.string(),
  startedAt: z.string().datetime(),
  endedAt: z.string().datetime().nullable(),
  durationMinutes: z.number().nullable(),
  heartRateSummary: heartRateSessionSummarySchema.nullable(),
});

export const healthDashboardDeviceSchema = z.object({
  _id: z.string(),
  name: z.string(),
  nickname: z.string().nullable(),
  type: z.string(),
  status: z.string(),
  isFavorite: z.boolean(),
  lastSeenAt: z.string().datetime().nullable(),
  healthCapable: z.boolean(),
});

export const healthDashboardSourceSchema = z.object({
  name: z.string(),
  type: z.enum(['airpods_pro', 'apple_watch', 'apple_health', 'manual']),
  lastDataAt: z.string().datetime().nullable(),
  sampleCountToday: z.number().int().min(0),
});

export const healthDashboardResponseSchema = z.object({
  heartRate: z.object({
    latest: healthDashboardLatestHRSchema.nullable(),
    today: healthDashboardTodayHRSchema.nullable(),
  }),
  sessions: z.object({
    today: z.array(healthDashboardSessionSchema),
    activeSession: z.object({
      _id: z.string(),
      gymName: z.string(),
      startedAt: z.string().datetime(),
    }).nullable(),
  }),
  devices: z.array(healthDashboardDeviceSchema),
  sources: z.array(healthDashboardSourceSchema),
});
export type HealthDashboardResponse = z.infer<typeof healthDashboardResponseSchema>;
```

## API Contracts

### Unified Health Dashboard

```
GET /api/v1/health/dashboard
Authorization: Bearer <token>

Response 200:
{
  "success": true,
  "data": {
    "heartRate": {
      "latest": { "bpm": 142, "recordedAt": "2026-04-15T14:30:00Z", "source": "airpods_pro" },
      "today": {
        "sampleCount": 540,
        "minBPM": 62,
        "maxBPM": 178,
        "avgBPM": 118,
        "zoneDistribution": { "rest": 15, "light": 20, "fatBurn": 30, "cardio": 28, "peak": 7 }
      }
    },
    "sessions": {
      "today": [
        {
          "_id": "abc123",
          "gymName": "Planet Fitness",
          "startedAt": "2026-04-15T14:00:00Z",
          "endedAt": "2026-04-15T15:30:00Z",
          "durationMinutes": 90,
          "heartRateSummary": { ... }
        }
      ],
      "activeSession": null
    },
    "devices": [
      { "_id": "d1", "name": "AirPods Pro", "type": "earbuds", "status": "connected", "healthCapable": true, ... },
      { "_id": "d2", "name": "Apple Watch", "type": "watch", "status": "active", "healthCapable": true, ... }
    ],
    "sources": [
      { "name": "AirPods Pro 3", "type": "airpods_pro", "lastDataAt": "2026-04-15T14:30:00Z", "sampleCountToday": 540 },
      { "name": "Apple Watch", "type": "apple_watch", "lastDataAt": null, "sampleCountToday": 0 }
    ]
  }
}
```

## Watch App Implementation Plan

### Directory Structure

```
client-ios/
├── GearSnitchWatch/
│   ├── GearSnitchWatchApp.swift          # Watch app entry point
│   ├── ContentView.swift                  # Tab-based navigation
│   ├── Views/
│   │   ├── HeartRateView.swift           # Live BPM + zone display
│   │   ├── SessionView.swift             # Gym session status + controls
│   │   ├── AlertsView.swift              # Device alert list
│   │   └── QuickActionsView.swift        # Quick action buttons
│   └── WatchSyncManager+Watch.swift       # Watch-side WC delegate
├── GearSnitch/
│   ├── Core/
│   │   └── Watch/
│   │       └── WatchSyncManager.swift     # iPhone-side WC delegate
│   └── Shared/
│       └── WatchSyncPayloads.swift        # Shared message types
```

### Watch Views

**HeartRateView:**
- Large centered BPM number (SF Rounded, 48pt)
- Zone-colored circular ring background
- Zone label text below
- Source device label at bottom
- "No Data" empty state with icon

**SessionView:**
- Active: gym name, live timer, red "End Session" button
- Inactive: default gym name, green "Start Session" button
- Loading states for start/end operations

**AlertsView:**
- List of active alerts with device name and time
- Tap to acknowledge → sends command to iPhone
- Empty state: "All clear" with checkmark

**QuickActionsView:**
- "Start Session" button (uses default gym)
- "Heart Rate" toggle (on/off)

### WatchSyncManager (Shared Logic)

New files in `Core/Watch/`:

**iPhone Side (`WatchSyncManager.swift`):**
- Observes `HeartRateMonitor`, `GymSessionManager`, alerts
- Pushes application context on any state change
- Sends live messages for HR updates (throttled to 2s)
- Receives and handles Watch commands
- Extracts Watch notification token from WCSession

**Watch Side (`WatchSyncManager+Watch.swift`):**
- Receives and publishes application context as `@Published` properties
- Receives live messages and updates local state
- Sends commands (start/end session, acknowledge alert)
- Reports Watch active state back to iPhone

## Backend Implementation Plan

### 1. Device Type Extension

File: `api/src/models/Device.ts`
- Add `'watch'` to type enum

File: `shared/src/schemas/index.ts`
- Add `'watch'` to `createDeviceSchema` and `updateDeviceSchema` type enums

### 2. Event Source Extension

File: `api/src/models/EventLog.ts`
- Add `'watchos'` to source enum

### 3. Health Dashboard Endpoint

File: `api/src/modules/health/routes.ts`
- Add `GET /dashboard` handler
- Aggregates: latest HR sample, today's HR stats, today's sessions with HR summaries, user's devices, data source attribution
- Single query-efficient endpoint for the web dashboard

### 4. Health Source Attribution

Compute data sources by distinct `source` values in today's `HealthMetric` records where `metricType = 'heart_rate'`.

## Web Implementation Plan

### 1. API Client Extension

File: `web/src/lib/api.ts`
- Add `getHealthDashboard()` function
- Add `HealthDashboardResponse` type

### 2. HeartRateSummaryCard Component

File: `web/src/components/metrics/HeartRateSummaryCard.tsx`
- Shows latest BPM with zone color
- Today's min/max/avg stats
- Zone distribution as colored bar segments
- Empty state when no HR data

### 3. ConnectedDevicesCard Component

File: `web/src/components/metrics/ConnectedDevicesCard.tsx`
- Grid of device cards with type icon (earbuds, watch, tracker, etc.)
- Status badge (connected, active, offline, lost)
- Last seen timestamp
- Health-capable indicator

### 4. HealthSourcesCard Component

File: `web/src/components/metrics/HealthSourcesCard.tsx`
- List of data sources with sample counts
- Last data timestamp per source
- Source type icon

### 5. MetricsPage Integration

File: `web/src/pages/MetricsPage.tsx`
- Add health dashboard query: `useQuery({ queryKey: ['health-dashboard'] })`
- Insert HR summary card at top of page
- Insert devices and sources cards after existing sections

## Xcode Project Configuration

File: `client-ios/project.yml`

Add new target:
```yaml
GearSnitchWatch:
  type: application
  platform: watchOS
  deploymentTarget: "10.0"
  sources:
    - GearSnitchWatch
    - path: GearSnitch/Shared/Models
      group: Shared
    - path: GearSnitch/Shared/Extensions/Color+GearSnitch.swift
      group: Shared
    - path: GearSnitch/Shared/Widgets/GymSessionActivityAttributes.swift
      group: Shared
    - path: GearSnitch/Core/Watch/WatchSyncPayloads.swift
      group: Shared
  entitlements:
    path: GearSnitchWatch/GearSnitchWatch.entitlements
  settings:
    PRODUCT_BUNDLE_IDENTIFIER: com.gearsnitch.app.watchkitapp
    INFOPLIST_KEY_WKCompanionAppBundleIdentifier: com.gearsnitch.app
    SWIFT_VERSION: "5.9"
  dependencies:
    - target: GearSnitch
      embed: false
```

## Testing

- Watch: UI test for each tab rendering with mock WatchSyncManager state
- WatchSyncManager: unit tests for message serialization, context updates, command handling
- Backend: route test for health dashboard endpoint, source attribution aggregation
- Web: component tests for HR summary card rendering with various data states
- Integration: verify iPhone → Watch state sync latency with real WatchConnectivity

## Validation, Privacy, And Policy

- Watch app inherits authentication from iPhone — no separate login
- All Watch commands are relayed through iPhone to backend — Watch never calls API directly
- Heart rate data on Watch is ephemeral display only — not persisted on Watch
- Device fleet registration for Apple Watch follows same ownership model as other devices
- Health dashboard endpoint enforces user ownership on all queries
- Watch notification tokens follow same registration flow as iOS tokens
