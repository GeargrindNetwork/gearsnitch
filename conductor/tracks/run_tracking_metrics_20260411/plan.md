# Run Tracking And Metrics — Execution Plan

## Context

- **Track**: `run_tracking_metrics_20260411`
- **Spec**: activate live workout contracts and ship the first authenticated browser metrics surface
- **Dependencies**: `backend_core_services_20260411`, `web_auth_dashboard_20260411`, `ios_completion_20260411`
- **Overlap Check**: checked completed tracks in `conductor/tracks.md`; auth/account/calendar foundation already landed, but workout APIs and browser metrics remain open
- **Execution Mode**: SEQUENTIAL

## Dependency Graph

```yaml
dag:
  nodes:
    - id: "1.1"
      name: "Implement live workout API routes and serializers"
      type: "code"
      files:
        - "api/src/modules/workouts/routes.ts"
        - "api/src/models/Workout.ts"
      depends_on: []
      estimated_duration: "60m"
      phase: 1
    - id: "1.2"
      name: "Add workout metrics aggregation endpoint"
      type: "code"
      files:
        - "api/src/modules/workouts/routes.ts"
      depends_on: ["1.1"]
      estimated_duration: "45m"
      phase: 1
    - id: "2.1"
      name: "Align iOS workout DTOs and save payloads with backend contract"
      type: "code"
      files:
        - "client-ios/GearSnitch/Core/Network/APIEndpoint.swift"
        - "client-ios/GearSnitch/Features/Workouts/WorkoutListViewModel.swift"
        - "client-ios/GearSnitch/Features/Workouts/ActiveWorkoutViewModel.swift"
        - "client-ios/GearSnitch/Features/Workouts/WorkoutDetailView.swift"
      depends_on: ["1.1"]
      estimated_duration: "45m"
      phase: 2
    - id: "2.2"
      name: "Expose the live workouts feature from the iOS tab shell"
      type: "ui"
      files:
        - "client-ios/GearSnitch/App/MainTabView.swift"
      depends_on: ["2.1"]
      estimated_duration: "15m"
      phase: 2
    - id: "3.1"
      name: "Build protected web metrics page"
      type: "ui"
      files:
        - "web/src/pages/MetricsPage.tsx"
        - "web/src/App.tsx"
        - "web/src/components/layout/Header.tsx"
      depends_on: ["1.2"]
      estimated_duration: "60m"
      phase: 3
    - id: "4.1"
      name: "Validate touched surfaces and close track artifacts"
      type: "test"
      files:
        - "api/package.json"
        - "web/package.json"
        - "client-ios/GearSnitch.xcodeproj/project.pbxproj"
      depends_on: ["2.2", "3.1"]
      estimated_duration: "45m"
      phase: 4
  parallel_groups: []
```

## Phase 1: Backend Contracts

### Tasks

- [x] Task 1.1: Implement live workout API routes and serializers <!-- deps: none -->
  - **Type**: code
  - **Acceptance**: authenticated clients can create, list, read, update, delete, and complete workouts without `501` responses
  - **Files**: `api/src/modules/workouts/routes.ts`, optional model/utility touches if needed
  - Replaced the workout route stubs with authenticated CRUD, completion handling, response serialization, and zero-safe helpers.
  - Added an API regression assertion so the route surface cannot silently fall back to placeholder handlers.

- [x] Task 1.2: Add workout metrics aggregation endpoint <!-- deps: 1.1 -->
  - **Type**: code
  - **Acceptance**: `GET /workouts/metrics/overview` returns zero-safe analytics derived from workouts and gym sessions
  - **Files**: `api/src/modules/workouts/routes.ts`
  - Added `GET /workouts/metrics/overview` with summary totals, streaks, distributions, and recent-workout history backed by workouts plus gym sessions.

## Phase 2: iOS Workout Activation

### Tasks

- [x] Task 2.1: Align iOS workout DTOs and save payloads with backend contract <!-- deps: 1.1 -->
  - **Type**: code
  - **Acceptance**: workout history decodes cleanly, exercise counts render correctly, and ending a workout sends entered exercises and metadata
  - **Files**: `client-ios/GearSnitch/Core/Network/APIEndpoint.swift`, `client-ios/GearSnitch/Features/Workouts/*`
  - Updated workout DTOs and request bodies to match the live backend envelope.
  - Ending an active workout now persists entered exercises, timestamps, and source metadata instead of sending placeholder payloads.

- [x] Task 2.2: Expose the live workouts feature from the iOS tab shell <!-- deps: 2.1 -->
  - **Type**: ui
  - **Acceptance**: the Workouts tab opens `WorkoutListView` instead of a placeholder
  - **Files**: `client-ios/GearSnitch/App/MainTabView.swift`
  - Replaced the placeholder workouts tab entry with the live workout history flow.

## Phase 3: Web Metrics Surface

### Tasks

- [x] Task 3.1: Build protected web metrics page <!-- deps: 1.2 -->
  - **Type**: ui
  - **Acceptance**: authenticated browser users can navigate to `/metrics` and see live metrics plus recent workouts
  - **Files**: `web/src/pages/MetricsPage.tsx`, `web/src/App.tsx`, `web/src/components/layout/Header.tsx`
  - Added a protected `/metrics` page with summary cards, distributions, streaks, and recent workouts.
  - Added authenticated navigation to the new metrics surface from the shared header.

## Phase 4: Validation And Closeout

### Tasks

- [x] Task 4.1: Validate touched surfaces and close track artifacts <!-- deps: 2.2, 3.1 -->
  - **Type**: test
  - **Acceptance**: API quality commands, web build, and iOS simulator build complete successfully or any residual failures are documented as pre-existing
  - **Files**: validation only plus track artifact updates
  - Fresh validation passed for `npm run test --workspace=api -- backend-core-services.test.cjs`, `npm run lint --workspace=api`, `npm run type-check --workspace=api`, `npm run build --workspace=api`, `npm run build --workspace=web`, and `xcodebuild -project client-ios/GearSnitch.xcodeproj -target GearSnitch -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build`.
  - `npm run lint --workspace=web` still fails on pre-existing shared UI fast-refresh exports plus stale `StorePage` eslint-disable directives; no new metrics-page lint issues were introduced.

## Discovered Work

- `xcodebuild -scheme GearSnitch` is not a reliable validation path in this repo because a checked-in shared scheme file is absent; target-based simulator builds are the stable compile gate.
- Remaining run-tracking scope is now the GPS-specific follow-up: continuous route capture, polyline storage, and replay, not the already-shipped workout/metrics foundation.
