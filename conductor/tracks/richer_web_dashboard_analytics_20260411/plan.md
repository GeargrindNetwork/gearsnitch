# Richer Web Dashboard Analytics — Execution Plan

## Context

- **Track**: `richer_web_dashboard_analytics_20260411`
- **Spec**: extend `/metrics` into the richer dashboard called for in the handoff
- **Dependencies**: `gps_route_capture_20260411`, `realtime_worker_hardening_20260411`
- **Execution Mode**: SEQUENTIAL

## Dependency Graph

```yaml
dag:
  nodes:
    - id: "1.1"
      name: "Extend backend/browser metrics contracts for richer dashboard analytics"
      depends_on: []
    - id: "2.1"
      name: "Add richer browser analytics cards, trends, and drill-downs"
      depends_on: ["1.1"]
    - id: "2.2"
      name: "Add device status cards and run-oriented gallery surfaces"
      depends_on: ["1.1"]
    - id: "3.1"
      name: "Validate touched web and backend surfaces"
      depends_on: ["2.1", "2.2"]
```

## Phase 1: Analytics Contract Expansion

- [x] Task 1.1: Extend backend/browser metrics contracts for richer dashboard analytics
  - **Acceptance**: distance totals, trends, and device-status-ready data are available to the web app through stable contracts
  - **Files**: touched analytics endpoints/hooks as needed

## Phase 2: Browser Dashboard Upgrade

- [x] Task 2.1: Add richer browser analytics cards, trends, and drill-downs
  - **Acceptance**: `/metrics` exposes more than the current summary cards and recent workouts list
  - **Files**: `web/src/pages/MetricsPage.tsx`, supporting components/hooks

- [x] Task 2.2: Add device status cards and run-oriented gallery surfaces
  - **Acceptance**: users can inspect run-oriented browser analytics and live-ish device status without placeholder cards
  - **Files**: `web/src/pages/*`, `web/src/components/*`

## Phase 3: Validation

- [x] Task 3.1: Validate touched web and backend surfaces
  - **Acceptance**: builds pass and any pre-existing lint baseline issues remain explicitly separated from new work
  - **Files**: validation only

## Discovered Work

- Expanded `GET /workouts/metrics/overview` to aggregate run distance trends, recent run gallery data, and device status summaries alongside the existing workout metrics payload.
- Rebuilt `web/src/pages/MetricsPage.tsx` into a fuller authenticated dashboard with run trend cards, run gallery drill-downs, and live-ish device status cards while preserving explicit zero-data states.
- `npm run lint --workspace=web` still fails on the pre-existing `react-refresh/only-export-components` issues in `web/src/components/ui/{badge,button,tabs}.tsx` plus unused disable comments in `web/src/pages/StorePage.tsx`; the richer dashboard slice did not add new web lint failures.
