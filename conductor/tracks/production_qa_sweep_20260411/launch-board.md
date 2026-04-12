# Launch Board

This board is the operational tracker for the remaining production integration work after repo completion.

## Status Legend

- `NOT_STARTED` — no provider setup or live verification has happened yet
- `IN_PROGRESS` — provider setup or env injection has started
- `BLOCKED_EXTERNAL` — waiting on Apple, Google, Stripe, certs, or portal access
- `READY_FOR_QA` — setup is complete and waiting on live verification
- `DONE` — configured and verified in the target environment

## Workstreams

| Workstream | Status | Suggested owner | Depends on | Primary touchpoints | Exit criteria |
|------------|--------|-----------------|------------|---------------------|---------------|
| Google OAuth | `NOT_STARTED` | Auth / Platform | Google Cloud Console access | [web/.env.example](/Users/shawn/Documents/GearSnitch/web/.env.example:3), [api/.env.example](/Users/shawn/Documents/GearSnitch/api/.env.example:19), [GoogleSignInManager.swift](/Users/shawn/Documents/GearSnitch/client-ios/GearSnitch/Core/Auth/GoogleSignInManager.swift:24) | Web and iOS Google sign-in succeed against production backend |
| Apple Sign-In | `NOT_STARTED` | iOS / Auth | Apple Developer access | [web/.env.example](/Users/shawn/Documents/GearSnitch/web/.env.example:4), [api/.env.example](/Users/shawn/Documents/GearSnitch/api/.env.example:23), [GearSnitch.entitlements](/Users/shawn/Documents/GearSnitch/client-ios/GearSnitch/GearSnitch.entitlements:9) | Web and iOS Apple sign-in succeed and API `/auth/oauth/apple` issues tokens |
| APNs Push Delivery | `NOT_STARTED` | iOS / Platform | Apple Developer access, push key | [api/.env.example](/Users/shawn/Documents/GearSnitch/api/.env.example:33), [GearSnitch.entitlements](/Users/shawn/Documents/GearSnitch/client-ios/GearSnitch/GearSnitch.entitlements:5), [NotificationPermissionManager.swift](/Users/shawn/Documents/GearSnitch/client-ios/GearSnitch/Core/Notifications/NotificationPermissionManager.swift:90) | Physical device registers token and receives a test notification |
| Stripe Web Checkout | `NOT_STARTED` | Payments / Backend | Stripe live credentials, webhook endpoint access | [StripeCheckout.tsx](/Users/shawn/Documents/GearSnitch/web/src/components/checkout/StripeCheckout.tsx:17), [api/.env.example](/Users/shawn/Documents/GearSnitch/api/.env.example:28), [PaymentService.ts](/Users/shawn/Documents/GearSnitch/api/src/services/PaymentService.ts:12) | Live card checkout succeeds and webhook processing updates backend state |
| Apple Pay | `NOT_STARTED` | iOS / Payments | Apple merchant setup, Stripe live config | [ApplePayManager.swift](/Users/shawn/Documents/GearSnitch/client-ios/GearSnitch/Core/Payments/ApplePayManager.swift:16), [paymentRoutes.ts](/Users/shawn/Documents/GearSnitch/api/src/modules/store/paymentRoutes.ts:79) | Apple Pay succeeds on a supported real device |
| Final Real-Device QA | `NOT_STARTED` | QA / Release | All workstreams above at `READY_FOR_QA` | [qa-report.md](/Users/shawn/Documents/GearSnitch/conductor/tracks/production_qa_sweep_20260411/qa-report.md:1), [launch-checklist.md](/Users/shawn/Documents/GearSnitch/conductor/tracks/production_qa_sweep_20260411/launch-checklist.md:1) | Sign-in, push, payments, and GPS run capture all pass in target environment |

## Sequencing

1. Run `npm run launch:check` to verify repo-side launch wiring.
2. Complete Google OAuth web and iOS credentials.
3. Complete Apple Sign-In identifiers and portal setup.
4. Provision APNs and verify device token registration.
5. Enable Stripe live checkout and webhook delivery.
6. Enable Apple Pay merchant setup and verify on device.
7. Run final real-device QA sweep.

## Active Checkpoints

### Google OAuth

- Provider setup:
  - Create or confirm browser client ID for the production web domain.
  - Create or confirm iOS client ID for the `gearsnitch://oauth/google/callback` flow.
- App config:
  - Set `VITE_GOOGLE_CLIENT_ID`.
  - Set `GOOGLE_OAUTH_CLIENT_ID` and `GOOGLE_OAUTH_CLIENT_SECRET`.
  - Inject `GS_GOOGLE_CLIENT_ID` into the iOS app config consumed by `GoogleSignInManager`.
- QA gate:
  - Web sign-in succeeds on `/sign-in`.
  - iOS sign-in succeeds on a real device.

### Apple Sign-In

- Provider setup:
  - Confirm Apple service/app identifiers match backend and web config.
  - Confirm redirect URI for the production web sign-in flow.
- App config:
  - Set `VITE_APPLE_SERVICE_ID` and `VITE_APPLE_REDIRECT_URI`.
  - Set `APPLE_CLIENT_ID`, `APPLE_TEAM_ID`, `APPLE_KEY_ID`, and `APPLE_PRIVATE_KEY`.
- QA gate:
  - Web Apple sign-in completes successfully.
  - iOS Apple sign-in completes successfully.

### APNs Push Delivery

- Provider setup:
  - Create or confirm APNs key for the production app.
  - Confirm provisioning profile and signing path use the correct push entitlement.
- App config:
  - Set `APNS_KEY`, `APNS_KEY_ID`, and `APNS_TEAM_ID`.
- QA gate:
  - Device token reaches backend registration.
  - Notification delivery succeeds on a physical device.

### Stripe Web Checkout

- Provider setup:
  - Load live Stripe secret, publishable, and webhook secrets.
  - Point Stripe webhook delivery at the deployed API endpoint.
- App config:
  - Set `VITE_STRIPE_PUBLISHABLE_KEY`.
  - Set `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, and `STRIPE_PUBLISHABLE_KEY`.
- QA gate:
  - Browser checkout succeeds.
  - Webhook event is received and processed.

### Apple Pay

- Provider setup:
  - Confirm merchant ID `merchant.com.gearsnitch.app`.
  - Complete merchant certificate and payment processor setup.
- QA gate:
  - Apple Pay sheet appears on supported hardware.
  - Backend confirmation succeeds and order state updates.

### Final Real-Device QA

- Validate:
  - Web Google sign-in
  - Web Apple sign-in
  - iOS Google sign-in
  - iOS Apple sign-in
  - Push token registration and delivery
  - Stripe checkout and webhook confirmation
  - Apple Pay checkout
  - GPS route capture

## Completion Rule

Move the board to fully complete only when every workstream is `DONE` and the final real-device QA sweep has passed.
