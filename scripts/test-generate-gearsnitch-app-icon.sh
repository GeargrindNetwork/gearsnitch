#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift scripts/generate-gearsnitch-app-icon.swift

expect_size() {
  local file="$1"
  local expected="$2"
  local actual
  actual="$(sips -g pixelWidth -g pixelHeight "$file" | awk '/pixelWidth:/{w=$2} /pixelHeight:/{h=$2} END{print w"x"h}')"

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
