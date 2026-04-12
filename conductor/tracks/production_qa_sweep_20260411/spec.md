# Production QA Sweep

## Track ID

`production_qa_sweep_20260411`

## Summary

Close the loop after the remaining product slices land: remove quality-baseline debt that blocks hard gates, run the cross-surface verification sweep, and document any external/manual launch blockers that still remain.

## Why This Track Exists

- the current loop still carries known validation debt, especially the pre-existing web lint baseline
- later launch work needs one place that records the real end-to-end verification state across iOS, web, API, worker, and realtime
- external configuration blockers should be explicit instead of being rediscovered every session

## In Scope

- clean the remaining validation debt required to turn key workspace checks into hard gates
- run the repo-wide or broadest-meaningful quality commands after the remaining tracks land
- create a cross-surface QA checklist and outcome artifact
- document any remaining external/manual blockers such as Apple, Google, APNs, or payment configuration

## Out Of Scope

- new product feature development
- marketing site redesign
- manual portal changes that require human credentials or approvals

## Acceptance Criteria

1. The remaining validation baseline debt required for the final sweep is removed or explicitly documented as external.
2. The broad quality pass for the finished product surfaces is executed and captured.
3. A cross-surface QA artifact exists for core sign-in, device, workout, run, notification, and metrics flows.
4. Remaining manual blockers are documented in one place instead of being implicit.

## Dependencies

- `device_priority_alarm_20260411`
- `richer_web_dashboard_analytics_20260411`

## Notes

This is the closure track for the current autonomous loop. Anything left afterward should be either external/manual setup or explicitly new roadmap scope.
