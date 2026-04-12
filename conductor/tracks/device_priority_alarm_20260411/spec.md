# Device Priority Alarm And Favorites

## Track ID

`device_priority_alarm_20260411`

## Summary

Promote device favorites and BLE alarm behavior from handoff backlog into a real cross-surface product slice: favorite devices, nickname persistence, smarter signal thresholds, and a better disconnect experience.

## Why This Track Exists

- the handoff still calls out favorite devices and alarm polish as launch-critical iOS work
- device favorites and nicknames are not yet part of the persisted product contract
- disconnect handling still needs a clearer “End Session” vs “Lost Gear” path

## In Scope

- add favorite-device and nickname fields where needed for persisted device data
- update iOS device surfaces to favorite, sort, and edit device priority metadata
- refine BLE signal monitoring thresholds and disconnect handling
- improve the disconnect UX so users can explicitly end a session or escalate into the lost-gear path

## Out Of Scope

- Apple Watch companion behavior
- net-new hardware integrations
- public web redesign
- unrelated social or commerce work

## Acceptance Criteria

1. Favorite device and nickname metadata persist cleanly and are reflected in iOS device surfaces.
2. Favorite devices sort ahead of others and receive monitoring priority where the product uses device ordering.
3. Disconnect handling offers a clear “End Session” vs “Lost Gear” path instead of forcing one panic path.
4. BLE signal progression is better calibrated than the current placeholder threshold behavior.
5. Touched API and iOS surfaces build successfully.

## Dependencies

- `realtime_worker_hardening_20260411`

## Notes

Battery telemetry can be added opportunistically if the implementation stays bounded, but the core acceptance criteria are favorite-device persistence plus improved alarm/disconnect behavior.
