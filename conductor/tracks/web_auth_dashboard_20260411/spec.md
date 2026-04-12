# Web Auth And Dashboard

## Track

- **Track ID**: `web_auth_dashboard_20260411`
- **Priority**: `P1`
- **Type**: `feature`
- **Depends On**: `backend_core_services_20260411`

## Overview

Turn the web app into a real account surface by adding explicit browser sign-in, session bootstrap, and live account/dashboard data backed by the API.

## Deliverables

- add browser sign-in for both Apple and Google using the shared backend account model
- replace the current ad hoc token hydration in the account page with a real auth bootstrap flow
- route signed-out users into a dedicated web sign-in experience
- ensure the account/dashboard surface reads real API-backed data instead of placeholder assumptions

## Acceptance Criteria

- a browser user can sign in with Apple or Google and reach the account surface with a real session
- web auth survives refresh via the refresh-cookie bootstrap path
- sign-out clears web auth state cleanly
- the web workspace builds cleanly after the changes

## Dependencies

- backend auth endpoints
- browser provider configuration for Apple and Google
- account/profile routes made real by the backend track

## Out Of Scope

- large marketing-site redesigns
- brand-new admin or analytics portals outside the account/dashboard surface
