# GearSnitch App Icon Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate and install the approved `B — Iris Ring` `eye + GS` app icon for the iOS app, with a deterministic source-of-truth asset and regenerated AppIcon catalog outputs.

**Architecture:** Build the icon from a local generator script instead of hand-editing raster files. The generator will produce a master vector/PDF artifact plus a 1024px raster, then derive the required iOS app icon sizes and refresh `AppIcon.appiconset` so the catalog stays maintainable and reproducible. The drawing should use a simple lucide-style eye outline, an inner iris ring, and centered `GS` text rather than a custom monogram.

**Tech Stack:** Swift CLI (`swift` + AppKit/CoreGraphics), macOS `sips`, Xcode asset catalog (`.xcassets`), `xcodebuild`

---

## File Structure

- Create: `scripts/test-generate-gearsnitch-app-icon.sh`
  - Shell verification harness that runs the generator and asserts all required icon outputs exist with the expected pixel dimensions.
- Create: `scripts/generate-gearsnitch-app-icon.swift`
  - Deterministic generator that draws the approved `eye + GS` mark, writes the master PDF, writes the 1024px PNG, and derives the remaining AppIcon outputs.
- Create: `client-ios/GearSnitch/Resources/AppIconSources/`
  - Source-of-truth directory for generated master artwork.
- Create: `client-ios/GearSnitch/Resources/AppIconSources/gs-eye-iris-master.pdf`
  - Generated vector master for future regeneration and reuse.
- Modify: `client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-40.png`
- Modify: `client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-58.png`
- Modify: `client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-60.png`
- Modify: `client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-76.png`
- Modify: `client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-80.png`
- Modify: `client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-87.png`
- Modify: `client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-120.png`
- Modify: `client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-152.png`
- Modify: `client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-167.png`
- Modify: `client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-180.png`
- Modify: `client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png`
- Delete: `client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-20.png`
- Delete: `client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-29.png`
- Modify only if needed: `client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`
  - Keep the asset catalog references aligned with the generated files and remove any avoidable stale-child warnings.

## Chunk 1: Generator and Source Asset

### Task 1: Add the failing verification harness

**Files:**
- Create: `scripts/test-generate-gearsnitch-app-icon.sh`
- Reference: `docs/superpowers/specs/2026-04-11-gearsnitch-app-icon-design.md`

- [ ] **Step 1: Write the failing verification script**

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift scripts/generate-gearsnitch-app-icon.swift

expect_size() {
  local file="$1"
  local expected="$2"
  local actual
  actual="$(sips -g pixelWidth -g pixelHeight "$file" | awk '/pixelWidth:/{w=$2} /pixelHeight:/{h=$2} END{print w\"x\"h}')"
  if [[ "$actual" != "${expected}x${expected}" ]]; then
    echo "Expected $file to be ${expected}x${expected}, got $actual" >&2
    exit 1
  fi
}

assert_missing() {
  local file="$1"
  if [[ -e "$file" ]]; then
    echo "Expected stale file to be removed: $file" >&2
    exit 1
  fi
}

test -f client-ios/GearSnitch/Resources/AppIconSources/gs-eye-iris-master.pdf
expect_size client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-40.png 40
expect_size client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-58.png 58
expect_size client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-60.png 60
expect_size client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-76.png 76
expect_size client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-80.png 80
expect_size client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-87.png 87
expect_size client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-120.png 120
expect_size client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-152.png 152
expect_size client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-167.png 167
expect_size client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-180.png 180
expect_size client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png 1024

assert_missing client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-20.png
assert_missing client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-29.png
```

- [ ] **Step 2: Run the harness to verify it fails before implementation**

Run:

```bash
bash scripts/test-generate-gearsnitch-app-icon.sh
```

Expected:

```text
<unknown>:0: error: error opening input file 'scripts/generate-gearsnitch-app-icon.swift' (No such file or directory)
```

- [ ] **Step 3: Commit the failing harness**

```bash
git add scripts/test-generate-gearsnitch-app-icon.sh
git commit -m "test: add app icon generation harness"
```

### Task 2: Implement the icon generator

**Files:**
- Create: `scripts/generate-gearsnitch-app-icon.swift`
- Create: `client-ios/GearSnitch/Resources/AppIconSources/gs-eye-iris-master.pdf`
- Modify: `client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png`

- [ ] **Step 1: Create the generator script skeleton**

```swift
import AppKit
import CoreGraphics
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourcesDir = root.appendingPathComponent("client-ios/GearSnitch/Resources/AppIconSources", isDirectory: true)
let iconSetDir = root.appendingPathComponent("client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

let backgroundStart = NSColor(calibratedRed: 10.0 / 255.0, green: 10.0 / 255.0, blue: 12.0 / 255.0, alpha: 1)
let backgroundEnd = NSColor(calibratedRed: 24.0 / 255.0, green: 24.0 / 255.0, blue: 27.0 / 255.0, alpha: 1)
let cyan = NSColor(calibratedRed: 34.0 / 255.0, green: 211.0 / 255.0, blue: 238.0 / 255.0, alpha: 1)
let emerald = NSColor(calibratedRed: 16.0 / 255.0, green: 185.0 / 255.0, blue: 129.0 / 255.0, alpha: 1)
```

- [ ] **Step 2: Implement drawing for the approved eye mark**

Use a single 1024x1024 artboard and draw:

```swift
func drawIcon(in rect: CGRect, context: CGContext) {
    let rounded = CGPath(roundedRect: rect.insetBy(dx: 56, dy: 56), cornerWidth: 235, cornerHeight: 235, transform: nil)
    context.addPath(rounded)
    context.clip()

    let bgColors = [backgroundStart.cgColor, backgroundEnd.cgColor] as CFArray
    let bgGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bgColors, locations: [0, 1])!
    context.drawLinearGradient(bgGradient, start: CGPoint(x: rect.minX, y: rect.minY), end: CGPoint(x: rect.maxX, y: rect.maxY), options: [])

    // Add subtle vignette / glow behind the mark.
    // Draw a simple lucide-style eye outline with an iris ring.
    // Center clean GS lettering inside the iris and keep the letters high-contrast.
}
```

Implementation rules:

- keep the eye shape centered and immediately legible
- keep the `GS` centered inside the iris ring
- avoid custom hand-drawn lettering or decorative detail
- keep the background treatment subtle

- [ ] **Step 3: Write the master PDF and the 1024px PNG**

The script should write:

```text
client-ios/GearSnitch/Resources/AppIconSources/gs-eye-iris-master.pdf
client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png
```

- [ ] **Step 4: Run the harness and verify the generator now passes its source/master checks**

Run:

```bash
bash scripts/test-generate-gearsnitch-app-icon.sh
```

Expected:

```text
Expected stale file to be removed: client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-20.png
```

The harness should now fail only because the stale legacy files still exist and catalog refresh is not complete yet.

- [ ] **Step 5: Commit the generator**

```bash
git add scripts/generate-gearsnitch-app-icon.swift client-ios/GearSnitch/Resources/AppIconSources/gs-eye-iris-master.pdf client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png
git commit -m "feat: generate gearsnitch app icon master"
```

## Chunk 2: AppIcon Catalog Refresh and Verification

### Task 3: Regenerate the iOS AppIcon catalog from the master artwork

**Files:**
- Modify: `scripts/generate-gearsnitch-app-icon.swift`
- Modify: `client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-40.png`
- Modify: `client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-58.png`
- Modify: `client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-60.png`
- Modify: `client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-76.png`
- Modify: `client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-80.png`
- Modify: `client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-87.png`
- Modify: `client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-120.png`
- Modify: `client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-152.png`
- Modify: `client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-167.png`
- Modify: `client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-180.png`
- Delete: `client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-20.png`
- Delete: `client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-29.png`
- Modify only if needed: `client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`

- [ ] **Step 1: Extend the generator to export all required icon sizes**

In the Swift script, add a size map and call `sips` against the generated 1024 PNG:

```swift
let outputSizes = [40, 58, 60, 76, 80, 87, 120, 152, 167, 180, 1024]

for size in outputSizes where size != 1024 {
    let output = iconSetDir.appendingPathComponent("icon-\(size).png")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    process.arguments = [
        "-z", "\(size)", "\(size)",
        iconSetDir.appendingPathComponent("icon-1024.png").path,
        "--out", output.path
    ]
    try process.run()
    process.waitUntilExit()
    precondition(process.terminationStatus == 0, "sips failed for \(size)")
}
```

- [ ] **Step 2: Delete the stale unassigned icon files**

Run:

```bash
rm -f client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-20.png
rm -f client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-29.png
```

Expected:

```text
# no output
```

- [ ] **Step 3: Keep the asset catalog manifest consistent**

Check:

```bash
sed -n '1,220p' client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json
```

If the manifest still matches the generated files, leave it unchanged. Only edit it if the regenerated file set requires cleanup for Xcode consistency.

- [ ] **Step 4: Run the full harness and verify all icon outputs pass**

Run:

```bash
bash scripts/test-generate-gearsnitch-app-icon.sh
```

Expected:

```text
# no output
```

- [ ] **Step 5: Commit the refreshed asset catalog**

```bash
git add scripts/generate-gearsnitch-app-icon.swift client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset client-ios/GearSnitch/Resources/AppIconSources/gs-eye-iris-master.pdf
git commit -m "feat: refresh ios app icon assets"
```

### Task 4: Verify the icon in the iOS build pipeline

**Files:**
- No new files expected unless build output reveals a manifest problem requiring `Contents.json` cleanup

- [ ] **Step 1: Run the iOS build verification**

Run:

```bash
xcodebuild -project client-ios/GearSnitch.xcodeproj -target GearSnitch -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
```

Expected:

```text
** BUILD SUCCEEDED **
```

Also verify the build log no longer reports avoidable `AppIcon` child-assignment warnings.

- [ ] **Step 2: Spot-check the smallest icon sizes for legibility**

Run:

```bash
sips -g pixelWidth -g pixelHeight client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-40.png
sips -g pixelWidth -g pixelHeight client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-58.png
sips -g pixelWidth -g pixelHeight client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/icon-60.png
```

Expected:

```text
pixelWidth: 40
pixelHeight: 40
...
```

Then visually inspect `icon-40.png` and `icon-58.png` to confirm the `GS` remains readable and not muddy.

- [ ] **Step 3: Commit any final catalog cleanup required by verification**

```bash
git add client-ios/GearSnitch/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json
git commit -m "chore: finalize app icon catalog cleanup"
```

Only do this commit if verification required a final manifest adjustment. Otherwise skip it.
