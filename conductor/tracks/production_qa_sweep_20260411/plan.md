# Production QA Sweep — Execution Plan

## Context

- **Track**: `production_qa_sweep_20260411`
- **Spec**: clear validation debt and capture the final cross-surface verification state
- **Dependencies**: `device_priority_alarm_20260411`, `richer_web_dashboard_analytics_20260411`
- **Execution Mode**: SEQUENTIAL

## Dependency Graph

```yaml
dag:
  nodes:
    - id: "1.1"
      name: "Remove remaining validation-baseline debt needed for hard quality gates"
      depends_on: []
    - id: "1.2"
      name: "Run broad quality/build/test sweeps across the finished surfaces"
      depends_on: ["1.1"]
    - id: "2.1"
      name: "Capture cross-surface QA checklist results and manual blockers"
      depends_on: ["1.2"]
```

## Phase 1: Baseline Cleanup And Verification

- [x] Task 1.1: Remove remaining validation-baseline debt needed for hard quality gates
  - **Acceptance**: known lint/build/test baseline failures that block the final sweep are resolved or formally reclassified as external
  - **Files**: repo-wide touched validation/config files as needed

- [x] Task 1.2: Run broad quality/build/test sweeps across the finished surfaces
  - **Acceptance**: the broadest meaningful validation commands for the completed loop are executed and captured
  - **Files**: validation only

## Phase 2: QA Artifact And Blocker Log

- [x] Task 2.1: Capture cross-surface QA checklist results and manual blockers
  - **Acceptance**: one artifact records the final status of sign-in, devices, workouts, runs, notifications, metrics, and any remaining external setup requirements
  - **Files**: QA/retrospective artifacts as needed

## Discovered Work

- Cleared the remaining hard-gate lint debt by disabling the web fast-refresh rule for generated `src/components/ui/*` files, removing the stale `StorePage` console suppressions, and adding local flat ESLint configs for `worker` and `realtime`.
- Ran the broad repo-wide validation sweep successfully with `npm run build`, `npm run lint`, `npm run type-check`, `npm run test`, and a fresh iOS simulator `xcodebuild`.
- Captured the final cross-surface status and remaining portal/configuration blockers in `conductor/tracks/production_qa_sweep_20260411/qa-report.md`.
