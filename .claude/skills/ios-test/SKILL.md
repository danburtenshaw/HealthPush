---
name: ios-test
description: Run the HealthPush iOS test suite against the iPhone 16 simulator. Regenerates the Xcode project first to avoid stale xcodeproj drift, then runs the HealthPush scheme's tests. Use when the user says "run the tests", "test the iOS app", or after making Swift changes.
---

# iOS Test Runner

Runs the full HealthPush iOS test suite from a clean Xcode project state.

## The command

```bash
cd ios/HealthPush && xcodegen && xcodebuild test \
  -project HealthPush.xcodeproj \
  -scheme HealthPush \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -quiet
```

## Why each piece

- **`xcodegen`** — `project.yml` is the source of truth. `HealthPush.xcodeproj` is gitignored and can go stale between sessions, especially after adding/removing source files. Running xcodegen first guarantees the project file matches the intended configuration.
- **`-scheme HealthPush`** — matches the single scheme declared in `project.yml`, which runs the `HealthPushTests` target.
- **`-destination '...iPhone 16'`** — any iOS 17+ simulator works, but iPhone 16 matches `.github/workflows/ios-ci.yml`, so local results mirror CI.
- **`-quiet`** — suppresses per-file compile spam. Failures still print.

## Failure playbook

1. **"No such scheme 'HealthPush'"** → xcodeproj is stale or missing. Run `xcodegen` manually from `ios/HealthPush/` and retry.
2. **"Unable to find a destination matching..."** → the iPhone 16 simulator isn't installed. List what's available with `xcrun simctl list devices available` and swap in a suitable iOS 17+ simulator.
3. **Compile failures** → read the Swift error and fix the root cause. Do not retry blindly.
4. **Test failures** → if `-quiet` hides context, drop it and re-run. Or filter the output with a grep for `Testing failed`, `error:`, or the specific failing test name.
5. **"Cycle in dependencies" / "cannot find symbol"** → almost always a stale xcodeproj that didn't pick up a new file. Run `xcodegen` manually and retry.

## Scope

This skill runs **only** the iOS tests. For other test suites in the monorepo:

- **Home Assistant integration (Python)**: `cd integrations/homeassistant && python -m pytest`
- **HealthPushStorageCore (Swift package)**: `cd packages/HealthPushStorageCore && swift test`

Don't conflate them — each has its own CI workflow (`ios-ci.yml`, `ha-integration-ci.yml`, `s3-core-ci.yml`) and failure modes.
