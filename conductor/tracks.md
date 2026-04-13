# GearSnitch Track Registry

This file tracks the active delivery sequence for finishing the application.

## Active Tracks

| Track ID | Type | Status | Progress |
|----------|------|--------|----------|
| `cycle_tracking_peptide_steroid_20260413` | `feature` | `planned` | `PRD, spec, and execution plan created from 3-lane reverse engineering; implementation not started` |

## Completed Tracks

| Track ID | Completed On | Result |
|----------|--------------|--------|
| `integration_gap_closure_20260411` | `2026-04-12` | The post-QA internal contract gaps are now closed: alerts and referrals use live backend routes, delete-account and support flows persist through the API, web checkout plus iOS Apple Pay use a shared cart-backed payment contract, BLE disconnect timeout invokes the real alert and haptic helpers, and API regression tests plus root type-check/test, launch preflight, and the iOS simulator build all passed. Remaining follow-up is limited to external Google OAuth, Apple Sign-In, APNs, and live Stripe or Apple Pay setup. |
| `production_qa_sweep_20260411` | `2026-04-12` | Repo-wide `build`, `lint`, `type-check`, and `test` now pass, the iOS simulator build passed, and the final cross-surface QA state plus remaining external blockers are recorded in `conductor/tracks/production_qa_sweep_20260411/qa-report.md`. Remaining follow-up is limited to external Google OAuth, Apple Sign-In, APNs, and live Stripe or Apple Pay setup. |
| `richer_web_dashboard_analytics_20260411` | `2026-04-12` | The browser `/metrics` surface now consumes a richer backend analytics contract with run distance trends, recent run gallery data, and device status summaries. The web dashboard ships run and device cards plus `/runs` drill-downs, and API test/lint/type-check/build plus the web build all passed. Web lint still only reports the pre-existing shared UI `react-refresh` issues and `StorePage` warnings outside this slice. |
| `device_priority_alarm_20260411` | `2026-04-12` | Device favorites and nicknames now persist through the API and iOS clients, favorites sort first across BLE-backed surfaces, reconnect timeout handling now asks whether the session ended or the gear is lost before escalating, and targeted API lint/test/type-check plus the iOS simulator build all passed. |
| `realtime_worker_hardening_20260411` | `2026-04-12` | Live notification list/read/preferences/register routes shipped, worker queue processors now have concrete idempotent runtime logic, realtime socket auth and Redis fan-out were aligned with the API session contract, and targeted API test/lint/type-check/build plus worker/realtime type-check/build all passed. Worker and realtime lint remain blocked by a pre-existing ESLint 9 flat-config gap in those workspaces. |
| `gps_route_capture_20260411` | `2026-04-12` | Backend run persistence and route endpoints shipped, iOS GPS capture/history/detail surfaces were wired into the app target, and the protected web `/runs` replay surface is live. Fresh API lint/test/type-check/build, web build, targeted web lint, and iOS simulator build all passed; repo-wide web lint still has pre-existing shared UI and `StorePage` debt outside this slice. |
| `run_tracking_metrics_20260411` | `2026-04-12` | Live workout CRUD and metrics aggregation shipped in the API, iOS workout history and save flows now use real backend contracts, the Workouts tab is live, and the protected web `/metrics` surface is available. Fresh API test/lint/type-check/build, web build, and iOS simulator build all passed; web lint still has pre-existing shared UI debt outside this slice. |
| `backend_core_services_20260411` | `2026-04-12` | Live store, device, and gym backend contracts shipped; `/users/me` aggregation verified against live models; API build/type-check/lint/test all passed; checkout, device sharing, and geofence/event flows remain deferred by design. |
| `ios_completion_20260411` | `2026-04-12` | Live auth session-management shipped for the iOS account screen, gym-session and calendar clients now match backend contracts, manual checkout now fails closed with explicit UX instead of hitting the `501` endpoint, and both API + iOS simulator builds passed. |
| `web_auth_dashboard_20260411` | `2026-04-12` | Browser sign-in, refresh-cookie auth bootstrap, account route protection, and live account/calendar data wiring shipped for the web app; the web build passed, while shared UI lint debt and interactive OAuth verification remain follow-up items. |

## Deferred Tracks

_None._

## Completion Rule

When a track finishes:

1. mark its `metadata.json` as complete
2. move it to a completed section with the date and result summary
3. update any dependency references for downstream tracks
