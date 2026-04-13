# Peptide And Steroid Cycle Tracking — Execution Plan

## Context

- **Track**: `cycle_tracking_peptide_steroid_20260413`
- **PRD**: `conductor/tracks/cycle_tracking_peptide_steroid_20260413/prd.md`
- **Spec**: `conductor/tracks/cycle_tracking_peptide_steroid_20260413/spec.md`
- **Related Existing Patterns**: dosing history, calendar month/day aggregation, workout metrics overview, shared schema exports
- **Research Basis**: reverse-engineered by three SEV research lanes covering backend/contracts, iOS integration, and web integration
- **Execution Mode**: SEQUENTIAL

## Dependency Graph

```yaml
dag:
  nodes:
    - id: "0.1"
      name: "Reverse-engineer backend, iOS, and web integration patterns"
      type: "research"
      files:
        - "api/src/modules/dosing/routes.ts"
        - "api/src/modules/calendar/routes.ts"
        - "client-ios/GearSnitch/Features/*"
        - "web/src/pages/*"
      depends_on: []
      estimated_duration: "completed"
      phase: 0
    - id: "0.2"
      name: "Write PRD and technical spec from the codebase"
      type: "documentation"
      files:
        - "conductor/tracks/cycle_tracking_peptide_steroid_20260413/prd.md"
        - "conductor/tracks/cycle_tracking_peptide_steroid_20260413/spec.md"
        - "conductor/tracks/cycle_tracking_peptide_steroid_20260413/plan.md"
      depends_on: ["0.1"]
      estimated_duration: "completed"
      phase: 0
    - id: "1.1"
      name: "Define shared cycle schemas and types"
      type: "code"
      files:
        - "shared/src/schemas/index.ts"
        - "shared/src/types/index.ts"
      depends_on: ["0.2"]
      estimated_duration: "45m"
      phase: 1
    - id: "1.2"
      name: "Add cycle models and indexes"
      type: "code"
      files:
        - "api/src/models/Cycle.ts"
        - "api/src/models/CycleEntry.ts"
        - "api/src/models/index.ts"
      depends_on: ["1.1"]
      estimated_duration: "60m"
      phase: 1
    - id: "1.3"
      name: "Implement cycle CRUD and reporting routes"
      type: "code"
      files:
        - "api/src/modules/cycles/routes.ts"
        - "api/src/routes/index.ts"
      depends_on: ["1.2"]
      estimated_duration: "90m"
      phase: 1
    - id: "2.1"
      name: "Wire iOS networking and DTOs to shared cycle contracts"
      type: "code"
      files:
        - "client-ios/GearSnitch/Core/Network/APIEndpoint.swift"
        - "client-ios/GearSnitch/Features/*"
      depends_on: ["1.3"]
      estimated_duration: "60m"
      phase: 2
    - id: "2.2"
      name: "Add iOS cycle summary, day, month, and year surfaces"
      type: "code"
      files:
        - "client-ios/GearSnitch/Features/*"
        - "client-ios/GearSnitch/App/*"
      depends_on: ["2.1"]
      estimated_duration: "90m"
      phase: 2
    - id: "3.1"
      name: "Add web cycle API hooks and account tab integration"
      type: "code"
      files:
        - "web/src/lib/*"
        - "web/src/pages/AccountPage.tsx"
        - "web/src/components/*"
      depends_on: ["1.3"]
      estimated_duration: "60m"
      phase: 3
    - id: "3.2"
      name: "Add web cycle summary reporting to metrics and year view"
      type: "code"
      files:
        - "web/src/pages/MetricsPage.tsx"
        - "web/src/components/*"
      depends_on: ["3.1"]
      estimated_duration: "60m"
      phase: 3
    - id: "4.1"
      name: "Add backend contract and aggregation tests"
      type: "test"
      files:
        - "api/tests/*"
        - "shared/src/*"
      depends_on: ["1.3"]
      estimated_duration: "45m"
      phase: 4
    - id: "4.2"
      name: "Run cross-surface verification and quality commands"
      type: "verification"
      files:
        - "api/*"
        - "client-ios/*"
        - "web/*"
      depends_on: ["2.2", "3.2", "4.1"]
      estimated_duration: "45m"
      phase: 4
  parallel_groups: []
```

## Phase 0: Reverse Engineering And Documentation

### Tasks

- [x] Task 0.1: Reverse-engineer backend, iOS, and web integration patterns
  - **Acceptance**: three research lanes identify reusable code patterns, missing contracts, and tooling needs
- [x] Task 0.2: Write PRD and technical spec from the codebase
  - **Acceptance**: product intent, architecture, and implementation sequencing are documented in the track folder

## Phase 1: Backend Contract

### Tasks

- [ ] Task 1.1: Define shared cycle schemas and types
  - **Acceptance**: cycle plan/entry/report payloads are exported from `shared` and can be consumed by both clients
- [ ] Task 1.2: Add cycle models and indexes
  - **Acceptance**: cycles and entries persist with user-scoped, date-indexed queries
- [ ] Task 1.3: Implement cycle CRUD and reporting routes
  - **Acceptance**: authenticated clients can create, update, list, and aggregate cycle data by day/month/year

## Phase 2: Client Integration

### Tasks

- [ ] Task 2.1: Wire iOS networking and DTOs to shared cycle contracts
  - **Acceptance**: iOS can request cycle CRUD and summary endpoints using the shared response shapes
- [ ] Task 2.2: Add iOS cycle summary, day, month, and year surfaces
  - **Acceptance**: the iOS app exposes cycle tracking from existing navigation without adding a new permanent tab in v1

## Phase 3: Web Integration

### Tasks

- [ ] Task 3.1: Add web cycle API hooks and account tab integration
  - **Acceptance**: authenticated web users can open a cycle tab under `/account` and render zero-safe cycle data
- [ ] Task 3.2: Add web cycle summary reporting to metrics and year view
  - **Acceptance**: the browser shows cycle summaries by month and year using existing visual patterns or a consciously added chart layer

## Phase 4: Verification

### Tasks

- [ ] Task 4.1: Add backend contract and aggregation tests
  - **Acceptance**: API tests cover empty state, ownership checks, and the day/month/year aggregations
- [ ] Task 4.2: Run cross-surface verification and quality commands
  - **Acceptance**: touched backend, iOS, and web surfaces pass their relevant quality gates and any pre-existing baseline issues remain explicitly separated

## Notes

- Start by reusing the dosing/calendar aggregation patterns instead of inventing a new reporting stack.
- Keep the first release read/write for cycle tracking only; defer any policy, alerting, or recommendation layer.
- Keep the backend as source of truth for cycle state. Local persistence should only support drafts or offline convenience.

## UI Action Plan — 2026-04-13

### Goal

Turn the existing read/reporting surfaces into actionable cycle and medication workflows across web and iOS without changing the product constraints already set in the PRD.

### Guardrails

- Keep web cycle work under `/account` before promoting it into top-level navigation.
- Keep iOS cycle work inside existing Health, calendar, and cycle flows; do not add a new permanent tab in v1.
- Reuse the current month heatmap, day detail, and year graph instead of inventing parallel UI patterns.
- Keep the backend contract as the source of truth for day/month/year summaries and all cycle or medication writes.

### Priority Order

1. Add write flows where users already see cycle and medication data.
2. Add day-level drilldown and quick actions.
3. Expand cycle surfaces from summary panels into workflow surfaces.
4. Make charts interactive.
5. Polish empty states and navigation handoffs.

### Sprint 1: Make The Surfaces Writable

- [ ] UI-1: Confirm shared/backend write coverage for cycle create/update/status and medication create/update/delete → Verify: both clients can complete create, edit, and delete flows without client-only field transforms
- [ ] UI-2: Add web `Create Cycle` and `Log Medication` entry points from `CyclesPanel` and `/metrics` → Verify: a browser user can create a cycle and log a dose end to end
- [ ] UI-3: Add iOS medication entry and edit sheets from `DayDetailView` and `CycleTrackingView` → Verify: an iOS user can create, edit, and delete a medication dose without leaving the current flow

### Sprint 2: Add Drilldown And Workflow Depth

- [ ] UI-4: Add a web day-detail panel or drawer from calendar cells showing medication, meals, water, workouts, and runs plus quick actions → Verify: clicking a day opens a correlated daily drilldown with same-day data and action buttons
- [ ] UI-5: Expand the web cycles tab from summary cards into a cycle detail workflow with timeline, compounds, notes, and status actions → Verify: an active cycle can be opened, reviewed, and updated from the browser
- [ ] UI-6: Add iOS cycle create/edit/status management without adding a new tab → Verify: a user can create a cycle and change its status from the current Health or cycle flow

### Sprint 3: Improve Analysis And Guidance

- [ ] UI-7: Add interactive chart behavior to the medication year graph on both platforms → Verify: users can isolate categories, inspect daily values, and understand overflow beyond the fixed 20 mg axis
- [ ] UI-8: Strengthen empty states, error states, and cross-links from dashboard, calendar, and metrics surfaces → Verify: every zero or error state points to a concrete next action instead of a dead end

### Verification

- [ ] UI-9: Run targeted cross-surface validation for the UI slice → Verify: web build and lint pass on touched files, iOS simulator build passes, and the create → view → edit → delete smoke flow succeeds on both clients

### First Execution Slice

- Web:
  - add `Create Cycle` modal in `CyclesPanel`
  - add `Log Medication` modal from `CyclesPanel` and `MetricsPage`
  - add clickable calendar day drilldown
- iOS:
  - add `Log Medication` action from `DayDetailView`
  - add medication entry/edit sheet from `CycleTrackingView`
  - add minimal cycle create/edit/status sheet
- Shared acceptance:
  - user creates a cycle
  - user logs a medication dose
  - calendar day, cycle summary, and year graph reflect the change
  - user edits or deletes the same dose from UI
