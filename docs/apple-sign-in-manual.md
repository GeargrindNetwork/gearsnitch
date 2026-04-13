# Apple Sign In Manual

This document is the operational runbook for making Sign in with Apple work in GearSnitch across both the web app and the iOS app.

It covers:
- the Apple Developer objects you must create
- the exact GearSnitch identifiers and URLs in production
- the backend, web, and iOS wiring already present in this repo
- the GCP Secret Manager values the deployment expects
- how to deploy changes safely
- how to verify the flow end to end
- the failure modes that actually broke production

## Current GearSnitch Production Values

These are the current non-secret identifiers and URLs used by the live system:

| Item | Value |
| --- | --- |
| Apple Team ID | `TUZYDM227C` |
| iOS bundle ID | `com.gearsnitch.app` |
| Web Apple Service ID | `com.gearsnitch.web` |
| Apple key ID | `W3U9W98M7Z` |
| Browser redirect URL | `https://gearsnitch.com/sign-in` |
| iOS API base URL | `https://api.gearsnitch.com` |
| Current Cloud Run API URL | `https://gearsnitch-api-6okk4hvbdq-uc.a.run.app` |
| Current Cloud Run realtime URL | `https://gearsnitch-realtime-6okk4hvbdq-uc.a.run.app` |
| Web site origin | `https://gearsnitch.com` |
| Apple web JS SDK | `https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/1/en_US/appleid.auth.js` |
| Apple JWKS endpoint | `https://appleid.apple.com/auth/keys` |
| Apple token exchange endpoint | `https://appleid.apple.com/auth/token` |
| Backend Apple auth endpoint | `POST /api/v1/auth/oauth/apple` |

## Official Apple URLs

Use these Apple pages when setting up or repairing the flow:

- Apple Developer account: `https://developer.apple.com/account/`
- Identifiers: `https://developer.apple.com/account/resources/identifiers/list`
- Keys: `https://developer.apple.com/account/resources/authkeys/list`
- Sign in with Apple environment setup: `https://developer.apple.com/documentation/signinwithapple/configuring-your-environment-for-sign-in-with-apple`
- Sign in with Apple REST token docs: `https://developer.apple.com/documentation/signinwithapplerestapi/generate-and-validate-tokens`
- Apple web JS SDK: `https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/1/en_US/appleid.auth.js`
- Apple token endpoint: `https://appleid.apple.com/auth/token`
- Apple signing keys: `https://appleid.apple.com/auth/keys`

## Architecture Summary

GearSnitch uses one backend endpoint for both Apple sign-in surfaces:

- iOS uses the native `SignInWithAppleButton`, receives `identityToken` and `authorizationCode`, and posts both to the backend.
- Web loads Apple’s browser SDK, launches the Apple popup, receives `id_token` and `code`, and posts both to the same backend endpoint.
- The backend validates the Apple identity token against Apple’s JWKS endpoint.
- If Apple token-exchange credentials are configured, the backend also exchanges the authorization code at Apple’s token endpoint and verifies that returned token too.
- The backend accepts both Apple audiences:
  - `com.gearsnitch.app`
  - `com.gearsnitch.web`
- The backend only provisions brand-new users from iOS. Web sign-in is for an already-created GearSnitch account.

## The Apple Objects You Must Have

You need three Apple-side objects:

1. An App ID for the iOS app.
2. A Services ID for the browser login.
3. A Sign in with Apple key for server-side code exchange.

### 1. iOS App ID

In Apple Developer:

- Open `https://developer.apple.com/account/resources/identifiers/list`
- Find or create an App ID for `com.gearsnitch.app`
- Ensure `Sign in with Apple` is enabled on that App ID

This App ID must match:

- [client-ios/project.yml](/Users/shawn/Documents/GearSnitch/client-ios/project.yml:28)
- [client-ios/GearSnitch/GearSnitch.entitlements](/Users/shawn/Documents/GearSnitch/client-ios/GearSnitch/GearSnitch.entitlements:11)

### 2. Web Services ID

In Apple Developer:

- Open `https://developer.apple.com/account/resources/identifiers/list`
- Create or edit a Services ID
- Set the identifier to `com.gearsnitch.web`
- Enable `Sign in with Apple`
- Under the web configuration, set:
  - Domain: `gearsnitch.com`
  - Return URL: `https://gearsnitch.com/sign-in`

The return URL must match the deployed web build exactly. Apple is strict here. A mismatch in scheme, hostname, or path will break the popup flow.

### 3. Sign in with Apple Key

In Apple Developer:

- Open `https://developer.apple.com/account/resources/authkeys/list`
- Create or locate a key with `Sign in with Apple` enabled
- Associate it with the app that backs GearSnitch login
- Download the `.p8` private key at creation time and store it securely

GearSnitch currently expects:

- Team ID: `TUZYDM227C`
- Key ID: `W3U9W98M7Z`

Do not commit the `.p8` contents into the repo. Store it in GCP Secret Manager as described below.

## Backend Requirements

The backend is the real enforcement point. If the backend is wrong, both web and iOS fail.

Relevant files:

- [api/src/config/index.ts](/Users/shawn/Documents/GearSnitch/api/src/config/index.ts:64)
- [api/src/services/AuthService.ts](/Users/shawn/Documents/GearSnitch/api/src/services/AuthService.ts:483)
- [api/src/modules/auth/routes.ts](/Users/shawn/Documents/GearSnitch/api/src/modules/auth/routes.ts:131)
- [api/.env.example](/Users/shawn/Documents/GearSnitch/api/.env.example:25)

### Required backend env vars

GearSnitch expects these values:

```env
APPLE_CLIENT_IDS=com.gearsnitch.app,com.gearsnitch.web
APPLE_TEAM_ID=TUZYDM227C
APPLE_KEY_ID=W3U9W98M7Z
APPLE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----"
```

Important details:

- `APPLE_CLIENT_IDS` must include both the native app bundle ID and the web Services ID.
- `APPLE_PRIVATE_KEY` may be stored with escaped newlines. The backend normalizes `\\n` into real newlines before signing the client secret.
- If `APPLE_TEAM_ID`, `APPLE_KEY_ID`, or `APPLE_PRIVATE_KEY` are missing, the backend skips authorization-code exchange and only validates the incoming identity token. That is weaker than the intended production setup.

### What the backend does

The Apple sign-in path is:

- `POST /api/v1/auth/oauth/apple`

The request body is:

```json
{
  "identityToken": "jwt-from-apple",
  "authorizationCode": "short-lived-code-from-apple",
  "fullName": "optional full name",
  "givenName": "optional first name",
  "familyName": "optional last name"
}
```

The backend then:

1. Verifies the incoming Apple identity token against `https://appleid.apple.com/auth/keys`
2. Accepts either audience:
   - `com.gearsnitch.app`
   - `com.gearsnitch.web`
3. If exchange credentials are configured, generates a client secret JWT and posts the authorization code to `https://appleid.apple.com/auth/token`
4. Verifies that the token returned by Apple matches the same user
5. Finds the GearSnitch user by `appleId` first, then by `emailHash`
6. Creates a new GearSnitch user only when the sign-in came from iOS
7. Issues the GearSnitch access token and refresh token
8. Sets the refresh token as an `httpOnly`, `secure`, `sameSite=strict` cookie on `/api/v1/auth`

### Important backend behavior

Web account creation is intentionally blocked.

If a user tries Apple login from the browser before the account exists in GearSnitch, the backend returns:

`No GearSnitch account exists for this Apple identity yet. Create it in the iOS app first, then use the same sign-in here.`

That is expected behavior, not a bug.

## GCP Secret Manager Mapping

These secrets are the source of truth for production deployment.

### Backend secrets

| Secret name | Expected value |
| --- | --- |
| `apple-client-id` | `com.gearsnitch.app,com.gearsnitch.web` |
| `apple-team-id` | `TUZYDM227C` |
| `apple-key-id` | `W3U9W98M7Z` |
| `apple-private-key` | Contents of the Apple `.p8` private key |

### Web build secrets

| Secret name | Expected value |
| --- | --- |
| `apple-service-id` | `com.gearsnitch.web` |
| `apple-redirect-uri` | `https://gearsnitch.com/sign-in` |

### Commands to inspect current secret values

```bash
gcloud secrets versions access latest --secret=apple-client-id --project=gearsnitch
gcloud secrets versions access latest --secret=apple-service-id --project=gearsnitch
gcloud secrets versions access latest --secret=apple-redirect-uri --project=gearsnitch
gcloud secrets versions access latest --secret=apple-team-id --project=gearsnitch
gcloud secrets versions access latest --secret=apple-key-id --project=gearsnitch
```

Do not print `apple-private-key` into terminal history unless you explicitly need to inspect it.

## Web App Requirements

Relevant files:

- [web/src/pages/SignInPage.tsx](/Users/shawn/Documents/GearSnitch/web/src/pages/SignInPage.tsx:80)
- [web/src/lib/auth.tsx](/Users/shawn/Documents/GearSnitch/web/src/lib/auth.tsx:41)
- [web/src/lib/api.ts](/Users/shawn/Documents/GearSnitch/web/src/lib/api.ts:4)
- [web/.env.example](/Users/shawn/Documents/GearSnitch/web/.env.example:1)
- [.github/workflows/deploy.yml](/Users/shawn/Documents/GearSnitch/.github/workflows/deploy.yml:29)
- [infrastructure/cloudbuild/cloudbuild.yaml](/Users/shawn/Documents/GearSnitch/infrastructure/cloudbuild/cloudbuild.yaml:15)

### Required build-time env vars

The web bundle needs:

```env
VITE_APPLE_SERVICE_ID=com.gearsnitch.web
VITE_APPLE_REDIRECT_URI=https://gearsnitch.com/sign-in
```

Important details:

- These are Vite variables. They are baked into the built frontend bundle.
- Changing them in Secret Manager does nothing until the web app is rebuilt and redeployed.
- The fallback redirect URI in code is `${window.location.origin}/sign-in`, but production should still set `VITE_APPLE_REDIRECT_URI` explicitly.
- The web app’s API base is also a build-time value. In the current production deploy, the web bundle is built against the active Cloud Run API URL, not the iOS app’s `https://api.gearsnitch.com` custom domain.

### What the web app does

The browser sign-in page:

1. Loads Apple’s JS SDK from `https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/1/en_US/appleid.auth.js`
2. Calls `AppleID.auth.init(...)` with:
   - `clientId = VITE_APPLE_SERVICE_ID`
   - `scope = "name email"`
   - `redirectURI = VITE_APPLE_REDIRECT_URI`
   - `usePopup = true`
3. Calls `AppleID.auth.signIn()`
4. Sends `id_token` and `code` to `POST /auth/oauth/apple`
5. Receives GearSnitch access token + refresh cookie
6. Bootstraps the browser session through:
   - `/auth/refresh`
   - `/auth/me`
7. Redirects the user to `/account` or the requested return path

### Critical web deployment detail

The deploy workflow resolves the web build values from GCP at deploy time:

- `apple-service-id`
- `apple-redirect-uri`

That resolution happens in:

- [.github/workflows/deploy.yml](/Users/shawn/Documents/GearSnitch/.github/workflows/deploy.yml:29)

Those values are passed into Cloud Build as:

- `_VITE_APPLE_SERVICE_ID`
- `_VITE_APPLE_REDIRECT_URI`

That wiring happens in:

- [infrastructure/cloudbuild/cloudbuild.yaml](/Users/shawn/Documents/GearSnitch/infrastructure/cloudbuild/cloudbuild.yaml:15)

If browser Apple login is broken, always verify the actual deployed web build values before blaming the SDK.

## iOS App Requirements

Relevant files:

- [client-ios/project.yml](/Users/shawn/Documents/GearSnitch/client-ios/project.yml:28)
- [client-ios/GearSnitch/GearSnitch.entitlements](/Users/shawn/Documents/GearSnitch/client-ios/GearSnitch/GearSnitch.entitlements:11)
- [client-ios/GearSnitch/Features/Auth/SignInView.swift](/Users/shawn/Documents/GearSnitch/client-ios/GearSnitch/Features/Auth/SignInView.swift:124)
- [client-ios/GearSnitch/Features/Auth/SignInViewModel.swift](/Users/shawn/Documents/GearSnitch/client-ios/GearSnitch/Features/Auth/SignInViewModel.swift:11)
- [client-ios/GearSnitch/Core/Auth/AuthManager.swift](/Users/shawn/Documents/GearSnitch/client-ios/GearSnitch/Core/Auth/AuthManager.swift:79)
- [client-ios/GearSnitch/Core/Network/APIEndpoint.swift](/Users/shawn/Documents/GearSnitch/client-ios/GearSnitch/Core/Network/APIEndpoint.swift:37)
- [client-ios/GearSnitch/Shared/Models/AppConfig.swift](/Users/shawn/Documents/GearSnitch/client-ios/GearSnitch/Shared/Models/AppConfig.swift:12)

### Required iOS app config

The iOS app must keep:

- bundle ID `com.gearsnitch.app`
- development team `TUZYDM227C`
- `Sign in with Apple` entitlement enabled

That is already present in:

- [client-ios/project.yml](/Users/shawn/Documents/GearSnitch/client-ios/project.yml:51)
- [client-ios/GearSnitch/GearSnitch.entitlements](/Users/shawn/Documents/GearSnitch/client-ios/GearSnitch/GearSnitch.entitlements:11)

### What the iOS app does

The native flow is:

1. `SignInWithAppleButton` requests:
   - `.fullName`
   - `.email`
2. Apple returns an `ASAuthorizationAppleIDCredential`
3. The app extracts:
   - `identityToken`
   - `authorizationCode`
   - `fullName`
   - `givenName`
   - `familyName`
4. The app posts them to `/api/v1/auth/oauth/apple`
5. The backend returns GearSnitch access and refresh tokens
6. The app stores the tokens and loads the current profile

Important details:

- Apple only provides name and email on the first authorization. If you do not persist them during the first successful login, they are gone on later logins.
- The iOS app is the only place where a brand-new Apple identity is allowed to create a GearSnitch account.
- The iOS app currently uses `https://api.gearsnitch.com` as the API origin unless overridden in the app bundle.

## End-to-End Setup Process

Follow these steps in order.

### Step 1. Verify Apple Developer configuration

- Confirm the App ID exists for `com.gearsnitch.app`
- Confirm `Sign in with Apple` is enabled for that App ID
- Confirm the Services ID exists for `com.gearsnitch.web`
- Confirm the Services ID web config includes:
  - domain `gearsnitch.com`
  - return URL `https://gearsnitch.com/sign-in`
- Confirm the Apple key still exists and matches:
  - Team ID `TUZYDM227C`
  - Key ID `W3U9W98M7Z`

### Step 2. Verify backend secrets

- Confirm `apple-client-id` contains both values:
  - `com.gearsnitch.app`
  - `com.gearsnitch.web`
- Confirm `apple-team-id`
- Confirm `apple-key-id`
- Confirm `apple-private-key`

If you rotate the Apple key, you must update both:

- `apple-key-id`
- `apple-private-key`

### Step 3. Verify web build secrets

- Confirm `apple-service-id = com.gearsnitch.web`
- Confirm `apple-redirect-uri = https://gearsnitch.com/sign-in`

### Step 4. Verify local repo wiring

Run:

```bash
node scripts/check-launch-config.mjs
```

That script checks the expected Apple env keys and iOS entitlements.

### Step 5. Deploy

Standard deployment uses GitHub Actions on push to `main`.

If you need to run deployment manually, use the same flow the repo uses:

```bash
API_URL="$(gcloud run services describe gearsnitch-api --region=us-central1 --project=gearsnitch --format='value(status.url)')/api/v1"
WS_URL="$(gcloud run services describe gearsnitch-realtime --region=us-central1 --project=gearsnitch --format='value(status.url)')"
APPLE_SERVICE_ID="$(gcloud secrets versions access latest --secret=apple-service-id --project=gearsnitch)"
APPLE_REDIRECT_URI="$(gcloud secrets versions access latest --secret=apple-redirect-uri --project=gearsnitch)"

gcloud builds submit \
  --config=infrastructure/cloudbuild/cloudbuild.yaml \
  --substitutions=_TAG=manual-apple-auth,_REGION=us-central1,_PROJECT_ID=gearsnitch,_VITE_API_URL="${API_URL}",_VITE_WS_URL="${WS_URL}",_VITE_GOOGLE_CLIENT_ID="",_VITE_APPLE_SERVICE_ID="${APPLE_SERVICE_ID}",_VITE_APPLE_REDIRECT_URI="${APPLE_REDIRECT_URI}" \
  --project=gearsnitch
```

### Step 6. Verify iOS first

Use iOS to create or restore the account first.

Checklist:

- install the latest iOS app build
- tap `Continue with Apple`
- confirm the backend returns a successful auth response
- confirm the app loads the authenticated profile
- confirm a brand-new Apple identity can create a GearSnitch account from iOS

### Step 7. Verify web second

After the iOS account exists, verify the browser flow.

Checklist:

- open `https://gearsnitch.com/sign-in`
- click `Continue with Apple`
- complete the Apple popup
- confirm `POST /auth/oauth/apple` returns `200`
- confirm the browser lands on `/account`
- confirm `/auth/refresh` and `/auth/me` succeed
- confirm the session persists on reload

## Quality and Validation Commands

For repo-level validation:

```bash
npm run turbo:quality
npm run turbo:test
npm run turbo:build
```

Focused checks that are especially relevant when touching auth:

```bash
node scripts/check-launch-config.mjs
npm run lint --workspace=api
npm run type-check --workspace=api
npm run build --workspace=api
npm run lint --workspace=web
npm run build --workspace=web
```

## Troubleshooting

### `Invalid Apple identity token`

Usually means one of these is wrong:

- `APPLE_CLIENT_IDS` does not include both `com.gearsnitch.app` and `com.gearsnitch.web`
- the browser Service ID does not match `VITE_APPLE_SERVICE_ID`
- the iOS bundle ID in Apple Developer does not match `com.gearsnitch.app`
- the Apple identity token was minted for a different audience than the backend accepts

### `Apple authorization code exchange failed`

Usually means one of these is wrong:

- `APPLE_TEAM_ID`
- `APPLE_KEY_ID`
- `APPLE_PRIVATE_KEY`
- the backend is using the wrong `client_id` when exchanging the code

### Browser popup succeeds but GearSnitch login still fails

Check:

- `VITE_APPLE_SERVICE_ID`
- `VITE_APPLE_REDIRECT_URI`
- Apple Services ID domain configuration
- whether the frontend was actually rebuilt after changing the secrets

Remember that the web app uses build-time Vite variables, not live runtime evaluation.

### Browser login says the account does not exist

This is expected if the Apple identity has never created a GearSnitch account on iOS.

Create the account in iOS first, then retry the browser flow.

### Session cookie is not sticking in the browser

Check:

- the browser is on HTTPS
- the backend is setting the refresh cookie
- requests include `credentials: "include"`
- the browser is reaching the right API origin

### Name or email is missing after a successful Apple login

Apple only returns name and email on the first authorization. Persist it the first time.

### Web sign-in starts failing with `429` or looks flaky

Two real production issues already caused this:

1. The web app had a `/config/app` request loop in [web/src/lib/release.tsx](/Users/shawn/Documents/GearSnitch/web/src/lib/release.tsx:26), which burned through rate limits before auth completed.
2. The API global rate limiter was created too early and fell back to per-instance memory storage instead of Redis in Cloud Run.

Those were fixed in:

- [web/src/lib/release.tsx](/Users/shawn/Documents/GearSnitch/web/src/lib/release.tsx:26)
- [api/src/middleware/rateLimiter.ts](/Users/shawn/Documents/GearSnitch/api/src/middleware/rateLimiter.ts:6)
- [api/src/app.ts](/Users/shawn/Documents/GearSnitch/api/src/app.ts:14)

If Apple web login starts failing again, check those areas first.

## Repo References

Use these files when making changes:

- Backend config: [api/src/config/index.ts](/Users/shawn/Documents/GearSnitch/api/src/config/index.ts:64)
- Backend Apple auth: [api/src/services/AuthService.ts](/Users/shawn/Documents/GearSnitch/api/src/services/AuthService.ts:483)
- Auth routes: [api/src/modules/auth/routes.ts](/Users/shawn/Documents/GearSnitch/api/src/modules/auth/routes.ts:131)
- API env example: [api/.env.example](/Users/shawn/Documents/GearSnitch/api/.env.example:25)
- Web sign-in page: [web/src/pages/SignInPage.tsx](/Users/shawn/Documents/GearSnitch/web/src/pages/SignInPage.tsx:80)
- Web auth bootstrap: [web/src/lib/auth.tsx](/Users/shawn/Documents/GearSnitch/web/src/lib/auth.tsx:41)
- Web API client: [web/src/lib/api.ts](/Users/shawn/Documents/GearSnitch/web/src/lib/api.ts:4)
- Web env example: [web/.env.example](/Users/shawn/Documents/GearSnitch/web/.env.example:1)
- iOS button: [client-ios/GearSnitch/Features/Auth/SignInView.swift](/Users/shawn/Documents/GearSnitch/client-ios/GearSnitch/Features/Auth/SignInView.swift:124)
- iOS auth manager: [client-ios/GearSnitch/Core/Auth/AuthManager.swift](/Users/shawn/Documents/GearSnitch/client-ios/GearSnitch/Core/Auth/AuthManager.swift:79)
- iOS auth request builder: [client-ios/GearSnitch/Core/Network/APIEndpoint.swift](/Users/shawn/Documents/GearSnitch/client-ios/GearSnitch/Core/Network/APIEndpoint.swift:37)
- iOS project config: [client-ios/project.yml](/Users/shawn/Documents/GearSnitch/client-ios/project.yml:28)
- iOS entitlements: [client-ios/GearSnitch/GearSnitch.entitlements](/Users/shawn/Documents/GearSnitch/client-ios/GearSnitch/GearSnitch.entitlements:11)
- Launch preflight: [scripts/check-launch-config.mjs](/Users/shawn/Documents/GearSnitch/scripts/check-launch-config.mjs:1)
- Deploy workflow: [.github/workflows/deploy.yml](/Users/shawn/Documents/GearSnitch/.github/workflows/deploy.yml:29)
- Cloud Build: [infrastructure/cloudbuild/cloudbuild.yaml](/Users/shawn/Documents/GearSnitch/infrastructure/cloudbuild/cloudbuild.yaml:15)
