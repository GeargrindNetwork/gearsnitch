# Realtime Worker Hardening

## Track ID

`realtime_worker_hardening_20260411`

## Summary

Replace the remaining realtime, queue, and notification stubs with durable implementations so the live product can fan out device, alert, subscription, and run-related events safely.

## Why This Track Exists

- `worker/` still contains stub job processors for critical queues
- `realtime/` still has TODO handlers in core socket flows
- `api/src/modules/notifications/routes.ts` still returns `501` for notification surfaces
- later dashboard and QA tracks need live event plumbing instead of placeholder infrastructure

## In Scope

- implement real notification list/read/preferences routes backed by existing models/user preferences
- replace critical worker stubs with structured, idempotent handlers and shared queue/job utilities
- harden realtime auth, room synchronization, and Redis event fan-out for live product events
- add targeted health/validation coverage for realtime and worker services

## Out Of Scope

- manual APNs key creation or Apple developer portal work
- marketing copy or campaign logic for notifications
- public web redesign
- unrelated store or BLE product expansion outside the event/queue paths

## Acceptance Criteria

1. Notification API routes no longer return `501` for list/read/preferences behavior.
2. Critical worker processors for alerts, push notifications, subscription validation, referral reward, store order handling, and data export have real non-placeholder logic paths plus failure logging.
3. Realtime service no longer relies on core TODO paths for auth/session, room sync, and Redis event fan-out on the live channels.
4. Worker, realtime, and touched API surfaces build successfully and any targeted tests or regression checks pass.
5. Later tracks can depend on this as the durable event-delivery layer.

## Dependencies

- `gps_route_capture_20260411`

## Notes

This track folds background-job automation and notification contracts into the hardening pass so later product slices can consume one stable event backbone instead of multiple partial fixes.
