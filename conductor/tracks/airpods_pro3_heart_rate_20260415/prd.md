# AirPods Pro 3 Heart Rate Integration

## Track ID

`airpods_pro3_heart_rate_20260415`

## Summary

Integrate AirPods Pro 3 real-time heart rate monitoring into GearSnitch so users can see their live BPM on the Dynamic Island, lock screen Live Activity, and in-app dashboard during gym sessions and general use.

## Why This Track Exists

- AirPods Pro 3 include an optical heart rate sensor that writes instantaneous heart rate samples to HealthKit. GearSnitch already reads resting heart rate from HealthKit but does not consume live heart rate data.
- The iOS app already has a Live Activity and Dynamic Island implementation for gym sessions (`GymSessionLiveActivityWidget`, `LiveActivityManager`) that shows session timer and gym name, but no biometric data.
- The app already has a HealthKit integration (`HealthKitManager`) with authorization for `restingHeartRate` but not instantaneous `heartRate` or `heartRateVariabilitySDNN`.
- The dashboard already renders device status, gym sessions, and health metrics, but has no real-time biometric display.
- The backend already stores health metrics (`HealthMetric` model) with `resting_heart_rate` as a supported type, but does not store instantaneous heart rate snapshots or session-level HR summaries.
- Users who wear AirPods Pro 3 during workouts have no way to see their heart rate without switching apps.

## Problem Statement

Users wearing AirPods Pro 3 during gym sessions cannot see their live heart rate within GearSnitch. They must switch to the Apple Health app or a third-party app to check their BPM, which breaks their workout flow. The existing Live Activity and Dynamic Island show only gym name and timer, wasting valuable real-estate that could display the most important biometric during exercise.

## Goals

- Stream real-time heart rate from HealthKit into the app as AirPods Pro 3 produce new samples
- Display live BPM with heart rate zone classification in the Dynamic Island during gym sessions
- Display live BPM on the lock screen Live Activity banner during gym sessions
- Display live BPM with trend and zone on the in-app dashboard
- Persist heart rate snapshots to the backend for session-level HR summaries
- Detect when the heart rate source is AirPods Pro 3 and surface that context in the UI
- Provide heart rate zone classification: Rest, Light, Fat Burn, Cardio, Peak

## Non-Goals

- No Apple Watch heart rate support in this track (future companion app work)
- No heart rate alerts, threshold notifications, or zone coaching in v1
- No heart rate sharing or social features
- No historical heart rate charting beyond the session summary in v1
- No custom zone configuration in v1; use standard 5-zone model
- No writing heart rate data back to HealthKit
- No ECG, blood oxygen, or other AirPods Pro 3 health features in this track

## MVP Scope

- HealthKit anchored object query for `HKQuantityTypeIdentifier.heartRate` with real-time delivery of new samples
- Source-device detection to identify AirPods Pro 3 as the HR provider
- Heart rate zone classification using standard 5-zone model (Rest, Light, Fat Burn, Cardio, Peak)
- Updated `GymSessionAttributes.ContentState` to carry optional heart rate and zone data
- Dynamic Island: live BPM in compact trailing, BPM + zone in expanded view
- Lock screen Live Activity: BPM with heart icon and zone color
- Dashboard: real-time heart rate card with BPM, zone label, zone color, and source device name
- `LiveActivityManager` update loop that pushes new HR data to the Live Activity
- Backend `heart_rate` metric type in HealthMetric model for snapshot persistence
- Backend `POST /health/heart-rate/batch` endpoint for efficient bulk HR sample ingestion
- Backend `GET /health/heart-rate/session-summary` endpoint returning min/max/avg BPM and zone distribution for a gym session time window

## Primary User Stories

- A user wearing AirPods Pro 3 opens GearSnitch and sees their current heart rate on the dashboard without navigating to a separate screen
- A user starts a gym session and their Dynamic Island shows live BPM alongside the session timer
- A user glances at their locked phone during a workout and sees their current BPM on the lock screen Live Activity
- A user finishes a gym session and can see their average, min, and max heart rate for that session
- A user not wearing AirPods Pro 3 sees a graceful empty state indicating no heart rate source is detected

## Product Requirements

1. The system must use `HKAnchoredObjectQuery` to stream heart rate samples in real-time from HealthKit as they are produced by AirPods Pro 3.
2. The system must add `HKQuantityTypeIdentifier.heartRate` and `.heartRateVariabilitySDNN` to the HealthKit read authorization request.
3. Heart rate zone classification must follow the 5-zone model:
   - Rest: < 100 BPM
   - Light: 100-119 BPM
   - Fat Burn: 120-139 BPM
   - Cardio: 140-159 BPM
   - Peak: >= 160 BPM
4. The Dynamic Island compact trailing must show the current BPM with a heart icon when heart rate data is available, falling back to the session timer when it is not.
5. The Dynamic Island expanded view must show BPM, zone label, and zone color alongside existing gym name and timer.
6. The lock screen Live Activity must show BPM with a pulsing heart icon and zone-colored accent.
7. The in-app dashboard must show a heart rate card when live data is available, positioned above the device status section.
8. The `LiveActivityManager` must update the Live Activity content state whenever a new HR sample arrives, throttled to at most once per 2 seconds.
9. The backend must accept batched heart rate samples and deduplicate by userId + recordedAt timestamp.
10. The backend must provide a session summary endpoint that computes min, max, average BPM and zone distribution percentages for a given time window.
11. Heart rate monitoring must respect HealthKit authorization status and show appropriate permission prompts.
12. Heart rate monitoring must stop gracefully when the user ends a gym session or backgrounds the app for more than 5 minutes.

## UX Scope By Surface

### iOS — Dynamic Island

- **Compact trailing**: Heart icon (heart.fill) + BPM number, zone-colored. Falls back to timer if no HR data.
- **Expanded leading**: Keep existing gym icon.
- **Expanded trailing**: Keep session timer.
- **Expanded center**: Keep gym name.
- **Expanded bottom**: Add heart rate row showing BPM, zone label, and zone-colored indicator dot. Keep "End Session" button.
- **Minimal**: Pulsing heart icon when HR active, gym icon when not.

### iOS — Lock Screen Live Activity

- Add heart rate display to the right of the gym name / session status area.
- Show BPM in large rounded font with heart.fill icon.
- Zone-colored accent on the heart icon.
- Fallback: hide heart rate section when no HR data.

### iOS — Dashboard

- New `HeartRateCard` component positioned after gym session status, before device status.
- Shows: current BPM (large), zone label, zone color bar, source device name ("AirPods Pro"), last updated timestamp.
- Empty state: "No heart rate source detected" with a prompt to connect AirPods Pro 3.
- Tappable to navigate to a detail view (deferred, shows card only in v1).

### Backend

- Extend existing HealthMetric model to support `heart_rate` metric type.
- New batch ingestion endpoint for efficient HR sample upload.
- New session summary endpoint for post-workout HR analytics.

## Success Criteria

- Live heart rate appears in the Dynamic Island within 3 seconds of a new HealthKit sample arriving from AirPods Pro 3
- Lock screen Live Activity shows current BPM during active gym sessions
- Dashboard heart rate card updates in real-time when the app is foregrounded
- Backend successfully receives and deduplicates batched HR samples
- Session summary returns correct min/max/avg/zone data for completed gym sessions
- The feature degrades gracefully when AirPods Pro 3 are not connected or HealthKit authorization is denied

## Risks And Open Questions

- Whether HealthKit delivers AirPods Pro 3 heart rate samples fast enough for near-real-time display (expected ~1 sample per 1-5 seconds based on Apple documentation)
- Whether Live Activity update frequency limits (ActivityKit throttles updates) impact the perceived real-time experience
- Whether background HealthKit delivery is reliable enough during active gym sessions or requires foreground app presence
- How to handle the transition when AirPods Pro 3 are removed mid-session (ear detection)
- Whether the 5-zone model should use fixed thresholds or age-based max HR calculation (deferred to v2)
- Battery impact of continuous HealthKit anchored queries during long gym sessions
