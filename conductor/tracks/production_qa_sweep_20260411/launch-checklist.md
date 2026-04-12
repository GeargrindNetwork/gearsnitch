# Launch Integration Checklist

This checklist covers the remaining work required to move GearSnitch from repo-complete to production-integrated.

## Current State

- Code integration is complete across `api`, `web`, `client-ios`, `worker`, and `realtime`.
- Repo wiring can now be checked with `npm run launch:check`.
- Automated validation already passed:
  - `npm run build`
  - `npm run lint`
  - `npm run type-check`
  - `npm run test`
  - `xcodebuild -project client-ios/GearSnitch.xcodeproj -target GearSnitch -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build`
- Remaining work is external configuration, credentials, and live-environment verification.

## 1. Google OAuth

Status: code-wired, provider setup still required.

Web configuration:
- Set `VITE_GOOGLE_CLIENT_ID` in [web/.env.example](/Users/shawn/Documents/GearSnitch/web/.env.example:3) for the browser sign-in flow in [SignInPage.tsx](/Users/shawn/Documents/GearSnitch/web/src/pages/SignInPage.tsx:70).

API configuration:
- Set `GOOGLE_OAUTH_CLIENT_ID` and `GOOGLE_OAUTH_CLIENT_SECRET` in [api/.env.example](/Users/shawn/Documents/GearSnitch/api/.env.example:19).
- Confirm the backend is validating tokens through [AuthService.ts](/Users/shawn/Documents/GearSnitch/api/src/services/AuthService.ts:394) and receiving them through [routes.ts](/Users/shawn/Documents/GearSnitch/api/src/modules/auth/routes.ts:82).

iOS configuration:
- Set `GS_GOOGLE_CLIENT_ID` in the app Info.plist consumed by [GoogleSignInManager.swift](/Users/shawn/Documents/GearSnitch/client-ios/GearSnitch/Core/Auth/GoogleSignInManager.swift:24).
- Confirm Google Cloud Console allows the redirect URI `gearsnitch://oauth/google/callback`.
- Confirm the app URL scheme `gearsnitch` remains present in [Info.plist](/Users/shawn/Documents/GearSnitch/client-ios/GearSnitch/Resources/Info.plist:21).

Verification:
- Browser sign-in succeeds on `/sign-in`.
- iOS sign-in returns an ID token and API login succeeds.
- API `/auth/oauth/google` issues access and refresh tokens.

## 2. Apple Sign-In

Status: code-wired, Apple portal setup still required.

Web configuration:
- Set `VITE_APPLE_SERVICE_ID` and `VITE_APPLE_REDIRECT_URI` in [web/.env.example](/Users/shawn/Documents/GearSnitch/web/.env.example:4).
- Confirm the configured redirect URI matches the web flow in [SignInPage.tsx](/Users/shawn/Documents/GearSnitch/web/src/pages/SignInPage.tsx:184).

API configuration:
- Set `APPLE_CLIENT_ID`, `APPLE_TEAM_ID`, `APPLE_KEY_ID`, and `APPLE_PRIVATE_KEY` in [api/.env.example](/Users/shawn/Documents/GearSnitch/api/.env.example:23).
- Confirm the backend Apple token validation path in [AuthService.ts](/Users/shawn/Documents/GearSnitch/api/src/services/AuthService.ts:423) matches the service/app identifiers registered in Apple Developer.

iOS configuration:
- Confirm the main app bundle identifier is `com.gearsnitch.app` in [project.pbxproj](/Users/shawn/Documents/GearSnitch/client-ios/GearSnitch.xcodeproj/project.pbxproj:1197).
- Confirm Sign in with Apple entitlement is present in [GearSnitch.entitlements](/Users/shawn/Documents/GearSnitch/client-ios/GearSnitch/GearSnitch.entitlements:9).
- Verify the service ID / app ID pair in Apple Developer matches the identifiers used by API and web.

Verification:
- Browser Apple sign-in returns to `/sign-in` successfully.
- iOS Apple sign-in succeeds from the native button.
- API `/auth/oauth/apple` creates or links the user and issues tokens.

## 3. APNs Push Delivery

Status: app capability present, live push delivery still blocked on Apple credentials.

Configuration:
- Set `APNS_KEY`, `APNS_KEY_ID`, and `APNS_TEAM_ID` in [api/.env.example](/Users/shawn/Documents/GearSnitch/api/.env.example:32).
- Confirm the app carries `aps-environment` in [GearSnitch.entitlements](/Users/shawn/Documents/GearSnitch/client-ios/GearSnitch/GearSnitch.entitlements:5).
- Confirm device registration reaches the API notification registration route in [routes.ts](/Users/shawn/Documents/GearSnitch/api/src/modules/notifications/routes.ts:331).

iOS checks:
- AppDelegate receives an APNs token in [AppDelegate.swift](/Users/shawn/Documents/GearSnitch/client-ios/GearSnitch/App/AppDelegate.swift:28).
- Notification permission and token handling run through [NotificationPermissionManager.swift](/Users/shawn/Documents/GearSnitch/client-ios/GearSnitch/Core/Notifications/NotificationPermissionManager.swift:90).

Verification:
- A physical device obtains an APNs token.
- The token is registered against the authenticated user.
- A test notification reaches the device end-to-end.

## 4. Stripe And Apple Pay

Status: checkout code is present; live credentials and webhook validation still required.

Web configuration:
- Set `VITE_STRIPE_PUBLISHABLE_KEY` for [StripeCheckout.tsx](/Users/shawn/Documents/GearSnitch/web/src/components/checkout/StripeCheckout.tsx:17).

API configuration:
- Set `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, and `STRIPE_PUBLISHABLE_KEY` in [api/.env.example](/Users/shawn/Documents/GearSnitch/api/.env.example:28).
- Confirm Stripe server integration in [PaymentService.ts](/Users/shawn/Documents/GearSnitch/api/src/services/PaymentService.ts:12).
- Confirm raw-body webhook handling remains mounted before JSON parsing in [app.ts](/Users/shawn/Documents/GearSnitch/api/src/app.ts:52).
- Confirm webhook endpoint `/api/v1/store/payments/webhook` is reachable and signed correctly through [paymentRoutes.ts](/Users/shawn/Documents/GearSnitch/api/src/modules/store/paymentRoutes.ts:128).

Apple Pay configuration:
- Confirm the merchant ID `merchant.com.gearsnitch.app` used in [ApplePayManager.swift](/Users/shawn/Documents/GearSnitch/client-ios/GearSnitch/Core/Payments/ApplePayManager.swift:16) exists in Apple Developer.
- Confirm the merchant certificate and domain associations are complete for the target environment.

Verification:
- Browser card checkout succeeds against live Stripe.
- Stripe webhook delivery is verified and order/subscription state updates correctly.
- Apple Pay succeeds on a real supported device.

## 5. Final Go-Live Verification

Run this after all provider setup is complete:

1. Run `npm run launch:check` to confirm the repo-side launch wiring is still intact.
2. Web Google sign-in on the production domain.
3. Web Apple sign-in on the production domain.
4. iOS Google sign-in on a real device.
5. iOS Apple sign-in on a real device.
6. Notification registration and delivery on a real device.
7. Browser Stripe checkout and webhook confirmation.
8. iOS Apple Pay checkout on a real device.
9. GPS run capture on a real device.

## Completion Rule

GearSnitch is fully production-integrated only when every item above is configured and all final go-live verification steps pass in the target environment.
