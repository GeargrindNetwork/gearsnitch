# Ralph Build-Loop Backlog

Items the autonomous build loop ("Ralph") works through. Status values:
`pending`, `pr-open`, `merged`, `blocked`.

## Shipped

| # | Title | Status | PR |
|---|---|---|---|
| 1 | Universal Links — `/r/:code` landing + AASA + iOS handler | merged | [#44](https://github.com/GeargrindNetwork/gearsnitch/pull/44) |
| 2 | Post-install referral attribution | merged | [#46](https://github.com/GeargrindNetwork/gearsnitch/pull/46) |
| 3 | Stripe Customer Portal deep-link into iOS | merged | [#47](https://github.com/GeargrindNetwork/gearsnitch/pull/47) |
| — | APNs push sender (item #19 prep) | merged | [#48](https://github.com/GeargrindNetwork/gearsnitch/pull/48) |
| 5 | Weekly reconciliation cron for subscription state drift | merged | [#50](https://github.com/GeargrindNetwork/gearsnitch/pull/50) |
| 35 | Dark-mode consistency pass | merged | [#53](https://github.com/GeargrindNetwork/gearsnitch/pull/53) |

## Queued — ranked by impact × (1/complexity)

| # | Title | Impact | Complexity | Tier | Layers | Status | Notes |
|---|---|---|---|---|---|---|---|
| 4 | Gear retirement + component mileage alerts (shoe/chain/tire) | 9 | S | 2 | ios,api,worker | pr-open | Strava GAP per DC Rainmaker; push at user-set threshold. Core gear-tracking moat. PR pending. |
| 5 | Weekly reconciliation cron for subscription state drift | 8 | M | 2 | api,worker | merged | Landed as #50. |
| 6 | AccessorySetupKit for one-tap BLE gear pairing | 8 | S | 2 | ios | pending | iOS 26.3 DMA expansion. Replaces CoreBluetooth permission prompt with AirPods-style sheet. |
| 7 | HealthKit Medications API sync for peptide/dosing log | 8 | S | 2 | ios | pending | WWDC25. Bi-directional med log sync; differentiator vs Whoop/Strava. |
| 8 | External HR sensor intake on iPhone (BLE HR profile + Powerbeats Pro 2) | 8 | S | 2 | ios | pending | iOS 26 HKLiveWorkoutDataSource. Expands Watch-less cohort. |
| 9 | Strava-style auto-gear assignment by activity type | 8 | S | 2 | ios,api | pending | Default gear per workout + manual override. Table-stakes. |
| 10 | iPhone-native workout session + crash recovery | 8 | M | 2 | ios | pending | WWDC25 HKWorkoutSession on iPhone. Retention win for non-Watch owners. |
| 11 | App Intents for Lock Screen workout control | 7 | S | 2 | ios | pending | INStartWorkoutIntent family. Compounds with #10. |
| 12 | Racquet-sport activity types (Padel, Pickleball) | 7 | XS | 3 | ios | pending | Strava shipped Padel/Basketball/Volleyball/Cricket/Dance 2025. |
| 13 | Apple Pay capability in XcodeGen project.yml | 7 | XS | 2 | infra | pr-open | Prevents silent Apple Pay regression on pbxproj regen. PR [#71](https://github.com/GeargrindNetwork/gearsnitch/pull/71). |
| 14 | tsconfig `ignoreDeprecations:5.0` vs TS 6 mismatch | 6 | XS | 2 | infra | pending | `npm run build` currently fails. Bump to `"6.0"`. |
| 15 | Widget extension target — compile + ship | 6 | M | 2 | ios | pending | Widgets exist in source; target not regenerated via XcodeGen. |
| 16 | Rest timer between sets | 6 | S | 2 | ios | pending | 30s/60s/90s/custom. Background audio cue. |
| 17 | BLE battery level (0x180F) | 6 | S | 2 | ios | pending | Read + surface on DeviceDetailView. Low-battery push at <20%. Route through AccessorySetupKit (see #6). |
| 18 | Auto-pause run on >60s inactivity | 6 | S | 2 | ios | pending | RunTrackingManager low-motion detection. |
| 19 | Signal history chart (RSSI trends per device, 24h) | 5 | M | 2 | ios,api | pending | Store RSSI samples, render line chart. |
| 20 | Dashboard trend charts (week/month/year) | 5 | M | 2 | web | pending | Pick Recharts or visx. |
| 21 | Run pace coach — Watch haptic + headphone cadence tone | 7 | M | 2 | ios | pending | Watch haptic at drift >5%; metronome over music. |
| 22 | Billing history page | 5 | S | 2 | web | pending | Lists Stripe invoices via `GET /subscriptions/invoices`. |
| 23 | Notifications history page | 5 | S | 2 | web | pending | Surfaces APNs/push-log per user. |
| 24 | Web test framework (Vitest + RTL) | 5 | M | 2 | web | pending | Tier 1 surfaces first. |
| 25 | Referral dashboard polish (referrer-side) | 4 | S | 2 | ios | pending | Earlier proposal from item #2 agent. |
| 26 | App Store review prompting | 5 | S | 2 | ios | pending | SKStoreReviewController on 3rd workout / 5th device pair. |
| 27 | Workout summary push after session end | 5 | M | 2 | api,worker,ios | pending | Uses new APNs sender. |
| 28 | Stripe Checkout for web subscriptions | 5 | M | 2 | web,api | pending | External-web-only path; no iOS-initiated links (App Store 3.1.1). |
| 29 | iOS CI workflow (macos-14 + xcodebuild test) | 4 | M | 2 | infra | pending | |
| 30 | Cloud Run auto-rollback on deploy 5xx | 4 | M | 2 | infra | pending | Per guard rail #3. |
| 31 | graphify-out/ housekeeping (gitignore) | 3 | XS | 2 | infra | pending | Currently modified every commit. |
| 32 | Admin dashboard API (currently 501) | 4 | L | 2 | api,web | pending | Gated on `user.roles.includes('admin')`. |
| 33 | Content module / CMS (currently 501) | 3 | M | 2 | api,web | pending | Blog posts / marketing. |
| 34 | Feature flag system (Redis-backed) | 5 | M | 2 | api | pending | Per-user / per-tier overrides. |
| 35 | Dark-mode consistency pass | 3 | S | 2 | web | merged | Landed as #53. |
| 36 | Landing page A/B framework | 4 | M | 2 | web | pending | Two variants, cookie-based bucketing. |
| 37 | GPS run polylines + route map | 5 | L | 2 | ios,api | pending | CoreLocation + MapKit. |
| 38 | Apple Watch companion workout sync | 5 | L | 2 | ios | pending | **Affected by #10** — model must handle iPhone-originated workouts with Watch as optional sensor. |
| 39 | Achievement badges (streaks, milestones) | 5 | M | 2 | ios,api | pending | 7d/30d streaks, 100 sessions, first run, first purchase. |

## Blocked

| # | Title | Blocker |
|---|---|---|
| — | APNs cert / sandbox key | ~~External~~ — Shipped in PR #48. Secrets live in GCP Secret Manager; Cloud Run mounted. Unblocked. |

## Needs user signoff

Items escalated here require explicit user approval before spawning a coding agent. Research-tick candidates with `tier==1` OR `complexity>=L` land here. Brand/UX pillar decisions land here.

| # | Title | Reason | Source / Notes |
|---|---|---|---|
| S1 | Identity collapse — brand consolidation | Requires pillar decision | GearSnitch / GearGrind.Net / GearGrind Network / Shawn Frazier Inc all coexist. |
| S2 | 3-tab nav rebuild (Gear / Train / Chemistry + avatar) | Requires pillar decision | Matches ultrathink redesign. Significant iOS refactor. |
| S3 | Onboarding "first win" restructure | Requires pillar decision | Defer permission gauntlet; let user pair a device / log a gym / browse store first. |
| S4 | Retire / demote unused features (Mesh Chat, Stopwatch, BMI calc) | Requires product decision | Per ultrathink redesign. |
| S5 | KMS envelope encryption on PHI — scope expansion (BAA inventory + audit-log retention) | Tier 1 (encryption keys + PHI) | 2026 HIPAA guidance: AES-256 at rest + TLS 1.3 + audit logs + BAAs. |
| S6 | Lab PDF upload + biomarker extraction (WHOOP Advanced Labs parity) | Biomarker storage may qualify as PHI | WHOOP 2025 launch; our lab-draw scheduler is stubbed, this unblocks without Rupa/LabCorp. High impact (9) but needs storage-design signoff. |

## Tick protocol

Each tick:

1. Read this file.
2. Pick the lowest-numbered `pending` item in **Queued** that is NOT Tier 1 and NOT in **Needs user signoff**.
3. Check open PR count — if > 4 open PRs, sleep-tick.
4. Check CI of latest main — if red, sleep-tick.
5. If queued `pending` < 5 items → research tick instead (read-only, refills queue).
6. Spawn agent in isolated worktree with the item's scope as the prompt.
7. Mark item `in-progress` → update this file.
8. When agent returns, mark `pr-open` with PR URL.
9. iMessage milestone on PR open.
10. Next tick, repeat.

Stop conditions:

- User says `/stop` or `pause ralph`.
- Budget exhausted.
- 3 consecutive PRs with red CI.
- Every queued item `merged` or `blocked` or in `Needs user signoff`.

## Research-tick cadence

- Every 4th build tick OR `pending < 5`, whichever comes first.
- Read-only agent. Caps: 3 WebSearch + 10 WebFetch per tick. No code.
- Admits if tier != 1, impact >= 7, complexity in [XS, S, M], no payment/auth/encryption layer.
- Everything else → Needs user signoff.
