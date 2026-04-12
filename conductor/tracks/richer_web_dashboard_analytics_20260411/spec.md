# Richer Web Dashboard Analytics

## Track ID

`richer_web_dashboard_analytics_20260411`

## Summary

Expand the first `/metrics` slice into the fuller browser dashboard called for in the handoff: run distance trends, device status cards, and richer run-centric analytics.

## Why This Track Exists

- the current `/metrics` page is intentionally the first thin slice, not the final browser dashboard
- the handoff still calls for distance totals, trend arrows, device status cards, and run-gallery behavior
- once run capture and realtime hardening land, the browser can expose that richer data without relying on placeholders

## In Scope

- extend backend/browser analytics contracts to include run distance and trend summaries
- show device status cards with last-seen or latest-known state where the backing data is available
- add richer run-oriented browser analytics such as route gallery cards or drill-down navigation
- preserve zero-state behavior for users who still have no runs or no tracked devices

## Out Of Scope

- public marketing changes
- admin or internal-only analytics
- unrelated store, referral, or nutrition reporting
- social map sharing

## Acceptance Criteria

1. Authenticated browser users can see richer analytics than the current summary-only `/metrics` slice, including run-oriented data.
2. Device status cards render from live backend/runtime data rather than placeholders.
3. The dashboard remains stable for zero-data accounts.
4. The web build passes and any touched backend checks pass.

## Dependencies

- `gps_route_capture_20260411`
- `realtime_worker_hardening_20260411`

## Notes

This track should extend the browser analytics surface, not redesign the public website shell.
