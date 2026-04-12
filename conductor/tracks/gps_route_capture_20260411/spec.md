# GPS Route Capture And Replay

## Track ID

`gps_route_capture_20260411`

## Summary

Add the real run-tracking slice that is still missing from GearSnitch: native iOS GPS capture, backend run persistence, and basic replay surfaces for completed runs.

## Why This Track Exists

- the workout-and-metrics foundation shipped, but continuous GPS run capture is still absent
- `docs/HANDOFF.md` still calls out run tracking as a first-class missing feature across iOS, backend, and web
- richer browser analytics and notification automation need real run data instead of placeholder assumptions

## In Scope

- add a backend `Run` model plus authenticated run CRUD/start-stop/detail endpoints
- add iOS run-tracking core state, location recording, and route buffering
- build iOS active run, run history, and run detail/replay surfaces
- add a basic web run replay/map surface for persisted runs
- support zero-state and interrupted-session recovery behavior without crashing the clients

## Out Of Scope

- social sharing of run maps
- achievements or streak badges
- Apple Watch companion behavior
- broad notification automation beyond the minimum persistence/replay contracts
- public marketing or landing-page redesign

## Acceptance Criteria

1. Authenticated clients can create, stop, list, and read runs through non-stub backend endpoints.
2. iOS can record an active run with duration, distance, pace, and route points, then persist the completed run.
3. iOS users can view a run history list and open a completed run detail surface with route replay data.
4. Browser users can open a basic run replay surface that renders the persisted route geometry for a completed run.
5. New or run-less accounts receive stable zero-state responses instead of route/map errors.
6. Validation passes for the touched surfaces: API checks, web build, and iOS simulator build.

## Dependencies

- `run_tracking_metrics_20260411`

## Notes

This track intentionally delivers the durable run-data plane first. Richer dashboard analytics and notification behavior should layer on top of this track instead of inventing parallel run summaries.
