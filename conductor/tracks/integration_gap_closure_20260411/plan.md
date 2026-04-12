# Integration Gap Closure — Execution Plan

## Context

- **Track**: `integration_gap_closure_20260411`
- **Spec**: close the remaining internal contract gaps surfaced by the cross-system audit
- **Dependencies**: `production_qa_sweep_20260411`, `backend_core_services_20260411`, `device_priority_alarm_20260411`, `web_auth_dashboard_20260411`, `ios_completion_20260411`
- **Execution Mode**: SEQUENTIAL

## Dependency Graph

```yaml
dag:
  nodes:
    - id: "1.1"
      name: "Replace stubbed alert and referral backend routes with contracts that match current clients"
      depends_on: []
    - id: "1.2"
      name: "Replace mocked account deletion and support submission flows with real API-backed behavior"
      depends_on: ["1.1"]
    - id: "2.1"
      name: "Align store catalog and payment contracts across web, API, and iOS Apple Pay"
      depends_on: ["1.2"]
    - id: "2.2"
      name: "Harden BLE disconnect handling so the timeout path produces real alerts and user feedback"
      depends_on: ["2.1"]
    - id: "3.1"
      name: "Run focused validation and update the blocker record to reflect the true post-integration state"
      depends_on: ["2.2"]
```

## Phase 1: Core Contract Closure

- [x] Task 1.1: Replace stubbed alert and referral backend routes with contracts that match current clients
  - **Acceptance**: `/alerts` and `/referrals` support the routes and payloads already consumed by the iOS app, and the related `501` stubs are removed
  - **Files**: `api/src/modules/alerts/*`, `api/src/modules/referrals/*`, related models/tests, client DTOs only if required for minor alignment
  - **Delivered**: live alert list, disconnect, and acknowledge handlers; live referral `/me` and `/qr` handlers; referral code persistence; worker disconnect fanout alignment

- [x] Task 1.2: Replace mocked account deletion and support submission flows with real API-backed behavior
  - **Acceptance**: account deletion no longer fakes success in web or iOS, and support submission persists through a concrete backend path
  - **Files**: `api/src/modules/users/*`, `api/src/modules/support/*`, `web/src/pages/DeleteAccountPage.tsx`, `web/src/pages/SupportPage.tsx`, related models/tests
  - **Delivered**: persisted deletion-request flow with session revocation and reactivation guardrails; support ticket model and routes; web delete-account and support screens now call the API

## Phase 2: Commerce And Device Hardening

- [x] Task 2.1: Align store catalog and payment contracts across web, API, and iOS Apple Pay
  - **Acceptance**: the web store loads products from the backend, checkout payloads satisfy backend validation, and iOS Apple Pay confirms with a valid payment intent
  - **Files**: `api/src/modules/store/*`, `api/src/services/PaymentService.ts`, `api/src/services/OrderService.ts`, `web/src/pages/StorePage.tsx`, `web/src/components/checkout/StripeCheckout.tsx`, `client-ios/GearSnitch/Core/Payments/*`, store view models as needed
  - **Delivered**: cart-backed totals and pending-order snapshots; `/store/payments/finalize`; live catalog/cart usage on web; real Apple Pay intent creation and confirmation on iOS

- [x] Task 2.2: Harden BLE disconnect handling so the timeout path produces real alerts and user feedback
  - **Acceptance**: the reconnect-timeout path invokes the existing backend alert/haptic helpers, and BLE service filtering is configurable rather than inline-placeholder-only
  - **Files**: `client-ios/GearSnitch/Core/BLE/BLEManager.swift`, related app config/plist documentation, targeted regression tests if applicable
  - **Delivered**: reconnect timeout now calls `triggerDisconnectHaptic()` and `postDisconnectAlert(for:)`; service UUIDs now load from `AppConfig.bleServiceUUIDs`

## Phase 3: Verification And Closure

- [x] Task 3.1: Run focused validation and update the blocker record to reflect the true post-integration state
  - **Acceptance**: regression checks cover the new contracts, root type-check and test pass, and the blocker docs distinguish internal fixes from external portal work
  - **Files**: `api/tests/*`, conductor artifacts as needed
  - **Delivered**: `api/tests/integration-gap-closure.test.cjs`, refreshed handoff and QA docs, and a completed loop state backed by passing API, repo, launch-preflight, and iOS validation

## Discovered Work

- The audit also surfaced dormant `501` modules under `health-data`, `calories`, `content`, `admin`, and `config`. They are not currently on active client paths, so they stay outside this execution slice unless a core fix depends on them.

## Validation Evidence

- `npm test --workspace=api` — PASS
- `npm run type-check` — PASS
- `npm run test` — PASS
- `npm run launch:check` — PASS
- `xcodebuild -project client-ios/GearSnitch.xcodeproj -target GearSnitch -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build` — PASS
