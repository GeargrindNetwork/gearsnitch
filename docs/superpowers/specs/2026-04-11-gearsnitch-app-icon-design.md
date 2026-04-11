# GearSnitch App Icon Design

Date: 2026-04-11
Status: Approved for implementation
Scope: iOS app icon only

## Goal

Replace the current iOS app icon with a much simpler mark that matches the existing GearSnitch website and app color system.

The icon should:

- feel simple, crisp, and intentional rather than hand-drawn or custom-lettered
- use the existing dark charcoal background and cyan-to-emerald accent language
- combine the letters `GS` with a clear eye symbol
- read cleanly at App Store and home screen sizes

## Chosen Direction

Selected concept: `B — Iris Ring`

This direction uses a minimal lucide-style eye outline centered on a dark rounded-square icon field, with a clean `GS` placed inside an inner iris ring. The eye shape carries the surveillance / detection idea, while the letters keep the brand name present without trying to be a bespoke monogram.

## Visual System

### Background

- Base background: near-black / charcoal
- Tone target: aligned to the existing website and iOS surface colors
- Suggested range: `#0A0A0C` to `#18181B`
- Background treatment should stay subtle and should not compete with the symbol

### Foreground Mark

- Primary symbol: simple eye outline
- Internal structure: one iris ring inside the eye
- Letter content: `GS` centered inside the iris
- Style target: lucide-like simplicity, smooth stroke geometry, no ornamental detail
- Weight: bold enough to survive small iOS icon outputs

### Accent Color

Use the existing brand accent system already present in the product:

- Cyan endpoint: consistent with the web and iOS cyan accent
- Emerald endpoint: consistent with `Color.gsEmerald`
- Gradient application: across the eye outline and iris ring

The letters should remain high-contrast and legible. They do not need gradient treatment if flat light text reads better at small sizes.

### Depth

- Allow a very subtle glow or lift behind the eye mark
- Do not introduce glossy skeuomorphic effects
- Do not use noise, texture, or extra rings

## Composition Rules

- The icon story is `eye first, GS second`
- The eye should be the clearest shape at a glance
- The iris ring should help anchor the letters, not turn into a badge system
- The `GS` should use clean sans letterforms rather than custom drawn monogram strokes
- The overall mark must stay readable and uncluttered when rasterized at small sizes

## Asset Plan

Implementation should produce:

- one vector master source for the icon artwork
- updated PNG exports for the existing `AppIcon.appiconset` slots
- no expanded scope into launch screen assets during this task

Expected app icon outputs:

- `icon-40.png`
- `icon-58.png`
- `icon-60.png`
- `icon-76.png`
- `icon-80.png`
- `icon-87.png`
- `icon-120.png`
- `icon-152.png`
- `icon-167.png`
- `icon-180.png`
- `icon-1024.png`

Legacy unassigned children such as `icon-20.png` and `icon-29.png` should be removed if they are not referenced by the active asset catalog manifest.

The existing `Contents.json` should only change if required for cleanup or asset assignment consistency.

## Acceptance Criteria

- New icon clearly reflects the selected `B — Iris Ring` direction
- Icon visually matches the current website / app palette
- The eye shape is immediately recognizable
- `GS` remains readable inside the iris at small sizes
- No custom hand-drawn monogram treatment remains
- All required icon sizes are regenerated and wired into the existing asset catalog
- Xcode no longer reports avoidable app icon assignment issues from the updated set

## Out of Scope

- launch screen redesign
- website logo update
- marketing brand system overhaul
- Android icon generation

## Implementation Notes

- Prefer generating the icon from a single high-resolution master and deriving all raster sizes from that source
- Validate small-size legibility explicitly, especially at 40, 58, and 60 pixel outputs
- Preserve the current product’s dark visual language instead of introducing a new palette
- Favor simple stroke geometry over bespoke illustration
