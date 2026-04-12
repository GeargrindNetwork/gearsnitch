# GearSnitch Knowledge Patterns

## Product Delivery Patterns

- Finish persistence before polishing downstream surfaces. Several iOS and web experiences already exist visually, but they remain blocked on backend CRUD and session behavior.
- Treat auth as a shared account model with surface-specific entrypoints. iOS and web can share the same backend user while using different provider audiences and client IDs.

## Repo Patterns

- Validate changes at the narrowest useful scope first, then broaden to workspace-level checks once the slice is stable.
- Keep platform work split by dependency direction: backend first, then web session bootstrap, then iOS live-data completion.
- ESLint 9 workspace commands need a local flat config in each package that invokes `eslint` directly; otherwise `npm run lint --workspace=<pkg>` fails before checking code.
- When replacing stub routes without a full integration harness, add a lightweight regression sweep that proves live service bindings are present and deferred endpoints remain explicitly bounded.
- When backend payloads are already shared by another surface, prefer client-side normalization on the dependent platform over reshaping the shared API contract mid-track.
- In Swift, adding a custom `Decodable.init(from:)` removes the synthesized memberwise initializer; restore an explicit initializer if previews or sibling views construct the type directly.
- For browser surfaces sharing the mobile auth backend, keep the access token in memory and use the refresh-cookie path plus a centralized `401` retry hook instead of persisting bearer tokens in `localStorage`.
- Normalize backend-rich account/calendar payloads in the page hook and keep the presentational heatmap component generic so UI state stays decoupled from response-envelope churn.
- Ship run-tracking incrementally on top of the existing `Workout` model first; use that shared data plane to unlock backend metrics, iOS history, and web analytics before introducing GPS-specific capture and replay.
- If an Xcode project is missing a checked-in shared scheme, validate compile health with `xcodebuild -target <AppTarget> -sdk iphonesimulator ... build` instead of treating `-scheme` failure as an application compile failure.
