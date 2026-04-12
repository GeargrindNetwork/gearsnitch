# Run Tracking And Metrics

## Track ID

`run_tracking_metrics_20260411`

## Summary

Ship the first concrete implementation of the deferred run-tracking-and-metrics work by activating live workout tracking contracts, exposing workout history in iOS, and adding a protected browser metrics page backed by a real aggregation endpoint.

## Why This Track Exists

- the API still returns `501` for the entire workout surface
- iOS already contains workout history and active workout UI, but it cannot persist or load real data
- the web app has no authenticated metrics surface despite account and calendar data now being live

## In Scope

- implement live workout CRUD and completion routes in the API
- add a metrics aggregation endpoint using gym sessions and workouts
- align iOS workout models and request payloads with the backend contract
- make the iOS Workouts tab render the live workout feature instead of a placeholder
- add a protected web metrics page using the shared auth runtime and the new metrics endpoint

## Out Of Scope

- continuous GPS run recording
- route polyline storage or map replay
- realtime socket or worker hardening
- new push-notification or background-job behavior
- redesign of the landing page or public marketing navigation

## Acceptance Criteria

1. Authenticated API clients can create, list, read, update, delete, and complete workouts without `501` stubs.
2. The workout response shape is stable and consumable by the existing iOS workout screens without local placeholder assumptions.
3. The iOS Workouts tab opens the real workout history flow, and ending an active workout persists entered exercises.
4. Authenticated web users can open a `/metrics` page that renders real session/workout analytics and recent workout history.
5. New accounts receive valid zero-state metrics responses instead of errors.
6. Validation passes for the touched surfaces: API quality commands, web build, and iOS simulator build.

## Dependencies

- `backend_core_services_20260411`
- `web_auth_dashboard_20260411`
- `ios_completion_20260411`

## Notes

This track intentionally uses the existing `Workout` model as the first implementation vehicle. Dedicated GPS run capture remains a follow-up once this shared metrics foundation is live.
