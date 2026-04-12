# Integration Gap Closure

## Track ID

`integration_gap_closure_20260411`

## Summary

Convert the post-QA audit findings into shipped product behavior by closing the remaining client/backend contract gaps, replacing mocked user-facing flows with real implementations, and hardening the BLE disconnect path so the integrated surfaces behave consistently.

## Why This Track Exists

- the production QA sweep incorrectly concluded that only external portal/configuration blockers remained
- a full cross-system audit surfaced internal build scope still missing in alerts, referrals, payments, account deletion, support, and BLE disconnect handling
- those gaps are already visible in shipped clients, so they must be treated as integration work, not deferred cleanup

## In Scope

- implement backend alert routes that match the iOS alert contract
- implement referral endpoints that match the iOS referral screen contract
- replace mocked account-deletion behavior with a real deletion-request flow across API, web, and iOS
- align store payment contracts across web, API, and iOS Apple Pay
- replace mocked store catalog/support flows with live API-backed behavior
- harden BLE disconnect handling so alerts and user feedback fire through the intended path
- record the new internal-vs-external blocker boundary once the work lands

## Out Of Scope

- Apple, Google, APNs, Stripe live credentials, merchant certificates, or other external portal work
- net-new product features unrelated to the audited contract gaps
- native iOS card-entry checkout via a new Stripe iOS SDK integration unless required to satisfy existing acceptance criteria

## Acceptance Criteria

1. iOS alert and referral screens consume live API routes without `501` stubs or route mismatches.
2. Account deletion and support submission no longer fake success in the browser.
3. Web store products load from the backend, and checkout request shapes match backend validation.
4. iOS Apple Pay creates and confirms payment intents using a valid backend contract.
5. BLE disconnect handling no longer leaves the backend alert/haptic helpers orphaned behind the timeout flow.
6. Remaining blockers after execution are external/manual only and are documented as such.

## Dependencies

- `production_qa_sweep_20260411`
- `backend_core_services_20260411`
- `device_priority_alarm_20260411`
- `web_auth_dashboard_20260411`
- `ios_completion_20260411`

## Notes

This track exists because the production QA closure artifact was too optimistic. It supersedes the assumption that the only follow-up remaining was provider configuration.

## Implementation Update — 2026-04-11

The integration slice is now built and verified.

- Alerts now ship live `/alerts`, `/alerts/device-disconnected`, and `/alerts/:id/acknowledge` handlers instead of `501` stubs, and worker fanout treats `device_disconnected` as a first-class disconnect alert.
- Referrals now ship live `/referrals/me` and `/referrals/qr` contracts with persisted referral codes and QR payloads that match the iOS client.
- Account deletion and support submission now persist through real backend flows instead of browser-only success mocks.
- The web store now loads live catalog data, cart totals are backend-derived, Stripe card checkout finalizes server-side orders, and iOS Apple Pay creates and confirms real payment intents against the same cart-backed contract.
- BLE reconnect timeout now invokes the real disconnect haptic plus alert helpers, and service UUID filtering is configurable through app config instead of an inline placeholder.

## Verification Evidence

- `npm test --workspace=api` — PASS (`5` suites / `25` tests)
- `npm run type-check` — PASS
- `npm run test` — PASS
- `npm run launch:check` — PASS (`21/21`)
- `xcodebuild -project client-ios/GearSnitch.xcodeproj -target GearSnitch -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build` — PASS
