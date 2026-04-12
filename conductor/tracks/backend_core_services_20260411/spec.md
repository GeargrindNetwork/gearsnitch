# Backend Core Services

## Track

- **Track ID**: `backend_core_services_20260411`
- **Priority**: `P0`
- **Type**: `feature`

## Overview

Replace the remaining stubbed or partial backend service layers that block real product behavior across iOS and web.

## Deliverables

- implement real service-layer logic for the highest-value user flows currently identified in `docs/HANDOFF.md`
- wire route modules to those services without breaking the existing response envelope
- support the account, device, gym, session, calendar, and store-adjacent surfaces that already exist in iOS and web
- document any intentionally deferred modules in the track plan instead of leaving ambiguity

## Acceptance Criteria

- the selected routes no longer return placeholder `501` responses
- `/users/me` and related account data are backed by real persistence behavior
- downstream clients can read live user/account state without mock data assumptions
- the API workspace builds cleanly after the changes

## Dependencies

- existing Mongoose models and route modules in `api/src`
- shared response utilities and auth middleware

## Out Of Scope

- new product areas that do not unblock the current app surfaces
- large infrastructure redesigns
- net-new analytics or dashboard features not needed for the dependent tracks
