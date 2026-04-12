# Realtime Worker Hardening — Execution Plan

## Context

- **Track**: `realtime_worker_hardening_20260411`
- **Spec**: harden queue processors, realtime event handling, and notification API contracts
- **Dependencies**: `gps_route_capture_20260411`
- **Execution Mode**: SEQUENTIAL

## Dependency Graph

```yaml
dag:
  nodes:
    - id: "1.1"
      name: "Replace notification API stubs with live persistence and preference handlers"
      depends_on: []
    - id: "1.2"
      name: "Create shared job/event utilities for idempotency, logging, and payload validation"
      depends_on: ["1.1"]
    - id: "2.1"
      name: "Implement worker processor logic for critical queues"
      depends_on: ["1.2"]
    - id: "2.2"
      name: "Harden realtime socket auth, room sync, and Redis fan-out"
      depends_on: ["1.2"]
    - id: "3.1"
      name: "Validate worker, realtime, and touched API surfaces"
      depends_on: ["2.1", "2.2"]
```

## Phase 1: Contracts And Shared Utilities

- [x] Task 1.1: Replace notification API stubs with live persistence and preference handlers
  - **Acceptance**: notification list/read/read-all/preferences flows return real data instead of `501`
  - **Files**: `api/src/modules/notifications/routes.ts`, supporting service/model files as needed

- [x] Task 1.2: Create shared job/event utilities for idempotency, logging, and payload validation
  - **Acceptance**: worker and realtime code paths stop depending on ad hoc placeholder job payload handling
  - **Files**: `worker/src/*`, `realtime/src/*`

## Phase 2: Runtime Hardening

- [x] Task 2.1: Implement worker processor logic for critical queues
  - **Acceptance**: alert, push, subscription, referral, store, and export processors have concrete logic and bounded failure behavior
  - **Files**: `worker/src/jobs/*`, `worker/src/index.ts`

- [x] Task 2.2: Harden realtime socket auth, room sync, and Redis fan-out
  - **Acceptance**: core realtime channels no longer rely on live-path TODOs for auth/session/device synchronization
  - **Files**: `realtime/src/index.ts`

## Phase 3: Validation

- [x] Task 3.1: Validate worker, realtime, and touched API surfaces
  - **Acceptance**: builds and targeted checks pass for the touched runtime services
  - **Files**: validation only

## Discovered Work

- Added `api/tests/realtime-worker-hardening.test.cjs` as a file-contract regression sweep for notification routes, worker utilities/jobs, and realtime auth/event wiring.
- `worker` and `realtime` both build and type-check cleanly after replacing placeholder queue processors and socket/session logic.
- `worker` and `realtime` workspace lint scripts still fail before code analysis because ESLint 9 is invoked without a workspace `eslint.config.*` file; this is an existing tooling baseline, not a regression introduced by this track.
