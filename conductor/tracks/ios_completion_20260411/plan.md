# iOS Completion — Execution Plan

## Context

- **Track**: `ios_completion_20260411`
- **Spec**: Finish the highest-value remaining iOS work that now has real backend state behind it.
- **Dependencies**: `backend_core_services_20260411`
- **Overlap Check**: checked `backend_core_services_20260411`, `api/src/modules/auth/routes.ts`, `api/src/modules/sessions/routes.ts`, `api/src/modules/calendar/routes.ts`, current iOS dashboard/profile/store/gym/device view models, and `docs/HANDOFF.md`
- **Execution Mode**: `PARALLEL`

## Scope Decisions

### In Scope For This Track

- add live backend session-management endpoints for the existing iOS account session screen
- align iOS gym-session networking with the backend routes that already exist under `/sessions`
- normalize the iOS calendar decoder against the backend month-summary payload without rebuilding calendar UI
- fix the iOS session-management behavior that fails to log the user out when the current session is revoked
- remove the silent `501` dead-end from the manual checkout button and record payment work as an explicit follow-up

### Overlap / Do Not Rebuild Here

- device, gym, and store CRUD backends already shipped in `backend_core_services_20260411`
- browser sign-in and the broader web account/dashboard work belong to `web_auth_dashboard_20260411`
- Apple Pay / payment-intent architecture already lives under `/store/payments/*`; do not redesign payments here
- health, calories, workouts, referrals, notifications, and geofence-event feature work remain outside this track
- profile photo upload still lacks a backend media surface and should not be invented inside iOS completion

### Explicit Deferrals

- full non-Apple-Pay checkout support
  - current app code still points at `/store/checkout`, but real payment flows require intent creation and order confirmation work that should stay in a dedicated follow-up
- backend/API normalization for the web account calendar consumer
  - this track will make the iOS calendar tolerant of the current payload instead of changing the shared API contract mid-stream
- gym geofence evaluation, event ingestion, and nearby discovery
- any new run-tracking or metrics features

## Dependency Graph

```yaml
dag:
  nodes:
    - id: '1.1'
      name: 'Add live auth session-management routes'
      type: 'integration'
      files:
        - 'api/src/modules/auth/routes.ts'
      depends_on: []
      estimated_duration: '45m'
      phase: 1
    - id: '1.2'
      name: 'Align iOS gym session endpoints and response decoding to /sessions'
      type: 'code'
      files:
        - 'client-ios/GearSnitch/Core/Session/GymSessionManager.swift'
      depends_on: []
      estimated_duration: '45m'
      phase: 1
    - id: '1.3'
      name: 'Make iOS calendar month decoding compatible with backend day summaries'
      type: 'code'
      files:
        - 'client-ios/GearSnitch/Features/Calendar/HeatmapCalendarViewModel.swift'
      depends_on: []
      estimated_duration: '30m'
      phase: 1
    - id: '2.1'
      name: 'Harden iOS account session behavior around current-session revocation'
      type: 'code'
      files:
        - 'client-ios/GearSnitch/Core/Auth/SessionManager.swift'
      depends_on:
        - '1.1'
      estimated_duration: '30m'
      phase: 2
    - id: '2.2'
      name: 'Replace the manual checkout dead-end with explicit deferred UX'
      type: 'ui'
      files:
        - 'client-ios/GearSnitch/Features/Store/CheckoutView.swift'
      depends_on: []
      estimated_duration: '20m'
      phase: 2
    - id: '3.1'
      name: 'Run targeted API and iOS build verification for the touched flows'
      type: 'test'
      files:
        - 'api/src/modules/auth/routes.ts'
        - 'client-ios/GearSnitch/Core/Auth/SessionManager.swift'
        - 'client-ios/GearSnitch/Core/Session/GymSessionManager.swift'
        - 'client-ios/GearSnitch/Features/Calendar/HeatmapCalendarViewModel.swift'
        - 'client-ios/GearSnitch/Features/Store/CheckoutView.swift'
      depends_on:
        - '1.2'
        - '1.3'
        - '2.1'
        - '2.2'
      estimated_duration: '30m'
      phase: 3

  parallel_groups:
    - id: 'pg-1'
      tasks:
        - '1.1'
        - '1.2'
        - '1.3'
      conflict_free: true
    - id: 'pg-2'
      tasks:
        - '2.1'
        - '2.2'
      conflict_free: true
```

## Phase 1: Contract Alignment

### Tasks

- [x] Task 1.1: Add live auth session-management routes <!-- deps: none, parallel: pg-1 -->
  - **Type**: `integration`
  - **Acceptance**: `GET /auth/sessions`, `DELETE /auth/sessions/:id`, and `POST /auth/sessions/revoke-others` return active session data from the `Session` model and expose an `isCurrent` marker for the caller
  - **Files**: `api/src/modules/auth/routes.ts`
- [x] Task 1.2: Align iOS gym session endpoints and response decoding to `/sessions` <!-- deps: none, parallel: pg-1 -->
  - **Type**: `code`
  - **Acceptance**: start, end, and active-session calls use the current backend route contract and decode the live session payload without assuming the deprecated `/gym-sessions/*` shape
  - **Files**: `client-ios/GearSnitch/Core/Session/GymSessionManager.swift`
- [x] Task 1.3: Make iOS calendar month decoding compatible with backend day summaries <!-- deps: none, parallel: pg-1 -->
  - **Type**: `code`
  - **Acceptance**: the heatmap view model can decode the current `/calendar/month` response envelope and still feed the existing `DayActivity` UI model
  - **Files**: `client-ios/GearSnitch/Features/Calendar/HeatmapCalendarViewModel.swift`

## Phase 2: Client Behavior Hardening

### Tasks

- [x] Task 2.1: Harden iOS account session behavior around current-session revocation <!-- deps: 1.1, parallel: pg-2 -->
  - **Type**: `code`
  - **Acceptance**: revoking the current session triggers logout correctly, other-session revocation refreshes local state cleanly, and the session list remains compatible with the live backend response
  - **Files**: `client-ios/GearSnitch/Core/Auth/SessionManager.swift`
- [x] Task 2.2: Replace the manual checkout dead-end with explicit deferred UX <!-- deps: none, parallel: pg-2 -->
  - **Type**: `ui`
  - **Acceptance**: the manual checkout path no longer blindly hits the known `501` route; instead the app surfaces the deferral clearly while preserving the already-live catalog/cart/order flows
  - **Files**: `client-ios/GearSnitch/Features/Store/CheckoutView.swift`

## Phase 3: Verification

### Tasks

- [x] Task 3.1: Run targeted API and iOS build verification for the touched flows <!-- deps: 1.2, 1.3, 2.1, 2.2 -->
  - **Type**: `test`
  - **Acceptance**: the API workspace still builds after the auth-route changes and the iOS target builds with the updated session/calendar/store code paths
  - **Files**: `api/src/modules/auth/routes.ts`, `client-ios/GearSnitch/Core/Auth/SessionManager.swift`, `client-ios/GearSnitch/Core/Session/GymSessionManager.swift`, `client-ios/GearSnitch/Features/Calendar/HeatmapCalendarViewModel.swift`, `client-ios/GearSnitch/Features/Store/CheckoutView.swift`

## Validation Commands

- `npm run build --workspace=api`
- `xcodebuild -project client-ios/GearSnitch.xcodeproj -target GearSnitch -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build`

## Plan Evaluation

- **Date**: `2026-04-12`
- **Evaluator**: `loop-plan-evaluator`
- **Verdict**: `PASS`
- **Summary**:
  - scope stays inside the spec and avoids rebuilding the backend CRUD work that already landed in `backend_core_services_20260411`
  - the only backend addition is auth session-management, which is required by an existing iOS surface and does not introduce a new product decision
  - the DAG is conflict-free for the Phase 1 and Phase 2 parallel groups, and the remaining work is explicitly deferred instead of expanding into payments or health features
  - board review was skipped because this plan resolves concrete contract mismatches rather than introducing a new architecture or product direction

## Discovered Work

- if the web account calendar should consume the richer day-summary shape later, capture that normalization inside `web_auth_dashboard_20260411` instead of changing the shared API contract in this iOS track
- if manual card checkout must become functional before launch, create a dedicated store-payments follow-up track that wires `PaymentService` intent creation into the existing cart and checkout UI

## Execution Results

- `npm run build --workspace=api` passed
- `xcodebuild -project client-ios/GearSnitch.xcodeproj -target GearSnitch -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build` passed
- the first iOS build failed because `DayActivity` lost its synthesized memberwise initializer after the custom decoder was added; restoring an explicit initializer resolved the regression without changing the runtime contract work

## Execution Evaluation

- **Date**: `2026-04-12`
- **Evaluator**: `loop-execution-evaluator`
- **Verdict**: `PASS`
- **Summary**:
  - auth session-management is now backed by live API routes that match the existing iOS account screen
  - iOS gym-session and calendar flows now tolerate the current backend contracts without requiring a risky shared API reshape
  - manual checkout no longer falls through to the known `501` endpoint; the app now surfaces that deferral explicitly while leaving Apple Pay intact
