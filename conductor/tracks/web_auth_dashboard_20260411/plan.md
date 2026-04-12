# Web Auth And Dashboard — Execution Plan

## Context

- **Track**: `web_auth_dashboard_20260411`
- **Spec**: Turn the web app into a real signed-in account surface backed by the API.
- **Dependencies**: `backend_core_services_20260411`
- **Overlap Check**: checked `web/src/App.tsx`, `web/src/pages/AccountPage.tsx`, `web/src/lib/api.ts`, `api/src/modules/auth/routes.ts`, `api/src/modules/users/routes.ts`, and `api/src/modules/calendar/routes.ts`
- **Execution Mode**: `PARALLEL`

## Scope Decisions

### In Scope For This Track

- add a dedicated browser sign-in route instead of leaving `/account` as a dead signed-out placeholder
- introduce a reusable web auth/bootstrap layer that uses the refresh cookie path rather than ad hoc token hydration inside `AccountPage`
- wire Google and Apple browser sign-in against the shared backend `/auth/oauth/*` endpoints using env-configured client IDs
- gate `/account` behind that auth state and make sign-out clear browser session state cleanly
- normalize account/dashboard queries against the current backend response shapes, especially the calendar month payload

### Overlap / Do Not Rebuild Here

- iOS auth, session-management, and payment work already belong to the native app tracks
- backend auth/session/calendar routes now exist and should be consumed, not redesigned here
- large landing-page or store redesign work stays out of scope
- admin/analytics surfaces beyond the account/dashboard page are not part of this track

### Explicit Deferrals

- production OAuth secret provisioning and cloud console setup beyond adding the required web env/config placeholders
- any shared API reshaping that would be safer to defer than to change mid-web-auth implementation
- deeper dashboard expansion beyond profile, purchases, and calendar/account bootstrap

## Dependency Graph

```yaml
dag:
  nodes:
    - id: '1.1'
      name: 'Introduce reusable web auth/session bootstrap primitives'
      type: 'infrastructure'
      files:
        - 'web/src/lib/api.ts'
        - 'web/src/**/*auth*'
      depends_on: []
      estimated_duration: '45m'
      phase: 1
    - id: '1.2'
      name: 'Add dedicated browser sign-in route and provider flows'
      type: 'feature'
      files:
        - 'web/src/App.tsx'
        - 'web/src/pages/SignInPage.tsx'
        - 'web/.env.example'
      depends_on:
        - '1.1'
      estimated_duration: '60m'
      phase: 1
    - id: '1.3'
      name: 'Normalize account page data hooks to current backend response shapes'
      type: 'code'
      files:
        - 'web/src/pages/AccountPage.tsx'
        - 'web/src/components/account/HeatmapCalendar.tsx'
      depends_on: []
      estimated_duration: '45m'
      phase: 1
    - id: '2.1'
      name: 'Gate the account surface behind auth bootstrap and signed-out redirect'
      type: 'feature'
      files:
        - 'web/src/App.tsx'
        - 'web/src/pages/AccountPage.tsx'
      depends_on:
        - '1.1'
        - '1.2'
      estimated_duration: '30m'
      phase: 2
    - id: '2.2'
      name: 'Harden refresh-cookie bootstrap and sign-out cleanup'
      type: 'integration'
      files:
        - 'web/src/lib/api.ts'
        - 'web/src/**/*auth*'
        - 'web/src/pages/AccountPage.tsx'
      depends_on:
        - '1.1'
        - '1.2'
      estimated_duration: '30m'
      phase: 2
    - id: '3.1'
      name: 'Run focused web workspace build verification'
      type: 'test'
      files:
        - 'web/package.json'
        - 'web/src/App.tsx'
        - 'web/src/pages/AccountPage.tsx'
        - 'web/src/pages/SignInPage.tsx'
        - 'web/src/lib/api.ts'
      depends_on:
        - '1.3'
        - '2.1'
        - '2.2'
      estimated_duration: '20m'
      phase: 3

  parallel_groups:
    - id: 'pg-1'
      tasks:
        - '1.1'
        - '1.3'
      conflict_free: true
    - id: 'pg-2'
      tasks:
        - '2.1'
        - '2.2'
      conflict_free: false
```

## Phase 1: Auth And Data Foundations

### Tasks

- [x] Task 1.1: Introduce reusable web auth/session bootstrap primitives <!-- deps: none, parallel: pg-1 -->
  - **Type**: `infrastructure`
  - **Acceptance**: auth state is no longer hydrated ad hoc inside `AccountPage`; the web app has a shared bootstrap path that can use the refresh cookie and apply/clear access tokens centrally
  - **Files**: `web/src/lib/api.ts`, new auth/bootstrap helpers as needed
- [x] Task 1.2: Add dedicated browser sign-in route and provider flows <!-- deps: 1.1 -->
  - **Type**: `feature`
  - **Acceptance**: browser users get a real sign-in screen with Apple and Google entrypoints wired to backend auth endpoints, and the required client-ID env vars are documented in `web/.env.example`
  - **Files**: `web/src/App.tsx`, `web/src/pages/SignInPage.tsx`, `web/.env.example`
- [x] Task 1.3: Normalize account page data hooks to current backend response shapes <!-- deps: none, parallel: pg-1 -->
  - **Type**: `code`
  - **Acceptance**: account/profile/orders/calendar hooks match the current API contracts, especially `/calendar/month` returning `{ days }` rather than an array
  - **Files**: `web/src/pages/AccountPage.tsx`, supporting account components as needed

## Phase 2: Route Protection And Lifecycle

### Tasks

- [x] Task 2.1: Gate the account surface behind auth bootstrap and signed-out redirect <!-- deps: 1.1, 1.2 -->
  - **Type**: `feature`
  - **Acceptance**: signed-out users are routed into the web sign-in flow and signed-in users land on the account surface without manual token hydration hacks
  - **Files**: `web/src/App.tsx`, `web/src/pages/AccountPage.tsx`
- [x] Task 2.2: Harden refresh-cookie bootstrap and sign-out cleanup <!-- deps: 1.1, 1.2 -->
  - **Type**: `integration`
  - **Acceptance**: refresh survives reload through the cookie bootstrap path, sign-out clears client state predictably, and token handling stays centralized
  - **Files**: `web/src/lib/api.ts`, auth/bootstrap helpers, `web/src/pages/AccountPage.tsx`

## Phase 3: Verification

### Tasks

- [x] Task 3.1: Run focused web workspace build verification <!-- deps: 1.3, 2.1, 2.2 -->
  - **Type**: `test`
  - **Acceptance**: `npm run build --workspace=web` succeeds after the auth/bootstrap/account changes
  - **Files**: `web/package.json`, touched web source files

## Validation Commands

- `npm run build --workspace=web`

## Plan Evaluation

- **Date**: `2026-04-12`
- **Evaluator**: `loop-plan-evaluator`
- **Verdict**: `PASS`
- **Summary**:
  - the plan stays inside the web track by consuming existing backend auth/profile/calendar routes rather than expanding backend scope again
  - provider configuration is handled as env/documentation work inside the web app, while cloud-console provisioning remains explicitly deferred
  - auth bootstrap, route protection, and data normalization are sequenced so shared client infrastructure lands before provider and account-page rewrites
  - board review was skipped because this is an implementation plan for a missing web auth surface, not a new product or architecture direction

## Execution Results

- Added a shared auth runtime in `web/src/lib/auth.tsx` and upgraded `web/src/lib/api.ts` so browser access tokens stay in memory, refresh bootstraps from the auth cookie, and `401` responses can retry once after a refresh.
- Added a dedicated `/sign-in` route in `web/src/pages/SignInPage.tsx` with Google Identity Services and Apple JS entrypoints wired to the existing backend `/auth/oauth/google` and `/auth/oauth/apple` endpoints.
- Protected `/account` in `web/src/App.tsx`, switched the header CTA to `/sign-in` or `/account` based on auth state, and removed the old `localStorage` token hydration from `web/src/pages/AccountPage.tsx`.
- Normalized the account calendar hook against the live `{ days }` month payload and mapped it into the heatmap component without pushing backend-shape details into the presentational calendar.
- Documented the required web OAuth env placeholders in `web/.env.example`.

## Execution Evaluation

- **Verdict**: `PASS`
- **Verified**:
  - `npm run build --workspace=web` passed
- **Observed but not blocking**:
  - `npm run lint --workspace=web` still fails on pre-existing `react-refresh/only-export-components` issues in shared UI files (`badge.tsx`, `button.tsx`, `tabs.tsx`) plus unused `eslint-disable` directives in `StorePage.tsx`
  - interactive browser verification of Apple/Google OAuth was not completed in-session because the local browser automation tooling was unavailable and provider configuration remains environment-dependent
