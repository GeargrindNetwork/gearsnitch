# GearSnitch App Icon Design

Date: 2026-04-11
Status: Approved for implementation
Scope: iOS app icon only

## Goal

Replace the current iOS app icon with a monogram that matches the existing GearSnitch website and app color system.

The icon should:

- feel premium and restrained rather than playful or aggressive
- use the existing dark charcoal background and cyan-to-emerald accent language
- read clearly at App Store and home screen sizes
- avoid extra symbolism such as the previously discussed eye motif

## Chosen Direction

Selected concept: `A — Luxe Monogram`

This direction uses a pure `GS` monogram centered on a dark rounded-square icon field. The letterforms are wide, smooth, and calm. The mark should communicate a polished, product-grade identity rather than a fitness badge, gamer emblem, or surveillance logo.

## Visual System

### Background

- Base background: near-black / charcoal
- Tone target: aligned to the existing website and iOS surface colors
- Suggested range: `#0A0A0C` to `#18181B`
- Background treatment should stay subtle and not compete with the letters

### Foreground Mark

- Monogram: `GS`
- Style: geometric but not rigid, with rounded or softened transitions
- Weight: bold enough to survive 20x20 icon usage
- Composition: centered and optically balanced
- No outlines, no badge ring, no eye symbol, no small detail work

### Accent Color

Use the existing brand accent system already present in the product:

- Cyan endpoint: consistent with the web and iOS cyan accent
- Emerald endpoint: consistent with `Color.gsEmerald`
- Gradient direction: cyan to emerald across the monogram

The gradient should add brand recognition without reducing legibility.

### Depth

- Allow a very subtle glow, highlight, or contrast lift behind the mark
- Do not introduce glossy skeuomorphic effects
- Do not use noisy textures

## Composition Rules

- The monogram is the entire icon story
- The `G` and `S` should feel designed as one mark, not like two default letters placed next to each other
- Negative space must stay open enough that the letters are still readable when rasterized at small sizes
- The icon must still work when viewed quickly in the iOS grid

## Asset Plan

Implementation should produce:

- one vector master source for the icon artwork
- updated PNG exports for the existing `AppIcon.appiconset` slots
- no expanded scope into launch screen assets during this task

Expected app icon outputs:

- `icon-20.png`
- `icon-29.png`
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

The existing `Contents.json` should only change if required for cleanup or asset assignment consistency.

## Acceptance Criteria

- New icon clearly reflects the selected `A — Luxe Monogram` direction
- Icon visually matches the current website / app palette
- `GS` is readable at small sizes
- No eye motif or extra symbol remains
- All required icon sizes are regenerated and wired into the existing asset catalog
- Xcode no longer reports avoidable app icon assignment issues from the updated set

## Out of Scope

- launch screen redesign
- website logo update
- marketing brand system overhaul
- Android icon generation

## Implementation Notes

- Prefer generating the icon from a single high-resolution master and deriving all raster sizes from that source
- Validate small-size legibility explicitly, especially at 20, 29, and 40 point outputs
- Preserve the current product’s dark visual language instead of introducing a new palette
