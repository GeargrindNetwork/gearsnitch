# Production QA Sweep Report

> Update (2026-04-11): this report was originally written before the follow-on `integration_gap_closure_20260411` track surfaced missing internal alert, referral, delete-account, support, store, and BLE disconnect wiring. Those gaps are now closed and revalidated, so the remaining blockers listed here are once again accurate as external or manual only.

## Automated Sweep

- `npm run build` — PASS
- `npm run lint` — PASS
- `npm run type-check` — PASS
- `npm run test` — PASS (`@gearsnitch/api` ran 5 suites / 25 tests)
- `xcodebuild -project client-ios/GearSnitch.xcodeproj -target GearSnitch -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build` — PASS

## Cross-Surface Checklist

| Surface | Status | Evidence | Remaining blocker |
|---------|--------|----------|-------------------|
| Sign-in | PARTIAL | Web auth/dashboard slice builds cleanly and the OAuth routes are wired on both web and API. | Interactive Google and Apple OAuth still requires environment-specific client IDs, redirect configuration, and portal verification. |
| Devices | PASS | Device priority/favorite regression sweep passed; root lint/build/type-check/test passed; iOS simulator build passed. | None in code. |
| Workouts | PASS | Workout metrics endpoint participates in the repo-wide build/lint/type-check/test sweep. | None in code. |
| Runs | PASS | Run capture pages and richer metrics dashboard build cleanly; recent run gallery and `/runs` drill-down are live in the browser. | Physical-device GPS capture remains a manual product QA step, not a code blocker. |
| Notifications | PARTIAL | Notification API, worker processors, and realtime event paths are covered by the hardening regression sweep and pass the repo-wide checks. | End-to-end push delivery still depends on APNs key provisioning and Apple portal setup. |
| Metrics | PASS | Richer dashboard regression sweep passed and `/metrics` is included in the successful web build. | None in code. |
| Store / Payments | PARTIAL | Store page now uses the live catalog and cart contract, Stripe checkout finalizes real backend orders, and iOS Apple Pay creates plus confirms real payment intents; the repo-wide sweep, API regression sweep, and iOS simulator build all passed. | Live payment verification, Stripe webhook credential validation, and Apple Pay merchant certificate setup remain external/manual. |

## Remaining External / Manual Blockers

1. Configure Google OAuth browser and iOS client IDs and confirm redirect URI setup.
2. Complete Apple Sign-In portal configuration for the service/app identifiers used by web and iOS.
3. Provision APNs credentials so push notification delivery can be verified outside the simulator.
4. Validate Stripe live credentials, webhook delivery, and Apple Pay merchant certificate setup in the target environment.

## Notes

- The repo-level validation debt that previously blocked hard lint gates is cleared: web lint no longer fails on the shared UI exports or `StorePage`, and `worker` plus `realtime` now have local flat ESLint configs.
- The integration follow-up track added a targeted regression sweep for alerts, referrals, account deletion, support, cart-backed checkout, Apple Pay, and BLE disconnect handling, and all of those checks passed.
- The remaining blockers are environment or portal tasks, not missing product code inside this repository.
- The repo-side launch wiring preflight now exists as `npm run launch:check` and currently passes.
- Use [launch-checklist.md](/Users/shawn/Documents/GearSnitch/conductor/tracks/production_qa_sweep_20260411/launch-checklist.md) for the implementation checklist and [launch-board.md](/Users/shawn/Documents/GearSnitch/conductor/tracks/production_qa_sweep_20260411/launch-board.md) as the owner/status tracker.
