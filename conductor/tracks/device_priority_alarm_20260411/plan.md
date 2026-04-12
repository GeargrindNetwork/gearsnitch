# Device Priority Alarm And Favorites — Execution Plan

## Context

- **Track**: `device_priority_alarm_20260411`
- **Spec**: ship favorite-device persistence and BLE alarm/disconnect polish
- **Dependencies**: `realtime_worker_hardening_20260411`
- **Execution Mode**: SEQUENTIAL

## Dependency Graph

```yaml
dag:
  nodes:
    - id: "1.1"
      name: "Add favorite and nickname device fields to the persisted contract"
      depends_on: []
    - id: "2.1"
      name: "Expose favorite and nickname controls in iOS device surfaces"
      depends_on: ["1.1"]
    - id: "2.2"
      name: "Refine BLE signal thresholds and disconnect UX"
      depends_on: ["2.1"]
    - id: "3.1"
      name: "Validate touched API and iOS surfaces"
      depends_on: ["2.2"]
```

## Phase 1: Device Contract

- [x] Task 1.1: Add favorite and nickname device fields to the persisted contract
  - **Acceptance**: device APIs and persisted models can store priority metadata without placeholder/local-only state
  - **Files**: `api/src/models/Device.ts`, touched device routes/services, iOS network models as needed

## Phase 2: iOS Priority And Alarm UX

- [x] Task 2.1: Expose favorite and nickname controls in iOS device surfaces
  - **Acceptance**: users can favorite and rename devices from the app, and favorites sort first in relevant lists
  - **Files**: `client-ios/GearSnitch/Features/Devices/*`

- [x] Task 2.2: Refine BLE signal thresholds and disconnect UX
  - **Acceptance**: disconnect handling clearly distinguishes ending a session from escalating to lost gear, with improved threshold behavior
  - **Files**: `client-ios/GearSnitch/Core/BLE/*`

## Phase 3: Validation

- [x] Task 3.1: Validate touched API and iOS surfaces
  - **Acceptance**: the touched device/alarm surfaces compile and any targeted checks pass
  - **Files**: validation only

## Discovered Work

- Added persisted `nickname` and `isFavorite` device metadata to the API contract, iOS DTOs, and BLE metadata sync path so favorites sort first across device-facing surfaces.
- Added `api/tests/device-priority-alarm.test.cjs` as a focused regression sweep covering the device priority contract, favorite/nickname UI wiring, and the disconnect decision path.
- Replaced the forced reconnect-timeout panic escalation with an explicit end-session vs lost-gear prompt and recalibrated BLE thresholds/alert cadence to reduce false positives.
