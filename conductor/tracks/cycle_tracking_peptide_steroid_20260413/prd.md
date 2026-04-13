# Peptide And Steroid Cycle Tracking

## Track ID

`cycle_tracking_peptide_steroid_20260413`

## Summary

Add a backend-owned, cross-platform medication and cycle-tracking domain that lets users log daily steroid, peptide, and oral medication doses, attach those doses to a cycle when relevant, and review them on both a yearly dose graph and a unified calendar that also shows meals, water intake, and gym/workout activity across iOS and web.

## Why This Track Exists

- `api/src/modules/dosing/routes.ts` proves the product already has a dose-adjacent domain, but it only stores isolated dose history and cannot represent a named cycle over time or a fixed yearly graph.
- `api/src/modules/cycles/routes.ts` proves the backend can support cycle-specific logging, but the current `CycleEntry` shape is not a clean general medication log because it requires `cycleId` and does not treat oral medication as a first-class category.
- `api/src/modules/calendar/routes.ts` proves the backend already supports zero-safe, date-window summaries that can power day and month drill-down UX for meals, water, workouts, and runs.
- iOS already has reusable calendar, health, dashboard, and cycle interaction patterns, but no unified medication graph or medication-aware calendar detail.
- the web app already has reusable account tabs, a month heatmap, and a metrics summary surface, but no medication graph or calendar overlay for doses.
- the `shared` package already exists for cross-platform schemas and types, so this feature should extend that layer instead of creating parallel DTOs per client.

## Problem Statement

Users can currently log doses, health data, calories, workouts, runs, and calendar activity, but they cannot:

- log one of three explicit medication dose categories for a specific day of the year: `steroid`, `peptide`, or `oral medication`
- see a yearly graph where the x-axis is day `1..365` and the y-axis is dose `0..20 mg`
- open a calendar day and understand medication doses in the same place as meals, water intake, and gym/workout activity
- use the same medication tracking model across iOS and web without one client inferring data the other one never receives

That makes the current dosing feature useful as a calculator or loose history log, but not as a unified medication and cycle tracker.

## Goals

- let users create and manage a cycle with a name, type, status, dates, notes, and planned compounds
- let users log a medication dose for a specific day with one explicit category: `steroid`, `peptide`, or `oral medication`
- support medication logging both inside a cycle and outside a cycle by treating medication doses as a first-class domain object
- provide a yearly medication graph with x-axis `day 1..365` and y-axis `0..20 mg`
- provide day, month, and year summaries without requiring clients to recompute rollups
- show medication doses in the same calendar surface as meals, water intake, and gym/workout activity
- keep iOS and web on the same backend contract and date-bucketing rules
- provide meaningful empty states and zero-safe reporting for new users and inactive cycles
- treat the feature as health-adjacent and user-scoped from the first release

## Non-Goals

- no medical advice, coaching, or protocol recommendations
- no autonomous scheduling, reminders, or adherence nudging in v1
- no social sharing, public profiles, or comparative analytics
- no new standalone cycle tab in iOS for the first release
- no top-level browser navigation item for cycles in the first release
- no attempt to infer medical meaning from correlations between doses, meals, hydration, or workouts in v1
- no non-mg chart axes in v1; doses that cannot be normalized to mg are out of scope for the first graph release

## MVP Scope

- backend cycle domain models plus a first-class medication-dose domain that can optionally link to a cycle
- shared schemas and types exported from `shared`
- cycle CRUD plus medication-dose CRUD
- medication-focused day, month, and year summary endpoints
- additive calendar overlays that show medication totals alongside meals, water intake, and gym/workout activity
- iOS integration as a secondary flow under existing Health/Profile/Dashboard patterns, with the yearly graph inside the current cycle surface and the correlated calendar inside the current activity calendar flow
- web integration as a new `Cycles` tab under `/account` plus a medication summary/graph card on `/metrics`
- privacy-safe export/delete compatibility and empty-state handling

## Primary User Stories

- a user can create a cycle and mark it planned, active, paused, completed, or archived
- a user can define one or more compounds within a cycle and keep notes on the cycle
- a user can log a medication dose on a specific date with dose, category, and notes
- a user can add that dose from a cycle flow and from a calendar/day flow
- a user can open a day view and see medication totals and entries in the same place as meals, water intake, and gym/workout activity
- a user can open a month view and see medication activity overlaid on the calendar
- a user can open a year view and see a `day 1..365` medication graph with separate steroid, peptide, and oral medication series
- a user can use the same account on iOS and web without seeing different cycle states or totals

## Product Requirements

1. The system must store a cycle as a first-class object, not as a client-side interpretation of `dosing` history.
2. The system must store medication doses separately from cycle metadata so individual events can be queried, edited, and deleted whether or not they belong to a cycle.
3. The medication domain must support exactly three first-release categories: `steroid`, `peptide`, and `oral medication`.
4. The backend must provide a yearly graph payload where:
   - the x-axis is day `1..365`
   - the y-axis is fixed to `0..20 mg`
   - the response contains one series per medication category
5. The backend must provide day and month summary endpoints with explicit zero-state payloads.
6. Calendar responses must support additive medication overlays without breaking current consumers that already render meals, water intake, and workouts.
7. The same contract must be usable by iOS and web without client-specific field translation.
8. The feature must remain authenticated, user-owned, and safe to export or delete alongside account data.

## UX Scope By Surface

### iOS

- reuse the existing tab shell; do not add a sixth fixed tab for v1
- entry points should come from existing Health/Profile/Dashboard patterns
- use `Cycle Summary -> Day Detail -> Month View -> Year View` as the preferred navigation flow
- place the yearly graph inside the existing cycle year surface
- reuse the current heatmap and day-detail mental model before inventing a new reporting interaction
- show correlated medication detail in the existing activity calendar day view

### Web

- add `Cycles` inside `/account` first, rather than promoting a top-level route immediately
- reuse the current month heatmap pattern for month activity
- add a medication summary card and yearly graph on `/metrics`
- only promote to `/cycles/:cycleId` and header navigation if the feature graduates into a primary browser workflow

## Success Criteria

- iOS and web both consume the same backend contract for cycle data
- iOS and web both consume the same backend contract for medication dose data and medication-aware calendar overlays
- the backend persists cycle and medication-dose data with stable ownership and date-indexed queries
- the yearly graph returns one point per day of year with three explicit medication series
- day, month, and year reporting return meaningful zero states for empty accounts and inactive cycles
- the feature lands without regressing the existing dosing history flow or current calendar consumers
- the feature is documented well enough that implementation can proceed track-first instead of rediscovery-first

## Risks And Open Questions

- whether overlapping cycles are supported in v1 or deferred
- whether medication doses outside a cycle are modeled as standalone records or the product requires a lightweight auto-created cycle wrapper
- whether day bucketing follows user timezone or cycle timezone when they differ
- whether compound reference data should be freeform only or include a backend preset list similar to `dosing/substances`
- how mg normalization works for units such as `mcg`, `iu`, `ml`, or `units`, and which of those units are excluded from the first yearly graph
- how much medication detail the month calendar can show before the cell UI becomes overloaded
- what disclaimer, age-gating, or retention policy is required for a health-adjacent logging feature
