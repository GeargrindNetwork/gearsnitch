# Device Pairing Architecture

## Current flow

GearSnitch now uses one iOS pairing flow for both onboarding and the device-management sheet:

1. `DevicePairingFlowView` starts BLE discovery through `BLEManager`.
2. The user taps `Pair` on a discovered tracker.
3. The app connects over CoreBluetooth and stops discovery once the device is connected.
4. The user explicitly saves the device to their account, with:
   - optional nickname
   - optional `Pin this device` toggle
5. iOS calls `POST /api/v1/devices`.
6. The API stores the device in MongoDB and returns the saved device contract.
7. iOS refreshes `/api/v1/devices` and updates `BLEManager` metadata so pinned state and nickname stay in sync.
8. On onboarding, a successful save advances to the next step. In device management, a successful save dismisses the sheet.

## BLE scan behavior

### Discovery flow

Onboarding and manual pairing now use `BLEManager.startScanning(mode: .discovery)`.

- Duplicate advertisements: disabled
- Scan timeout: `AppConfig.bleScanTimeout` = `30s`
- Stale device prune loop: every `5s`
- Stale device eviction: `BLEScanner.staleDeviceTimeout` = `30s`
- Minimum RSSI: `BLEScanner.minimumRSSI` = `-80`
- Non-connectable peripherals: filtered out

### Gym monitoring flow

Active gym sessions still use `BLEManager.startScanning()` which defaults to `.monitoring`.

- Duplicate advertisements: enabled
- No automatic timeout
- Same `5s` stale prune loop
- Same `30s` stale device eviction

## Why discovery still shows generic Bluetooth devices

The app only narrows discovery to specific tracker hardware when `GS_BLE_SERVICE_UUIDS` is configured in `client-ios/GearSnitch/Resources/Info.plist`.

Right now that allowlist is not configured, so discovery falls back to generic BLE scanning and can still show nearby named, connectable peripherals. The code now suppresses some noise by rejecting non-connectable advertisements, but a true tracker-only list still requires one of:

- a service UUID allowlist
- a manufacturer-data allowlist
- another explicit hardware fingerprint for supported trackers

This is an architecture/configuration gap, not just a UI bug.

## Account persistence model

Devices are stored in MongoDB through `api/src/models/Device.ts`.

Important fields:

- `identifier`: persisted as the device Bluetooth identifier
- `nickname`: optional user-facing label
- `isFavorite`: backend field currently used as the account-level pinned-device flag
- `monitoringEnabled`
- `status`
- `lastSeenAt`

`GET /users/me` projects device state into the web account profile and exposes:

- `devices[]`
- `pinnedDeviceId`

The canonical account-facing device contract is now:

- `_id`
- `name`
- `nickname`
- `type`
- `bluetoothIdentifier`
- `status`
- `isFavorite`
- `isMonitoring`
- `lastSeenAt`
- `createdAt`

The web account page is currently a read-only surface for device state. Pairing and pinning are managed in the iOS app, then reflected into the web account view from the server response.

## Pinning semantics

The user-facing concept is now **Pinned Device**.

The backend field remains `isFavorite` for compatibility, but the logic now treats it as the single pinned tracker for the account.

Write rules:

- `POST /api/v1/devices` accepts `nickname` and `isFavorite`
- `PATCH /api/v1/devices/:id` accepts `nickname` and `isFavorite`
- when a device is pinned, the API clears `isFavorite` on the user's other devices

This closes the earlier inconsistency where multiple devices could be marked favorite while `/users/me` exposed only one `pinnedDeviceId`.

## Integration status

### iOS

- Onboarding pairing and device-management pairing now share the same save/pin flow
- Pairing no longer auto-registers and auto-advances without user confirmation
- Device metadata refreshes after save so BLE labels and pin state stay aligned with the account

### API

- Device create/update contracts now accept nickname and pin state
- Pinned-device enforcement is centralized in `DeviceService`
- Shared contract drift was corrected for `name`, `type`, `bluetoothIdentifier`, `nickname`, `isFavorite`, `isMonitoring`, and `lastSeenAt`
- Device registration failures now emit structured server logs with request correlation data and the sanitized create payload fields needed to debug real `500` responses

### Web

- The account page now reads the same canonical device fields returned by `/devices` and `/users/me`
- Web remains display-only for device state
- Copy now explicitly states that pairing and pinning happen in the iOS app and sync into the account page

## Remaining architectural work

The pairing/save flow is now coherent, but two larger items remain if GearSnitch needs production-grade tracker discovery:

1. Define supported tracker fingerprints.
   Without a service UUID or manufacturer allowlist, the app cannot reliably hide unrelated Bluetooth peripherals.

2. Decide whether the web account surface should stay read-only or gain pin-management controls.
   The current architecture treats iOS as the source of truth for pairing and pinning, with web as a synced account view only.
