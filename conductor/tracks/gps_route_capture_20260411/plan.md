# GPS Route Capture And Replay — Execution Plan

## Context

- **Track**: `gps_route_capture_20260411`
- **Spec**: ship native GPS run capture plus backend and replay surfaces
- **Dependencies**: `run_tracking_metrics_20260411`
- **Execution Mode**: SEQUENTIAL

## Dependency Graph

```yaml
dag:
  nodes:
    - id: "1.1"
      name: "Add backend run model, routes, and serialization"
      depends_on: []
    - id: "1.2"
      name: "Add backend regression coverage for run endpoints"
      depends_on: ["1.1"]
    - id: "2.1"
      name: "Build iOS run-tracking core manager and models"
      depends_on: ["1.1"]
    - id: "2.2"
      name: "Ship iOS active run, history, and detail surfaces"
      depends_on: ["2.1"]
    - id: "3.1"
      name: "Add basic web run replay surface"
      depends_on: ["1.1"]
    - id: "4.1"
      name: "Validate API, web, and iOS run-tracking surfaces"
      depends_on: ["1.2", "2.2", "3.1"]
```

## Phase 1: Backend Run Contract

- [x] Task 1.1: Add backend run model, routes, and serialization
  - **Acceptance**: authenticated run start/stop/list/detail endpoints persist and return stable run summaries plus route geometry
  - **Files**: `api/src/models/Run.ts`, `api/src/modules/runs/routes.ts`, route mounting as needed
  - Added the `Run` model plus authenticated start, active, list, detail, and complete endpoints with stable run summaries and route payload serialization.
  - Mounted the new run routes in the API and aligned model exports so the backend surface is live end-to-end.

- [x] Task 1.2: Add backend regression coverage for run endpoints
  - **Acceptance**: tests prove run routes are mounted live and zero-state responses stay bounded
  - **Files**: `api/tests/*`
  - Extended backend regression coverage to prove the run routes are registered and zero-state responses stay bounded.

## Phase 2: iOS Run Capture

- [x] Task 2.1: Build iOS run-tracking core manager and models
  - **Acceptance**: location updates, timing, pace, distance, and local buffering behave predictably for an active run
  - **Files**: `client-ios/GearSnitch/Core/RunTracking/*`
  - Added the iOS run-tracking core manager and DTO/model layer for distance, pace, duration, route buffering, and backend sync.

- [x] Task 2.2: Ship iOS active run, history, and detail surfaces
  - **Acceptance**: users can start a run, finish it, review run history, and inspect a completed route
  - **Files**: `client-ios/GearSnitch/Features/RunTracking/*`
  - Added the active run and run history flows, wired them into the Xcode target, and exposed the surfaces from the existing workouts shell.

## Phase 3: Web Replay Surface

- [x] Task 3.1: Add basic web run replay surface
  - **Acceptance**: authenticated users can open a browser route viewer for completed runs without map/render crashes
  - **Files**: `web/src/pages/RunMapPage.tsx`, `web/src/components/maps/*`, routing/nav as needed
  - Added a protected `/runs` page plus an SVG-based `RunRoutePreview` component for safe browser replay without taking on a full map dependency.
  - Added authenticated header navigation for the new run replay surface.

## Phase 4: Validation

- [x] Task 4.1: Validate API, web, and iOS run-tracking surfaces
  - **Acceptance**: API checks, web build, and iOS simulator build pass or any pre-existing baseline failures are explicitly documented
  - **Files**: validation only
  - Fresh validation passed for `npm run lint --workspace=api`, `npm run test --workspace=api -- backend-core-services.test.cjs`, `npm run type-check --workspace=api`, `npm run build --workspace=api`, `npm run build --workspace=web`, and `xcodebuild -project client-ios/GearSnitch.xcodeproj -target GearSnitch -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build`.
  - Targeted lint on the new web files passed; repo-wide `npm run lint --workspace=web` still fails only on pre-existing shared UI and `StorePage` issues.

## Discovered Work

- Repo-wide `npm run lint --workspace=web` still fails on pre-existing `react-refresh/only-export-components` violations in `web/src/components/ui/badge.tsx`, `web/src/components/ui/button.tsx`, and `web/src/components/ui/tabs.tsx`.
- `web/src/pages/StorePage.tsx` still has pre-existing unused `eslint-disable` directives that fail the workspace lint run.
- `xcodebuild -scheme GearSnitch` is not a reliable validation path in this repo because a checked-in shared scheme is absent; target-based simulator builds are the stable compile gate.
