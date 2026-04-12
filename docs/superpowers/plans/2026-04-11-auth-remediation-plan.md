# GearSnitch Auth Remediation Plan

> **For agentic workers:** Use `systematic-debugging` during implementation and verify each phase before moving to the next.

**Goal:** Restore Apple sign-in from the iOS app, ensure the backend creates or links the correct user record, and define and implement a real web sign-in path for the same account.

**Current Root Cause Summary:**
- iOS auth requests are built against `https://api.gearsnitch.com/api/v1` while endpoint paths also include `/api/v1`, producing URLs like `/api/v1/api/v1/auth/oauth/apple`.
- The web app claims the iOS session is shared, but no token handoff or browser sign-in flow exists.
- The backend can already represent a cross-platform user account, but the product-level web auth flow is incomplete.

**Recommended Approach:** Fix the broken iOS request path first, then implement an explicit web authentication strategy instead of relying on the current unimplemented “shared session” assumption.

---

## File Structure

- Modify: `client-ios/GearSnitch/Shared/Models/AppConfig.swift`
- Modify: `client-ios/GearSnitch/Core/Network/APIEndpoint.swift`
- Modify: `client-ios/GearSnitch/Core/Network/RequestBuilder.swift`
- Modify: `client-ios/GearSnitch/Core/Auth/AuthManager.swift`
- Modify: `api/.env`
- Modify: `api/.env.example`
- Modify: `api/src/services/AuthService.ts`
- Add: `api/src/**/__tests__/*auth*` or equivalent auth test file(s)
- Modify: `web/src/pages/AccountPage.tsx`
- Modify: `web/src/lib/api.ts`
- Add: web auth flow files if implementing browser login
- Optional add: API routes for browser auth handoff if implementing true app-to-web session exchange

---

## Sprint 1: Restore iOS Apple Login

**Goal:** Make the iOS app hit the correct auth routes and verify Apple login creates or links a backend user.

**Demo/Validation:**
- Apple sign-in from iOS returns `accessToken`, `refreshToken`, and `user`
- `/api/v1/auth/me` succeeds after sign-in
- `/api/v1/users/me` returns the created profile

### Task 1.1: Normalize API base URL and endpoint responsibilities
- **Location:** `client-ios/GearSnitch/Shared/Models/AppConfig.swift`, `client-ios/GearSnitch/Core/Network/APIEndpoint.swift`, `client-ios/GearSnitch/Core/Network/RequestBuilder.swift`
- **Description:** Remove the duplicated `/api/v1` composition bug. Pick one convention and apply it consistently:
  - Option A: base URL is origin only, endpoints include `/api/v1/...`
  - Option B: base URL includes `/api/v1`, endpoints become relative without the version prefix
- **Recommendation:** Use Option A. It is less error-prone for REST and WebSocket construction.
- **Acceptance Criteria:**
  - Apple login resolves to exactly `https://api.gearsnitch.com/api/v1/auth/oauth/apple`
  - Google login, refresh, logout, and `/users/me` also resolve correctly
- **Validation:**
  - Add a small request-builder test or debug assertion for URL output
  - Manually log final URLs in development once

### Task 1.2: Verify the iOS sign-in happy path end to end
- **Location:** `client-ios/GearSnitch/Core/Auth/AuthManager.swift`
- **Description:** Confirm Apple credential fields are serialized correctly and that login errors surface useful backend messages in development.
- **Dependencies:** Task 1.1
- **Acceptance Criteria:**
  - Apple sign-in no longer fails due to route mismatch
  - User-facing errors distinguish server rejection from local token extraction failure
- **Validation:**
  - Manual sign-in on simulator/device
  - Confirm `AuthState.authenticated` is reached

### Task 1.3: Capture a known-good backend-created Apple account
- **Location:** backend database plus `/users/me`
- **Description:** Sign in once from iOS and verify the stored user has `appleId`, `authProviders: ['apple']` or linked providers, and the expected email/display name behavior.
- **Dependencies:** Tasks 1.1, 1.2
- **Acceptance Criteria:**
  - First-time Apple sign-in creates a user
  - Repeat Apple sign-in links to the same user
  - Existing email-based user is linked instead of duplicated
- **Validation:**
  - Check Mongo user document
  - Verify `/api/v1/users/me` response contents

---

## Sprint 2: Harden Backend Apple Auth

**Goal:** Make Apple auth robust and test-covered so it does not regress.

**Demo/Validation:**
- Auth service tests cover Apple account creation, linking, and repeat login
- Environment validation fails fast when required auth config is missing in the target environment

### Task 2.1: Audit backend Apple config assumptions
- **Location:** `api/.env`, `api/.env.example`, `api/src/config/index.ts`, `api/src/services/AuthService.ts`
- **Description:** Verify the production/deployment environment has the correct Apple audience and document it. `APPLE_CLIENT_ID` must match the Apple service or app identifier used by the tokens being sent by iOS.
- **Dependencies:** Sprint 1 validation
- **Acceptance Criteria:**
  - Required Apple variables are documented and validated
  - Startup or auth logging makes misconfiguration diagnosable
- **Validation:**
  - Development boot with env check
  - Staging/prod secret audit before release

### Task 2.2: Add Apple auth service tests
- **Location:** new auth test file(s) under `api/src`
- **Description:** Add tests around `AuthService.signInWithApple` and route-level behavior.
- **Dependencies:** Task 2.1
- **Acceptance Criteria:**
  - Covers first-time account creation
  - Covers linking to an existing email-hash user
  - Covers repeat login with existing `appleId`
  - Covers missing-email first-login rejection behavior
- **Validation:**
  - `npm test --workspace=api`

### Task 2.3: Add request/response diagnostics around auth failures
- **Location:** `api/src/modules/auth/routes.ts`, `api/src/services/AuthService.ts`
- **Description:** Improve structured logging for Apple verification failures without logging tokens or PII.
- **Dependencies:** Task 2.2
- **Acceptance Criteria:**
  - Logs indicate whether failure was route validation, JWT verification, missing audience, or account-linking logic
- **Validation:**
  - Trigger a controlled invalid-token request in development and inspect logs

---

## Sprint 3: Implement a Real Web Sign-In Strategy

**Goal:** Replace the current non-functional “shared session” assumption with an explicit, supported browser auth flow.

**Demo/Validation:**
- A user created from iOS can sign into the website
- The web app no longer depends on an unexplained `localStorage` token appearing magically

### Task 3.1: Choose the cross-platform auth model
- **Decision Required:** pick one of these before implementation:
  - **Model A, recommended:** Web has its own sign-in flow using the same backend user account. Apple/web login resolves to the same user through `appleId` or `emailHash`.
  - **Model B:** iOS hands off a browser session through a one-time token exchange or deep link.
- **Recommendation:** Model A. It is simpler, more secure, and matches normal browser expectations. Model B is only needed if you explicitly want “open website already signed in from phone.”
- **Acceptance Criteria:**
  - One documented decision for product + engineering
- **Validation:**
  - Brief ADR or implementation note in repo

### Task 3.2: Remove or replace the misleading web copy
- **Location:** `web/src/pages/AccountPage.tsx`
- **Description:** Update the page text so it matches reality until the new auth flow is live.
- **Dependencies:** Task 3.1
- **Acceptance Criteria:**
  - No claim that the session is shared unless that feature actually exists
- **Validation:**
  - Manual browser check

### Task 3.3A: If choosing Model A, build browser sign-in
- **Location:** web auth pages/components, `web/src/lib/api.ts`, backend auth routes as needed
- **Description:** Implement a proper web login entry point, store tokens intentionally, and hydrate auth state in a supported way.
- **Dependencies:** Task 3.1
- **Acceptance Criteria:**
  - User can sign in on web with the same Apple-backed account
  - `localStorage` token usage is explicit and set by a real login action, or replaced with cookie-based auth
- **Validation:**
  - Browser sign-in test
  - `/users/me` loads after login

### Task 3.3B: If choosing Model B, build session handoff
- **Location:** new backend handoff route(s), iOS deep-link/open-in-browser action, web token-exchange page
- **Description:** Generate a one-time exchange token from the authenticated app session, open the browser with that token, redeem it server-side, then establish a browser session.
- **Dependencies:** Task 3.1
- **Acceptance Criteria:**
  - Opening the site from the app signs the same user into web securely
  - Exchange token is short-lived and one-time-use
- **Validation:**
  - iPhone-to-browser handoff test
  - Replay protection test

---

## Sprint 4: Regression Coverage and Release Readiness

**Goal:** Ensure auth works across iOS and web without hidden path or session regressions.

**Demo/Validation:**
- Repeated Apple login works
- Web account access works for the same user
- Auth copy, behavior, and token storage are aligned

### Task 4.1: Add client-side auth regression coverage
- **Location:** iOS tests and web tests as applicable
- **Description:** Add at least one test or scripted verification for URL construction and one for web auth state hydration.
- **Dependencies:** Sprints 1 and 3
- **Acceptance Criteria:**
  - Duplicate `/api/v1` bug is covered
  - Web login flow or handoff flow is covered
- **Validation:**
  - Relevant iOS and web test commands

### Task 4.2: Run quality gates
- **Location:** repo root
- **Description:** Run project checks after implementation.
- **Dependencies:** all previous tasks
- **Acceptance Criteria:**
  - Relevant workspaces pass lint, type-check, and tests
- **Validation:**
  - `npm run turbo:quality`
  - `npm run turbo:test`

---

## Testing Strategy

- Start with URL-construction verification on iOS before touching backend logic.
- Use one known Apple login account for repeatability.
- Validate both first-time sign-up and repeat sign-in.
- Validate account reuse on web against the same backend user record.
- Prefer automated coverage for:
  - request path composition
  - `AuthService.signInWithApple`
  - web auth hydration/sign-in

## Potential Risks & Gotchas

- Changing `apiBaseURL` can affect WebSocket URL generation, so REST and socket construction must be verified together.
- If Apple tokens from iOS and browser use different audiences, account linking needs a clear provider strategy.
- If browser auth remains token-in-`localStorage`, session persistence and logout semantics must be explicit and secure.
- A true app-to-web shared session requires additional backend security work and should not be implied by static copy alone.

## Rollback Plan

- Revert the iOS networking changes as one commit if route normalization breaks unrelated endpoints.
- Keep the web copy conservative until the chosen web auth model is live.
- Ship Sprint 1 independently if needed; it fixes the immediate iOS failure without forcing the web auth redesign in the same release.
