# Run Tracking And Metrics Design

## Goal

Deliver the first usable implementation of the deferred run-tracking-and-metrics work without opening a brand-new GPS/polyline subsystem. The repo already has an existing workout model, workout UI, gym sessions, and calendar aggregation, so the fastest durable path is to activate those contracts and expose a browser-visible metrics surface on top of them.

## Scope

This slice will ship:

- live backend workout endpoints backed by the existing `Workout` model
- a metrics aggregation endpoint combining gym-session and workout data
- iOS workout contract alignment so the existing workout history and active workout flows use live API data
- a protected web metrics page that renders the first account-adjacent analytics surface

This slice will not ship:

- continuous GPS run capture
- run polylines or route maps
- new realtime or worker orchestration
- background notifications beyond the already-shipped auth/session work

## Approach Options

### Option A: Build a brand-new `Run` subsystem first

Pros:

- aligns literally with the deferred placeholder name
- creates a dedicated route-map-ready data model

Cons:

- duplicates concepts already present in `Workout`
- requires new iOS UX, new backend model, and new web map rendering before any existing surface becomes live
- leaves the current workout UI and stubbed workout routes unresolved

### Option B: Activate workout tracking and add metrics on top of sessions and workouts

Pros:

- uses existing models, screens, and route mounts
- resolves an actual current gap: iOS workout UI points at `501` workout endpoints
- creates an immediately useful browser metrics surface with minimal new surface area

Cons:

- does not yet deliver GPS route capture
- “run tracking” becomes a staged capability rather than a single big-bang feature

### Recommendation

Use Option B now. It is the smallest end-to-end slice that turns existing dormant UI into live product behavior across API, iOS, and web. GPS route capture can remain a follow-up once the generic workout/metrics foundation is stable.

## Backend Design

Add a `WorkoutService`-style implementation directly behind `api/src/modules/workouts/routes.ts` using the existing `Workout` model. The response contract should match what the iOS views need instead of leaking raw Mongoose field names:

- `_id`
- `name`
- `startedAt`
- `endedAt`
- `durationMinutes`
- `durationSeconds`
- `exerciseCount`
- `exercises` with `name`, `sets`, `reps`, `weightKg`
- `notes`
- `source`

Support:

- `GET /workouts`
- `POST /workouts`
- `GET /workouts/:id`
- `PATCH /workouts/:id`
- `DELETE /workouts/:id`
- `POST /workouts/:id/complete`
- `GET /workouts/metrics/overview`

`/workouts/metrics/overview` will aggregate:

- average gym-session duration for the trailing 30 days
- total gym sessions this week and this month
- current streak and longest streak by day with any session/workout activity
- total completed workouts
- total workout minutes this month
- workout counts by weekday and by hour-of-day
- recent workout list for quick browser inspection

## iOS Design

Align the workout request and DTOs with the backend instead of expecting the old placeholder fields:

- `CreateWorkoutBody` should send `name`, `startedAt`, `endedAt`, `notes`, `source`, optional `gymId`, and encoded exercise sets
- `WorkoutDTO` should decode `durationMinutes`, `exerciseCount`, and `weightKg`
- `ActiveWorkoutViewModel` should post a complete workout payload that includes entered exercises
- the Workouts tab in `MainTabView` should render `WorkoutListView` instead of a placeholder so the live feature is reachable

## Web Design

Add a protected `/metrics` page behind the existing auth runtime. The page should avoid new chart dependencies and instead use cards plus simple inline SVG/CSS charts.

Sections:

- 30-day performance summary cards
- session streak and total counts
- workout activity by weekday
- workout activity by hour
- recent completed workouts table/list

Navigation should expose the page from authenticated surfaces without changing the public marketing IA.

## Error Handling

- metrics endpoint should return zero-state payloads, not `null`, for new accounts
- iOS workout creation should surface save failures without silently dismissing the session
- web metrics page should show a distinct signed-in error state with retry guidance

## Validation

- API build, type-check, lint, test
- web build
- iOS simulator build
- manual contract sanity via existing iOS decoders and web page rendering against the shared API envelope

## Follow-Up

Once this slice lands, the next expansion can decide whether GPS route capture belongs as:

- a dedicated `Run` model, or
- an extension of `Workout` for cardio activities with optional route payloads
