# iOS Completion

## Track

- **Track ID**: `ios_completion_20260411`
- **Priority**: `P1`
- **Type**: `feature`
- **Depends On**: `backend_core_services_20260411`

## Overview

Finish the highest-value remaining iOS application work that depends on real backend state and bring the app closer to an operationally complete first release.

## Deliverables

- connect unfinished iOS account- and data-backed flows to live backend services
- close the most important gaps called out in `docs/HANDOFF.md` after backend persistence exists
- prioritize completion work that strengthens the day-to-day product loop: devices, sessions, gyms, profile state, and related UX polish
- record any net-new capabilities that should become separate follow-up tracks instead of quietly expanding this one

## Acceptance Criteria

- the selected iOS flows operate against real backend data rather than placeholders
- session and account state behave consistently with the web and backend contracts
- the iOS target builds after the changes
- any deferred iOS work is explicitly captured in roadmap or follow-up track notes

## Dependencies

- backend core services
- existing iOS feature surfaces already present in `client-ios/`

## Out Of Scope

- wholly new product pillars that deserve their own track, such as full run tracking if it grows beyond a contained slice
- unrelated visual redesign work
