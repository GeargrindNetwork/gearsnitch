# Backend Core Services — Execution Plan

## Context

- **Track**: `backend_core_services_20260411`
- **Spec**: Replace the remaining stubbed backend layers that block real account, device, gym, and store persistence.
- **Dependencies**: none
- **Overlap Check**: checked `auth`, `sessions`, `calendar`, `store/paymentRoutes`, and the already-live parts of `users/routes.ts`
- **Execution Mode**: `PARALLEL`

## Scope Decisions

### In Scope For This Track

- harden the existing account surfaces around `/users/me`, `/users/me/profile`, and `/users/me/export`
- implement user-scoped device persistence for list, create, detail, delete, status update, and map locations
- implement user-scoped gym persistence for list, create, detail, update, delete, and default selection
- implement store catalog, cart persistence, and order history surfaces used by current iOS/web clients
- preserve the existing API response envelope and auth middleware behavior

### Overlap / Do Not Rebuild Here

- `api/src/modules/auth/routes.ts`
- `api/src/modules/sessions/routes.ts`
- `api/src/modules/calendar/routes.ts`
- `api/src/modules/store/paymentRoutes.ts`
- already-live account read/update handlers in `api/src/modules/users/routes.ts`

### Explicit Deferrals

- `/store/checkout`
  - current iOS card checkout call is still a placeholder, while real payment work already lives under `/store/payments/*`
- `/devices/:id/share`
  - current `Device` model has no sharing persistence or acceptance rules
- `/gyms/evaluate`, `/gyms/events`, `/gyms/nearby`, `/:id/check-in`
  - requires broader geofence/event semantics than this CRUD-focused track
- `DELETE /users/me` and `GET /users/:id`
  - not needed to unblock the dependent web/iOS tracks
- alerts, notifications, referrals, health, calories, workouts, config, content, support, admin, subscription CRUD

## Dependency Graph

```yaml
dag:
  nodes:
    - id: '1.1'
      name: 'Create store service and response serializers'
      type: 'code'
      files:
        - 'api/src/modules/store/storeService.ts'
        - 'api/src/modules/store/routes.ts'
      depends_on: []
      estimated_duration: '60m'
      phase: 1
    - id: '1.2'
      name: 'Create device service and serializers'
      type: 'code'
      files:
        - 'api/src/modules/devices/deviceService.ts'
        - 'api/src/modules/devices/routes.ts'
      depends_on: []
      estimated_duration: '60m'
      phase: 1
    - id: '1.3'
      name: 'Create gym service and serializers'
      type: 'code'
      files:
        - 'api/src/modules/gyms/gymService.ts'
        - 'api/src/modules/gyms/routes.ts'
      depends_on: []
      estimated_duration: '60m'
      phase: 1
    - id: '2.1'
      name: 'Wire store product, cart, and order routes'
      type: 'integration'
      files:
        - 'api/src/modules/store/routes.ts'
      depends_on:
        - '1.1'
      estimated_duration: '45m'
      phase: 2
    - id: '2.2'
      name: 'Wire device CRUD, status, and locations routes'
      type: 'integration'
      files:
        - 'api/src/modules/devices/routes.ts'
      depends_on:
        - '1.2'
      estimated_duration: '45m'
      phase: 2
    - id: '2.3'
      name: 'Wire gym CRUD and default-selection routes'
      type: 'integration'
      files:
        - 'api/src/modules/gyms/routes.ts'
      depends_on:
        - '1.3'
      estimated_duration: '45m'
      phase: 2
    - id: '3.1'
      name: 'Harden users/me aggregations against live device and order state'
      type: 'code'
      files:
        - 'api/src/modules/users/routes.ts'
      depends_on:
        - '2.1'
        - '2.2'
      estimated_duration: '30m'
      phase: 3
    - id: '3.2'
      name: 'Add focused API validation and 501 regression checks for selected routes'
      type: 'test'
      files:
        - 'api/src/modules/store/routes.ts'
        - 'api/src/modules/devices/routes.ts'
        - 'api/src/modules/gyms/routes.ts'
        - 'api/src/modules/users/routes.ts'
      depends_on:
        - '2.1'
        - '2.2'
        - '2.3'
        - '3.1'
      estimated_duration: '45m'
      phase: 3

  parallel_groups:
    - id: 'pg-1'
      tasks:
        - '1.1'
        - '1.2'
        - '1.3'
      conflict_free: true
    - id: 'pg-2'
      tasks:
        - '2.1'
        - '2.2'
        - '2.3'
      conflict_free: true
```

## Phase 1: Service Slices

### Tasks

- [x] Task 1.1: Create store service and response serializers <!-- deps: none, parallel: pg-1 -->
  - **Type**: `code`
  - **Acceptance**: service can list active products, fetch a product by id/slug-safe key, return user order history, and upsert cart items with recalculated subtotal
  - **Files**: `api/src/modules/store/storeService.ts`, `api/src/modules/store/routes.ts`
- [x] Task 1.2: Create device service and serializers <!-- deps: none, parallel: pg-1 -->
  - **Type**: `code`
  - **Acceptance**: service can list/register/load/delete devices for the authenticated user, update device status, and project map-friendly location payloads from persisted device state
  - **Files**: `api/src/modules/devices/deviceService.ts`, `api/src/modules/devices/routes.ts`
- [x] Task 1.3: Create gym service and serializers <!-- deps: none, parallel: pg-1 -->
  - **Type**: `code`
  - **Acceptance**: service can list/create/load/update/delete gyms for the authenticated user and enforce a single default gym
  - **Files**: `api/src/modules/gyms/gymService.ts`, `api/src/modules/gyms/routes.ts`

## Phase 2: Route Wiring

### Tasks

- [x] Task 2.1: Wire store product, cart, and order routes <!-- deps: 1.1, parallel: pg-2 -->
  - **Type**: `integration`
  - **Acceptance**: `GET /store/products`, `GET /store/products/:id`, `GET /store/cart`, `POST /store/cart`, `PATCH /store/cart/:productId`, `DELETE /store/cart/:productId`, and `GET /store/orders` return live data instead of `501`
  - **Files**: `api/src/modules/store/routes.ts`
- [x] Task 2.2: Wire device CRUD, status, and locations routes <!-- deps: 1.2, parallel: pg-2 -->
  - **Type**: `integration`
  - **Acceptance**: `GET /devices`, `POST /devices`, `GET /devices/:id`, `DELETE /devices/:id`, `PATCH /devices/:id/status`, and `GET /devices/locations` return live user-scoped data instead of placeholders
  - **Files**: `api/src/modules/devices/routes.ts`
- [x] Task 2.3: Wire gym CRUD and default-selection routes <!-- deps: 1.3, parallel: pg-2 -->
  - **Type**: `integration`
  - **Acceptance**: `GET /gyms`, `POST /gyms`, `GET /gyms/:id`, `PATCH /gyms/:id`, `DELETE /gyms/:id`, and `PATCH /gyms/:id/default` return live user-scoped data instead of placeholders
  - **Files**: `api/src/modules/gyms/routes.ts`

## Phase 3: Account Aggregation And Validation

### Tasks

- [x] Task 3.1: Harden users/me aggregations against live backend state <!-- deps: 2.1, 2.2 -->
  - **Type**: `code`
  - **Acceptance**: `/users/me` and `/users/me/export` continue to resolve cleanly with real device and order data and no mock-only assumptions
  - **Files**: `api/src/modules/users/routes.ts`
- [x] Task 3.2: Add focused API validation and 501 regression checks <!-- deps: 2.1, 2.2, 2.3, 3.1 -->
  - **Type**: `test`
  - **Acceptance**: targeted API validation passes and a route sweep confirms the selected endpoints no longer emit placeholder `501` responses
  - **Files**: `api/src/modules/store/routes.ts`, `api/src/modules/devices/routes.ts`, `api/src/modules/gyms/routes.ts`, `api/src/modules/users/routes.ts`

## Validation Commands

- `npm run build --workspace=api`
- `npm run lint --workspace=api`
- `npm run type-check --workspace=api`
- `npm run test --workspace=api`

## Plan Evaluation

- **Date**: `2026-04-12`
- **Evaluator**: `loop-plan-evaluator`
- **Verdict**: `PASS`
- **Summary**:
  - scope aligns with the track spec and `docs/HANDOFF.md`
  - overlap is explicitly excluded for auth, sessions, calendar, and store payment intent work
  - dependency ordering is valid and the DAG has no unresolved conflicts
  - board review was skipped because the plan does not introduce a new product or architecture decision beyond the existing decision log

## Discovered Work

- if execution proves `/store/checkout` is still needed for a non-Apple-pay browser flow, spin that into the downstream web auth/dashboard track or a new store-payments follow-up track instead of expanding this one mid-flight

## Execution Result

- **Date**: `2026-04-12`
- **Executor**: `loop-executor`
- **Result**: `PASS`
- **Notes**:
  - added live `StoreService`, `DeviceService`, and `GymService` slices and replaced the selected route placeholders with user-scoped handlers
  - kept `/store/checkout`, `/devices/:id/share`, `/gyms/evaluate`, `/gyms/events`, `/gyms/nearby`, and `/gyms/:id/check-in` as explicit deferred flows
  - confirmed `/users/me` and `/users/me/export` already aggregate from live `StoreOrder` and `Device` collections, so no additional code change was required there
  - added `api/eslint.config.js`, `api/jest.config.cjs`, and `api/tests/backend-core-services.test.cjs` so the workspace-level lint/test commands now provide durable regression coverage

## Validation Evidence

- `npm run build --workspace=api`
- `npm run type-check --workspace=api`
- `npm run lint --workspace=api`
- `npm run test --workspace=api`
