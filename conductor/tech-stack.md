# GearSnitch Tech Stack Context

## Architecture

- `api/` — Express + TypeScript + Mongoose + Redis-backed auth/session behavior
- `web/` — Vite + React + React Router + TanStack Query + shadcn/ui
- `client-ios/` — SwiftUI app with Bluetooth, location, HealthKit, payments, and realtime clients
- `worker/` — BullMQ job processors
- `realtime/` — Socket.IO service
- `shared/` — shared types and schema contracts

## Operational Constraints

- repo has pre-existing dirty work; never revert unrelated changes
- governance files such as `AGENTS.md` must not be edited directly
- auth must support separate provider audiences for iOS and web where required
- the loop should treat backend persistence as the primary blocker for downstream product completion

## Validation Commands

Use the smallest relevant command set for the touched surface, then broaden as needed:

- root:
  - `npm run build`
  - `npm run lint`
  - `npm run type-check`
  - `npm run test`
- targeted:
  - `npm run build --workspace=api`
  - `npm run build --workspace=web`
  - `xcodebuild -project client-ios/GearSnitch.xcodeproj -target GearSnitch -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build`

## Existing Product-Specific Lessons

- API response shape uses `{ success, data, meta, error }`
- the web app currently stores an access token in local storage but lacks a real auth bootstrap layer
- the iOS app already has native Apple and Google sign-in flows and dedicated network endpoint builders
