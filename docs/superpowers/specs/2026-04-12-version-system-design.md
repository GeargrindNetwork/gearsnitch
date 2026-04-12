# GearSnitch Version System Design

Date: 2026-04-12
Status: Approved for implementation
Scope: API, web, and iOS

## Goal

Add a real version system across the GearSnitch website and iOS app so the live backend can decide whether a client is still supported, expose release notes, and block stale product clients when they fall below the minimum supported version.

The system should:

- treat the live deployed API as the runtime authority for compatibility
- keep one shared product version across web and iOS
- expose release notes and build metadata across surfaces
- hard-block unsupported clients from the product experience
- leave public website pages reachable even when the web app shell is blocked

## Scope

This slice will ship:

- a committed release policy file in the repo
- API loading and validation of that release policy at startup
- a normalized remote config and compatibility contract for clients
- client version/build headers on web and iOS requests
- strict server-side rejection for unsupported product clients on protected routes
- a blocking update experience in iOS
- a blocking refresh/update experience on protected web routes
- visible version and build metadata on both platforms

This slice will not ship:

- an internal admin console for changing release policy without deploy
- per-platform release channels
- separate web and iOS semantic versions
- App Store automation or release pipeline automation beyond validation hooks

## Approach Options

### Option A: API-authoritative release policy

Store a release policy file in the repo, deploy it with the API, and let the live API decide compatibility for every client.

Pros:

- one runtime decision point
- supports strict gating and server enforcement
- keeps clients aligned with live backend contracts
- gives web and iOS one shared policy without duplicated logic

Cons:

- requires clients to fetch release state before rendering protected product flows
- needs careful bootstrap handling for stale sessions and cached config

### Option B: Client-bundled manifest only

Bundle a shared manifest into web and iOS and let each client self-enforce without a server compatibility decision.

Pros:

- simpler bootstrap path
- fewer moving parts on the backend

Cons:

- cannot reliably block stale clients server-side
- drifts more easily from real backend support policy
- weaker contract for strict enforcement

### Option C: Build registry or deployment inventory

Publish build metadata from each surface into a separate registry and compute compatibility from that registry.

Pros:

- flexible for future channel management
- useful for more advanced release observability

Cons:

- too much machinery for the current need
- adds another system to maintain
- slows down delivery of the actual gating behavior

### Recommendation

Use Option A.

It is the smallest design that satisfies the product requirements:

- one shared product version
- deployment-driven runtime authority
- repo-backed release management through code review
- strict server-side compatibility enforcement

## Source Of Truth

The source of truth is the release policy deployed with the live API.

Operationally, that policy originates as a committed file in the repo, but compatibility decisions are made by whatever release policy the currently deployed API revision is running. This keeps the system deployment-driven at runtime while still making release changes reviewable in git.

Recommended file:

- `config/release-policy.json`

Recommended top-level shape:

- `version`
- `minimumSupportedVersion`
- `forceUpgrade`
- `publishedAt`
- `releaseNotes`
- `environment`

Recommended metadata block:

- `buildId`
- `gitSha`
- `builtAt`

The shared semantic version applies to both web and iOS. Platform-specific build metadata remains separate and is reported by each client.

## Version Model

Use semantic versioning for the shared product version.

- `version`: the current live product version
- `minimumSupportedVersion`: the oldest client version allowed to access protected product routes
- `forceUpgrade`: explicit hard-upgrade flag for the current release window
- `releaseNotes`: short user-facing notes describing what changed

Platform build metadata is additive rather than authoritative.

### Web local metadata

The web build should embed:

- `platform = web`
- `version`
- `buildId` or deployment identifier
- `gitSha`
- `builtAt`

### iOS local metadata

The iOS app should expose:

- `platform = ios`
- `version = CFBundleShortVersionString`
- `build = CFBundleVersion`
- optional `gitSha` and `builtAt` if the build pipeline stamps them into Info.plist

## API Design

The existing config module already exposes public remote config and should become the main release-policy delivery surface.

### Config payload

`GET /api/v1/config/app` should return:

- `featureFlags`
- `release`
- `compatibility`
- `maintenance`
- `server`

Recommended `release` fields:

- `version`
- `minimumSupportedVersion`
- `forceUpgrade`
- `releaseNotes`
- `publishedAt`

Recommended `compatibility` fields:

- `status` with values such as `supported` or `blocked`
- `reason` such as `below_minimum_version`
- `clientVersion`
- `minimumSupportedVersion`
- `currentVersion`

Recommended `server` fields:

- `version`
- `buildId`
- `gitSha`
- `builtAt`
- `environment`

### Request contract

All product clients should send:

- `X-Client-Platform`
- `X-Client-Version`
- `X-Client-Build`

Optional future headers:

- `X-Client-Git-Sha`
- `X-Client-Built-At`

### Server enforcement

Protected API routes should run version compatibility middleware before core business logic. If a client is below `minimumSupportedVersion`, the API should return:

- `426 Upgrade Required`

The response body should reuse the normalized compatibility payload so both web and iOS can render the same blocking state.

Public bootstrap endpoints must remain reachable:

- `/api/v1/config/app`
- any intentionally public support or legal endpoints

## Web Design

The current web app already separates public and authenticated routes in `web/src/App.tsx`, which is the natural insertion point for gating.

### Web enforcement rules

Public routes remain reachable:

- `/`
- `/privacy`
- `/terms`
- `/support`
- `/delete-account`
- `/sign-in`

Protected product routes are blocked when incompatible:

- `/account/*`
- `/metrics`
- `/runs`
- any future authenticated app routes

### Web runtime structure

Add:

- a build-time release metadata module
- a `ReleaseProvider` near the app root
- a protected-route release gate layered with the existing auth gate

### Web blocked UX

When the loaded web client is unsupported:

- replace protected route content with a blocking screen
- show current loaded version
- show required version
- show release notes
- show `Refresh Now` CTA that performs a hard reload
- optionally allow `Sign Out`

The website should still function as a marketing and support site while the authenticated app experience is blocked.

### Visible web version info

Add visible version/build info in at least one authenticated surface and optionally the footer:

- current deployed version
- build identifier or short git SHA

## iOS Design

The iOS app already exposes local version/build values and already has a root-level view gate in `RootView`, which is the correct place to enforce compatibility.

### iOS runtime structure

Add:

- `ReleaseGateManager` or equivalent observable state owner
- remote fetch through the existing config client
- version comparison utility
- full-screen blocking update view

### iOS enforcement rules

During app startup and foreground refresh:

- fetch `GET /api/v1/config/app`
- compare local installed version to `minimumSupportedVersion`
- if unsupported, block access to onboarding, sign-in, and the main tabs

### iOS blocked UX

Show a full-screen `Update Required` view with:

- installed version
- required version
- release notes
- `Update on the App Store` CTA
- optional support link

This view should not be dismissible because the chosen behavior is strict gating.

### Visible iOS version info

Settings should continue showing:

- version
- build

If available, add:

- short server version or build metadata for support diagnostics

## Compatibility Logic

Compatibility should be decided with semantic version comparison, not string comparison.

Rules:

- if `clientVersion < minimumSupportedVersion`, status is `blocked`
- otherwise status is `supported`
- `forceUpgrade` remains available for release messaging, but strict blocking is still governed by `minimumSupportedVersion`

If a client does not send a version header on a protected route, the safe default is to treat it as unsupported once the rollout is complete. During migration, the middleware can allow missing headers temporarily behind a feature flag until both web and iOS are updated.

## Operations

Release publishing workflow:

1. Update `config/release-policy.json` in a PR.
2. Set the new shared semantic version.
3. Raise `minimumSupportedVersion` when backend contract changes require it.
4. Add release notes.
5. Deploy API and web with the updated release policy.
6. Ship iOS with matching `MARKETING_VERSION` and build number.

Because the live API is authoritative, the deployed API revision determines who is allowed into the product at runtime.

## Validation

Require:

- API tests for release policy parsing and semantic version comparison
- API contract tests for `/api/v1/config/app`
- API middleware tests for `426 Upgrade Required` behavior
- web tests proving public routes remain reachable while protected routes block
- iOS tests proving incompatible versions present the blocking update screen
- validation that iOS `MARKETING_VERSION` matches the shared release version

## Out Of Scope

- Android support
- phased rollout channels
- canary release cohorts
- server-managed admin editing of release policy
- detailed changelog history UI

## Follow-Up

Once the core version system lands, future expansion can add:

- a release history endpoint and changelog screen
- richer deployment metadata in support diagnostics
- build-pipeline automation for stamping git SHA and built-at fields
- admin or ops tooling for preparing release policy updates
