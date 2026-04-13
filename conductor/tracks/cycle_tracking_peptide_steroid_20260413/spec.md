# Peptide And Steroid Cycle Tracking — Technical Spec

## Reverse-Engineered Reuse Paths

This feature should extend existing product patterns rather than inventing a fourth style of health logging.

### Backend

- `api/src/modules/dosing/routes.ts` is the closest domain analogue for dose/event history and preset substances.
- `api/src/modules/cycles/routes.ts` is the closest analogue for cycle-specific logging and date-window summaries.
- `api/src/modules/calendar/routes.ts` is the closest reporting analogue for zero-safe day and month aggregation across meals, water, workouts, and runs.
- `api/src/modules/health/routes.ts` is the closest example of a health-adjacent, user-scoped data domain.
- `api/src/routes/index.ts` shows the existing module registration pattern.

### iOS

- `client-ios/GearSnitch/Features/DosingCalculator/*` is the best interaction pattern for dose-centric logging and local history.
- `client-ios/GearSnitch/Features/Calendar/*` is the best month/day reporting pattern.
- `client-ios/GearSnitch/Features/Cycles/CycleTrackingView.swift` already owns the cycle day/month/year surfaces and is the correct home for the yearly medication graph.
- `client-ios/GearSnitch/App/MainTabView.swift` and `AppCoordinator.swift` show that v1 should integrate under existing tabs, not by adding a new permanent tab immediately.

### Web

- `web/src/pages/AccountPage.tsx` already owns account-adjacent tabs and a month heatmap.
- `web/src/pages/MetricsPage.tsx` already owns summary cards and lightweight reporting, and is the correct primary home for the yearly medication graph.
- `web/src/lib/api.ts` and React Query hooks are the browser integration model to follow.

## Architecture Overview

### Shared Contract Layer

Add the medication and cycle contracts to `shared/src/schemas/index.ts` and `shared/src/types/index.ts` first. Backend, iOS, and web should all bind to the same field names, date semantics, and mg-normalization rules before UI work begins.

### Backend Domain

Introduce a first-class `MedicationDose` domain object that can optionally link to a cycle. Do not overload `DosingHistory` as the source of truth, and do not force all medication logging through `CycleEntry` because the current `CycleEntry` shape requires `cycleId` and does not model oral medication as a first-class category.

### Backend Aggregation Layer

Expose medication-focused graph and summary endpoints and extend the existing calendar responses with additive medication overlays. Correlation means one unified same-day view keyed by `userId + dateKey`; it does not mean causal inference in v1.

### iOS Integration

Add medication and cycle DTOs plus view models. v1 should surface the yearly graph inside the existing cycle year view and surface medication-aware day correlation inside the existing activity calendar flow.

### Web Integration

Add medication and cycle API helpers, a `Cycles` tab inside `/account`, and a medication graph card on `/metrics`.

## Data Model

### `Cycle`

One document per user cycle.

Fields:

- `userId`
- `name`
- `type`: `peptide | steroid | mixed | other`
- `status`: `planned | active | paused | completed | archived`
- `startDate`
- `endDate` nullable
- `timezone`
- `notes` nullable
- `tags` optional string array
- `compounds` optional array of planned compounds:
  - `compoundName`
  - `compoundCategory`
  - `targetDose` nullable
  - `doseUnit`
  - `route` nullable
- `createdAt`, `updatedAt`

### `MedicationDose`

One document per logged medication event.

Fields:

- `userId`
- `cycleId` nullable
- `dateKey` as `YYYY-MM-DD`
- `dayOfYear` as `1..365` (or `366` on leap years)
- `category`: `steroid | peptide | oralMedication`
- `compoundName`
- `dose`
  - `value`
  - `unit`
- `doseMg` nullable but required for the first yearly graph
- `occurredAt`
- `notes` nullable
- `source`: `manual | ios | web | imported`
- `createdAt`, `updatedAt`

### `CycleEntry` Compatibility

If the current implementation keeps `CycleEntry` for cycle-local behavior, treat it as a compatibility or projection layer. New cross-platform clients should bind to `MedicationDose` semantics first.

Fields:

- `userId`
- `cycleId`
- `compoundName`
- `compoundCategory`: `peptide | steroid | support | pct | other`
- `route`: `injection | oral | topical | other`
- `occurredAt`
- `dateKey` as `YYYY-MM-DD`
- `plannedDose` nullable
- `actualDose` nullable
- `doseUnit`: `mg | mcg | iu | ml | units`
- `notes` nullable
- `source`: `manual | ios | web | imported`
- `createdAt`, `updatedAt`

### Optional Reference Data

If the product wants guided entry similar to `dosing/substances`, add a small preset catalog route. Keep the first version optional and additive.

## Shared Schemas And Types

Add schemas and types for at least:

- `createCycleSchema`
- `updateCycleSchema`
- `createMedicationDoseSchema`
- `updateMedicationDoseSchema`
- `medicationDoseCategorySchema`
- `medicationDoseEntrySchema`
- `medicationDailySummarySchema`
- `medicationYearGraphResponseSchema`
- `calendarMedicationOverlaySchema`
- `cycleStatusSchema`
- `cycleTypeSchema`
- `cycleDoseUnitSchema`
- `cycleRouteSchema`
- `CycleResponse`
- `MedicationDoseResponse`
- `CycleDaySummaryResponse`
- `CycleMonthSummaryResponse`
- `CycleYearSummaryResponse`
- `MedicationDaySummaryResponse`
- `MedicationMonthSummaryResponse`
- `MedicationYearGraphResponse`

## API Contracts

### Core CRUD

- `GET /cycles`
- `POST /cycles`
- `GET /cycles/:id`
- `PATCH /cycles/:id`
- `DELETE /cycles/:id`

### Medication Dose CRUD

- `GET /medications/doses?from=&to=&category=&page=&limit=`
- `POST /medications/doses`
- `PATCH /medications/doses/:doseId`
- `DELETE /medications/doses/:doseId`

### Optional Cycle-Linked Writes

- `POST /cycles/:id/entries`
- `PATCH /cycles/entries/:entryId`
- `DELETE /cycles/entries/:entryId`

Cycle-linked writes should either create/update a `MedicationDose` record under the hood or project into the medication aggregation layer.

### Reporting

- `GET /medications/day/:date`
- `GET /medications/month?year=YYYY&month=1-12`
- `GET /medications/graph/year?year=YYYY`
- `GET /cycles/day/:date`
- `GET /cycles/month?year=YYYY&month=1-12`
- `GET /cycles/year?year=YYYY`
- optional `GET /cycles/substances`

### Calendar Correlation

- `GET /calendar/month?year=YYYY&month=1-12&include=medication`
- `GET /calendar/day/:date?include=medication`

Calendar responses should keep current fields untouched and add optional medication overlay fields.

### Envelope Rules

- keep the existing `{ success, data, meta, error }` envelope
- use ISO 8601 strings for timestamps
- serialize IDs as strings
- include empty `entries`, `days`, or `months` collections explicitly instead of omitting them
- include pagination metadata on list endpoints
- treat medication overlay fields as additive so old clients remain decode-safe

## Reporting And Aggregation Rules

- Medication day view: group by `dateKey`, return raw dose entries plus totals by category.
- Medication month view: zero-fill one bucket per day for the requested month and include totals for `steroid`, `peptide`, and `oralMedication`.
- Medication yearly graph: return one point per day of year with three explicit series and a fixed axis contract:
  - x-axis `1..365`
  - y-axis `0..20 mg`
- Values above `20 mg` should not change the axis; they should be flagged in metadata or rendered as overflow/high-water markers by clients.
- Calendar month/day overlays should add:
  - `medication.entryCount`
  - `medication.totalDoseMg`
  - `medication.categoryDoseMg.{steroid,peptide,oralMedication}`
  - `medication.hasMedication`
- Use one authoritative timezone rule for `dateKey` and `dayOfYear`. Do not let iOS and web infer bucket rules independently.
- Compute summaries on read for v1. Add persisted rollups only if performance requires it later.
- Correlation in v1 is same-day colocation only; causal or timing-based correlations such as `withMeal` or `preWorkout` are explicitly deferred.

## iOS Integration Plan

- Add medication endpoints to `client-ios/GearSnitch/Core/Network/APIEndpoint.swift`.
- Add medication and cycle DTOs aligned to the backend summary payloads.
- Reuse `HeatmapCalendarView` and `DayDetailView` patterns for month/day reporting.
- Reuse the `DosingCalculator` and existing form interaction patterns for dose entry capture and editing.
- Start from existing entry points under Health/Profile/Dashboard. Do not add a new sixth tab in v1.
- Put the yearly graph inside `CycleTrackingView` year mode.
- Extend `HeatmapCalendarViewModel` and `DayDetailView` so medication totals render alongside meals, water, workouts, and runs.
- Use `Swift Charts` for the 365-day graph.

## Web Integration Plan

- Add typed medication and cycle clients in the web API layer using the existing `api.get/post/patch/delete` pattern.
- Add a new `Cycles` tab to `web/src/pages/AccountPage.tsx`.
- Add `CycleOverviewTab`, `CycleDetailTab`, `MedicationDoseEntryFlow`, and a medication-aware wrapper around the existing heatmap component.
- Add a medication summary card and `MedicationDoseYearGraph` to `web/src/pages/MetricsPage.tsx`.
- Keep v1 inside `/account`; only promote to a top-level `/cycles` route if the workflow becomes primary.
- The current repo has no charting dependency, so the implementation should either use simple SVG/canvas primitives first or add one dedicated chart library intentionally for the yearly graph.
- The account calendar should move from a single intensity count to structured day rendering that can show medication presence without losing meals/water/workout visibility.

## Validation, Privacy, And Policy

- require authentication for every route
- enforce ownership on every read/write path
- validate dates, enums, and dose units strictly
- cap page sizes and date-range windows
- treat cycle data as sensitive health-adjacent data
- make export and delete-account behavior explicit
- keep all product copy free of medical advice or protocol recommendations
- reject graph payloads that cannot be normalized to mg for the first `0..20 mg` chart contract

## Testing And Tooling

- add shared contract tests in `shared`
- add backend route and aggregation tests for empty state, ownership, pagination, medication graph buckets, and additive calendar overlays
- add iOS DTO decode tests and view-model tests for zero states
- add browser tests for the new account tab, medication graph card, and structured calendar rendering when web test tooling is introduced
- the main tooling prerequisite is schema-first shared contracts plus a clear mg-normalization rule; visualization tooling can follow later

## Open Technical Decisions

- whether overlapping cycles are supported in v1
- whether planning fields such as `plannedDose` are required at launch or deferred
- whether to ship preset substances immediately or start with freeform compound entry
- whether day bucketing follows account timezone or per-cycle timezone when they differ
- whether `MedicationDose` replaces `CycleEntry` outright or is introduced as the durable cross-platform source of truth while `CycleEntry` becomes a compatibility path
- how the first release handles dose units that cannot be cleanly represented as mg on a fixed 0..20 mg chart
