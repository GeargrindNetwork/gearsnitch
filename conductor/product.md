# GearSnitch Product Context

## Goal

Ship a production-ready fitness and gear-awareness product across three surfaces:

- native iOS app for on-device sensing, geofence/session behavior, and personal workflows
- web app for account access, commerce, support, and browser-visible metrics
- backend services that persist user, device, session, store, and health-adjacent state

## Current Reality

From `docs/HANDOFF.md`:

- the public website and legal pages are live
- the API and worker are deployed, but many product routes still return `501`
- the iOS app has substantial UI and device capability, but many flows still depend on stubbed backend data
- the web app has shell pages, commerce scaffolding, and account UI, but no real browser sign-in flow yet

## Primary User Outcomes

- a user can sign in on iOS and web with the same backend account
- tracked devices, gyms, sessions, purchases, and profile data persist across surfaces
- iOS experiences stay device-native, but account and history data become portable
- the team can resume work from file-backed loop state instead of reconstructing context each session

## Scope Constraints

- preserve the current monorepo structure
- prefer small, dependency-aware tracks over one giant catch-all implementation push
- backend work should unblock real product behavior before net-new surfaces are added
- do not rely on implied cross-surface session sharing; explicit auth flows are required per surface
