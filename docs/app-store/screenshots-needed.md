# Screenshots — Checklist

Apple requires screenshots for the **largest supported iPhone display size and the largest supported iPad display size** at minimum; other sizes are scaled but you get better conversion if you ship dedicated shots. Minimum 3 per size, maximum 10.

## Required device classes (as of iOS 17/18)

| Size | Resolution (pts/px) | Required | Our plan |
|---|---|---|---|
| iPhone 6.9" (iPhone 15 Pro Max, 16 Pro Max) | 1320×2868 | **Yes — primary** | 8 shots |
| iPhone 6.5" (iPhone 11 Pro Max, XS Max) | 1242×2688 | Scalable from 6.9" | Ship dedicated 5 shots |
| iPhone 6.1" (iPhone 14, 15, 16) | 1179×2556 | Scalable | Ship dedicated 5 shots |
| iPad Pro 13" (M4) | 2064×2752 | **Yes if iPad supported** | 5 shots |
| iPad Pro 11" | 1668×2388 | Scalable from 13" | Ship dedicated 3 shots |

## Shot list (in order of conversion impact)

1. **Dashboard with split heart rate** — two HR streams live, caption: "See both your chest strap and Watch live."
2. **BLE device pairing** — discovery sheet with multiple gear found, caption: "Pair any Bluetooth gear in seconds."
3. **Device detail view** — HR graph, battery, firmware, caption: "Every device, every stat."
4. **Run tracking map** — route drawn, splits panel, caption: "Runs that tell the full story."
5. **Medication / supplement log** — weekly heatmap, caption: "Your private journal. On your device."
6. **Subscription screen** — clean pricing tiers, caption: "Unlock Pro. Cancel anytime."
7. **Apple Watch companion** — side-by-side iPhone + Watch, caption: "Leave your phone in the locker."
8. **Gym geofence** — map with gym pin + auto check-in toast, caption: "Walk in. We start tracking."

## Localization

- English (US) only for launch.
- Add Spanish (Mexico), German, French post-launch per user analytics.

## Copy and overlay guidelines

- Overlay font: San Francisco Pro Display (Apple's own; safe to use in App Store assets).
- Background: dark gradient matching app theme.
- Do NOT include competitor product names or trademarked hardware brand names in screenshots.
- Do NOT show any real user's name, email, HR data — use internal test account "Alex Gear".

## Capture plan

- Use the existing iOS test-automation harness (see `scripts/` in repo — expanded in S9 landing swiper work).
- Run a dedicated "screenshot mode" build flag that seeds demo data and hides version banners.
- Ship to `docs/app-store/screenshots/` once captured (this directory will be created then — not committed in this PR because the assets are binary).

## Preview video (optional but recommended)

- 30 seconds, 1080×1920 portrait.
- H.264, max 500 MB.
- Must use app footage only (no marketing B-roll).
- Caption-safe zone top/bottom.
