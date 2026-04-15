# Apple Watch Companion & Cross-Platform Continuity

## Track ID

`apple_watch_companion_cross_platform_20260415`

## Summary

Build a native Apple Watch companion app that pairs with the GearSnitch iOS app and integrate all four surfaces — Watch, iOS, Web, and Backend — into a unified system where user state, health data, gym sessions, device alerts, and heart rate flow seamlessly across every platform in real time.

## Why This Track Exists

- The iOS app already has WatchConnectivity partially implemented in `PanicAlarmManager.swift` for sending panic alerts to a paired Apple Watch, proving the connectivity layer is viable.
- The backend `Session` model already supports `platform: 'watchos'` and `NotificationToken` supports `platform: 'watchos'`, meaning the auth and notification infrastructure is Watch-ready.
- The `WidgetSyncStore` and app group pattern (`group.com.gearsnitch.app`) already shares data between the iOS app and widget extension — this same pattern extends naturally to a Watch app.
- The `RealtimeEventBus` (WebSocket) and backend event system provide the real-time backbone, but the web app has no live health data display and the Watch has no app to consume it.
- Users who track workouts with GearSnitch on their phone and wear an Apple Watch have no way to see session status, heart rate, device alerts, or quick actions from their wrist without pulling out their phone.
- The web dashboard shows workout metrics, cycles, and device status but has no heart rate data, no live session awareness, and no indication of what devices (including Watch) are connected across the user's account.

## Problem Statement

GearSnitch is a multi-surface platform (iOS, Web, Backend) but these surfaces operate as loosely connected clients that each fetch their own data independently. There is no:

1. **Watch presence** — users cannot see gym session status, heart rate, device alerts, or quick actions from their wrist
2. **iPhone-Watch sync** — the iOS app cannot push real-time session state, heart rate, or alerts to a paired Watch, and the Watch cannot send actions (start/end session) back to the phone
3. **Web health continuity** — the web dashboard shows workout metrics but has no heart rate data, no live session awareness, and no unified health view that shows data from all sources (AirPods Pro 3, Apple Watch, HealthKit)
4. **Unified device fleet** — the web and iOS surfaces show BLE devices but don't surface the Apple Watch itself as a connected health data source in the user's device fleet

## Goals

- Ship a native watchOS companion app within the existing `client-ios/` Xcode project as a new WatchKit target
- Enable bidirectional real-time sync between iPhone and Watch via `WatchConnectivity` for session state, heart rate, device alerts, and user actions
- Display live heart rate, gym session status, device alert count, and quick actions on the Watch
- Allow users to start and end gym sessions from the Watch
- Register the Watch as a notification endpoint so push notifications (panic alarms, disconnect alerts) reach the wrist
- Add a unified health dashboard to the web app showing heart rate summaries, session history, and data source attribution
- Surface the Apple Watch as a recognized device in the user's fleet on both web and iOS
- Ensure the backend maintains a single source of truth for user state that all four surfaces consume consistently

## Non-Goals

- No standalone Watch app without iPhone pairing in v1 (require iPhone companion)
- No Watch-side BLE scanning or device pairing (BLE management stays on iPhone)
- No Watch-side HealthKit writing (read-only for heart rate display)
- No Watch complications beyond a simple BPM complication in v1
- No offline Watch workout recording without iPhone in v1
- No Watch-specific subscription or payment flow
- No Watch-specific auth flow (Watch inherits session from paired iPhone)

## MVP Scope

### Apple Watch App

- SwiftUI watchOS app with tab-based navigation: Heart Rate, Session, Alerts, Quick Actions
- Heart Rate tab: live BPM from iPhone (via WatchConnectivity), zone indicator, source device
- Session tab: active gym session status with timer, start/end session buttons
- Alerts tab: count of active device alerts with most recent alert detail
- Quick Actions: start session at default gym, toggle heart rate monitoring

### WatchConnectivity Layer

- `WatchSyncManager` shared between iOS and Watch targets
- iPhone → Watch: session state, heart rate updates, device alert count, gym name
- Watch → iPhone: start/end session commands, acknowledge alert
- Application context for persistent state sync (survives app restarts)
- Live messaging for real-time HR and session updates when both apps are active
- User info transfer for queued updates when Watch app is not reachable

### Backend Extensions

- Add `'watchos'` to event source enum so Watch-originated actions are attributed correctly
- Add `'watch'` device type to device model so Apple Watch appears in the device fleet
- Add `GET /health/dashboard` unified endpoint returning latest HR, session history, source devices, and cross-platform data summary
- Extend existing health sync to accept `source: 'apple_watch'`

### Web Health Dashboard

- New `HeartRateSummaryCard` on Metrics page showing latest HR, session avg/min/max, zone distribution
- New `ConnectedDevicesCard` showing all devices including Apple Watch with last-seen status
- New `HealthSourcesCard` showing data source attribution (AirPods Pro 3, Apple Watch, HealthKit)
- Heart rate session history list with expandable zone breakdown

## Primary User Stories

- A user starts a gym session on their iPhone and immediately sees the session status on their Apple Watch without any manual action
- A user glances at their Watch during a workout and sees their live heart rate, current zone, and session timer
- A user taps "End Session" on their Watch and the session ends on their iPhone, the Live Activity updates, and the backend records the completion
- A user receives a device disconnect alert and sees it on their Watch as a push notification and in the Alerts tab
- A user opens the web dashboard at home and sees their heart rate summary from today's workout, including average BPM and zone distribution
- A user views their device fleet on the web and sees their Apple Watch listed alongside their AirPods Pro 3 and other BLE devices
- A user logs in on web and sees health data from all sources unified in one view — no need to know which device produced which reading

## Product Requirements

1. The Watch app must be a WatchKit target within the existing `client-ios/` Xcode project, sharing code via the `Shared/` directory.
2. The Watch app must not require independent authentication — it inherits the session from the paired iPhone via WatchConnectivity.
3. `WatchSyncManager` must use `WCSession.default` with application context for persistent state and `sendMessage()` for real-time updates.
4. Heart rate data displayed on the Watch must originate from the iPhone's `HeartRateMonitor` and be pushed via WatchConnectivity, not queried independently by the Watch.
5. Session start/end commands from the Watch must be relayed to the iPhone, which remains the authoritative client for backend API calls.
6. The backend must accept `source: 'watchos'` in event logs and `platform: 'watchos'` in auth sessions.
7. The backend must provide a `GET /health/dashboard` endpoint that returns a unified view of the user's health data across all sources.
8. The web Metrics page must display heart rate data from the backend without needing to know the originating device.
9. Device fleet views on both web and iOS must show the Apple Watch when it is registered as a device.
10. Push notifications for panic alarms and disconnect alerts must be delivered to the Watch when the Watch has a registered notification token.
11. All Watch UI must use SwiftUI with watchOS 10+ APIs.
12. The Watch app must respect the `watchCompanionEnabled` feature flag for staged rollout.

## UX Scope By Surface

### watchOS — Watch App

**Tab 1 — Heart Rate:**
- Large BPM number in center with zone-colored ring
- Zone label below (Rest / Light / Fat Burn / Cardio / Peak)
- Source device label (e.g. "AirPods Pro")
- "No heart rate data" empty state when iPhone is not sending HR

**Tab 2 — Session:**
- Active session: gym name, elapsed timer, "End Session" button (red)
- No session: "Start Session" button with default gym name
- Starting/ending loading states

**Tab 3 — Alerts:**
- Badge count of active alerts
- List of recent alerts with device name, message, time
- Tap to acknowledge (relayed to iPhone)

**Tab 4 — Quick Actions:**
- Start session at default gym
- Toggle heart rate monitoring on/off

### iOS — WatchSyncManager Integration

- Invisible to user — runs in background
- Pushes session state changes to Watch automatically
- Pushes HR updates to Watch when HeartRateMonitor has new data
- Receives Watch commands and delegates to GymSessionManager
- Registers Watch notification token via existing push infrastructure

### Web — Health Dashboard

**Metrics Page Additions:**
- `HeartRateSummaryCard`: latest BPM, today's avg/min/max, zone distribution donut chart
- `ConnectedDevicesCard`: all registered devices with type icon, status badge, last seen
- `HealthSourcesCard`: data attribution — which devices contributed health data today
- `HeartRateSessionHistory`: expandable list of recent sessions with HR summary

### Backend — Unified Health Endpoint

- `GET /health/dashboard`: aggregates latest HR, today's session summaries, registered devices with health capability, source attribution
- Extends event source enum with `'watchos'`
- Extends device type enum with `'watch'`

## Success Criteria

- Watch displays live heart rate within 2 seconds of iPhone receiving a new HealthKit sample
- Session start/end from Watch reflects on iPhone, Dynamic Island, and backend within 3 seconds
- Web health dashboard loads heart rate summaries and device fleet in a single page load
- Push notifications reach the Watch within Apple's standard delivery time
- The feature flag gates the entire Watch experience for staged rollout
- All four surfaces show consistent data when viewing the same user's account

## Risks And Open Questions

- WatchConnectivity message delivery latency during background states — may need fallback to application context polling
- Whether the Watch should have its own HealthKit entitlement to read heart rate directly from the Watch's sensors (v2 consideration)
- Whether watchOS background app refresh is reliable enough for session timer updates when the Watch app is not foregrounded
- How to handle Watch disconnection from iPhone during a gym session (graceful degradation)
- Whether complication data (BPM on watch face) requires a separate complication target or can be driven from the app's data
- Battery impact of continuous WatchConnectivity messaging during long gym sessions
