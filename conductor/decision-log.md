# GearSnitch Decision Log

| Date | Decision | Impact |
|------|----------|--------|
| 2026-04-11 | The repo-local `/loop` workflow will use backend-first sequencing: backend core services must land before web auth/dashboard and iOS completion tracks. | Prevents parallel work from encoding assumptions against stubbed APIs. |
| 2026-04-11 | Browser auth will be treated as an explicit surface-specific sign-in flow, not session sharing from iOS. | Keeps account identity consistent while respecting platform-specific OAuth behavior. |
| 2026-04-12 | The first run-tracking delivery slice will ship on the existing `Workout` model and shared metrics surfaces, while continuous GPS capture and replay stay deferred. | Unblocks real workout persistence and analytics across API, iOS, and web without coupling the slice to unreconciled route-recording architecture. |
