---
name: release-build
description: Release build for MKTourApp. Verifies the live API URL in lib/core/constants/api_constants.dart, bumps version/build, creates a signed iOS .xcarchive with the developer/distribution account connected, creates a signed Android .aab, then opens Xcode Organizer on the archive and Finder on the .aab. Use when the user asks to build a release, bump the version or build number, create an archive or .aab, ship/deploy/publish, or upload to TestFlight, App Store, or Play Store.
---

# Release Build (MKTourApp)

Repo root: `/Users/moksha/Moksha/Hamshad/Flutter/MKTourApp`

Run these steps **in order**. Do not parallelise the iOS and Android builds — they have raced each other and produced an empty archive plus a stale `.aab`. iOS first, then Android.

## Phase 1 — Live-API guard (blocking)

```bash
grep -n "socketUrl" lib/core/constants/api_constants.dart
```

The **active** (uncommented) `socketUrl` line must point at the live host `api.mktours.co.uk`.

- If it points at a LAN address (e.g. `192.168.x.x`), or the live line is commented out and the local line is active → **STOP**. Do not build. Tell the user the app is pointed at a local backend, quote the URL you found, and ask whether to switch it to live first.
- Only proceed when the live URL is the active one.

This file is the single source of truth: `baseUrl` and every endpoint below it derive from `socketUrl`, so a local URL silently ships the whole app against a dev backend.

## Phase 2 — Preflight (blocking)

```bash
security find-identity -v -p codesigning
ls -la android/upload-keystore.jks android/key.properties
grep -n "signingConfig\|isMinifyEnabled" android/app/build.gradle.kts
```

Require:

- a valid **`Apple Distribution`** identity (TestFlight/App Store needs Distribution, not just Development)
- both keystore files present
- `signingConfig` wired to the release keystore

If the Distribution identity is missing or the keystore is gone, **STOP** and report — do not produce an unsigned artifact.

## Phase 3 — Bump version

If the user named a version, use it. Otherwise patch-bump (`1.1.5+56` → `1.1.6+57`):

```bash
.opencode/skills/release-build/scripts/bump_version.sh          # auto
.opencode/skills/release-build/scripts/bump_version.sh 1.2.0+57 # explicit
```

The script edits `pubspec.yaml`, deletes `ios/Flutter/Generated.xcconfig`, runs `flutter pub get`, and re-reads the generated config to prove `FLUTTER_BUILD_NAME`/`FLUTTER_BUILD_NUMBER` match. Treat a `FAIL:` line from it as a hard stop.

Deleting `Generated.xcconfig` is mandatory — it is a stale-cache trap that otherwise ships the previous version.

## Phase 4 — iOS archive

```bash
rm -rf ~/Desktop/MKTours.xcarchive
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
  -configuration Release -archivePath ~/Desktop/MKTours.xcarchive \
  clean archive 2>&1 | grep -E "ARCHIVE SUCCEEDED|error:"
```

Require `** ARCHIVE SUCCEEDED **`.

Then **verify the binary really carries the new version** — never trust the build alone:

```bash
/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" \
  ~/Desktop/MKTours.xcarchive/Products/Applications/Runner.app/Info.plist
/usr/libexec/PlistBuddy -c "Print CFBundleVersion" \
  ~/Desktop/MKTours.xcarchive/Products/Applications/Runner.app/Info.plist
```

Must match the version from Phase 3.

If the build reports `The sandbox is not in sync with the Podfile.lock`, run `pod install` in `ios/` (needs a generous timeout — 300s+) and re-run the archive.

## Phase 5 — Android signed .aab

```bash
flutter build appbundle --release 2>&1 | grep -E "Built build|FAILED|error:"
```

Require a `✓ Built build/app/outputs/bundle/release/app-release.aab` line.

```bash
ls -lh build/app/outputs/bundle/release/app-release.aab
```

## Phase 6 — Open both

```bash
open ~/Desktop/MKTours.xcarchive
open build/app/outputs/bundle/release/
```

## Phase 7 — Report

State: version + build, iOS archive path, Android `.aab` path and size, and any warnings that are safe to ignore.

Do **not** commit unless asked. If the user asks to commit, stage only the real changes (`pubspec.yaml`, and `android/*.gradle.kts` when the TikTok deps were re-added) — never `.DS_Store`.

## Known-good build config (already committed — don't re-apply)

These were the TikTok Events SDK build fixes. They are committed, so if a build breaks on repos or R8 missing classes, something reverted them — check `git status` first:

- `android/settings.gradle.kts` — no `dependencyResolutionManagement` block
- `android/build.gradle.kts` — `allprojects` with `google()`, `mavenCentral()`, JitPack
- `android/app/build.gradle.kts` — `com.android.billingclient:billing:8.0.0` (Play requires ≥ 8.0.0) and `com.android.installreferrer:installreferrer:2.2`

## Benign warnings — do not chase

- Kotlin metadata version mismatch (`binary version 2.3.0, expected 2.1.0`)
- Pods deployment-target warnings (9.0 / 11.0 vs supported 12.0+)
- `failed to strip debug symbols from native libraries`
- `CocoaPods did not set the base configuration...`