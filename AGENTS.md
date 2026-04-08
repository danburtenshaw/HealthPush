# HealthPush — Agent & Development Guide

## Purpose Of This File

Use this file as the durable source of truth for coding agents working in this repo. Keep it focused on product direction, architecture constraints, repository conventions, and implementation guidance that should shape decisions across tasks.

Do not treat this file as a changelog or a sprint board. Put volatile status updates in issues, PRs, or dedicated planning docs.

## Project Overview

HealthPush is a fully open-source iOS app that reads Apple Health data and pushes it directly to destinations the user controls. The product is privacy-first, local-first, and account-free: no hosted HealthPush backend, no subscriptions, no telemetry, and no vendor lock-in.

Home Assistant is the first major integration, but the broader product direction is a destination-agnostic health data delivery app. HealthPush should be able to push data to user-owned and developer-friendly targets such as Home Assistant, Amazon S3, generic REST endpoints, Google Drive, Google Sheets, and similar systems without changing the core sync model.

## Product Direction

### Long-Term Vision
- Build the open-source standard for exporting Apple Health data to user-controlled destinations.
- Support multiple destination types without making any single integration the architectural center of the app.
- Keep the app understandable and auditable: follow the tiered dependency policy in `docs/dependencies.md`. The iOS app target stays at zero SPM deps; internal packages under `packages/` may use only allowlisted Apple-stewarded libraries.
- Preserve direct data flow from device to destination whenever feasible. Avoid introducing HealthPush-operated infrastructure.

### MVP Positioning
- The MVP does not need every planned destination.
- The MVP must prove the core value proposition: reliable Apple Health export, good onboarding, background sync, and enough trust signals that users can safely adopt it.
- Destination count is less important than one polished end-to-end workflow and a destination architecture that makes later additions straightforward.

### Product Decision Rules
- Prefer reusable destination primitives over one-off integrations.
- Prefer a smaller, reliable destination set over a broad but brittle one.
- Avoid hard-coding Home Assistant assumptions into shared sync logic.
- Treat S3, REST, Google Drive, Google Sheets, CSV, and future targets as first-class use cases when designing shared models and services.

## Monorepo Structure

```text
HealthPush/
├── ios/HealthPush/          # Native iOS app (SwiftUI + HealthKit)
│   ├── Sources/
│   │   ├── App/             # App entry point, lifecycle
│   │   ├── Models/          # Data models, HealthKit types
│   │   ├── Views/           # SwiftUI views
│   │   │   ├── Screens/     # Full-screen views
│   │   │   └── Components/  # Reusable UI components
│   │   ├── Services/        # HealthKit, background tasks, networking
│   │   └── Destinations/    # Sync destination implementations
│   ├── Resources/           # Assets, entitlements, Info.plist
│   └── Tests/               # Unit & integration tests
├── integrations/
│   └── homeassistant/       # Home Assistant custom component (Python)
├── fastlane/                # App Store deployment automation
├── .github/workflows/       # CI/CD pipelines
└── docs/                    # Architecture docs, setup guides
```

## Current Implementation Context

- The iOS app is the primary product surface.
- Home Assistant is implemented as a full destination plus a custom integration.
- Amazon S3 is implemented in the iOS app and should be treated as part of the multi-destination direction.
- The architecture and docs should continue to describe HealthPush as a multi-destination platform, not a Home Assistant-only app.
- New work should strengthen shared destination infrastructure where possible so REST, Google Drive, Google Sheets, CSV, and other targets can be added with minimal core churn.

## Tech Stack

### iOS App
- **Language**: Swift 6+ with strict concurrency
- **UI**: SwiftUI (iOS 17+)
- **Health**: HealthKit framework
- **Background**: BGTaskScheduler for automated syncs
- **Storage**: SwiftData for local persistence
- **Networking**: URLSession — see dependency policy in Architecture Principles #2
- **Project**: XcodeGen (`project.yml` generates `.xcodeproj`)

### Home Assistant Integration
- **Language**: Python 3.12+
- **Framework**: Home Assistant custom component
- **Distribution**: HACS-compatible

### CI/CD
- **CI**: GitHub Actions (build, test, lint)
- **Deploy**: Fastlane (App Store Connect)
- **Code Gen**: XcodeGen (run `xcodegen` in `ios/HealthPush/`)

## Architecture Principles

1. **Destination-first abstraction** — All sync targets implement `SyncDestination`. Core flows should remain destination-agnostic.
2. **Minimal, tiered, audited dependencies** — The iOS app target ships with **zero** third-party SPM dependencies. Internal packages under `packages/` may use only (a) Apple system frameworks, (b) Apple-stewarded Swift Server Workgroup packages (`swift-crypto`, `swift-asn1`, etc.) allowlisted by name, and (c) specific security-critical libraries with strong pedigree (currently none; `AppAuth-iOS` is planned for post-1.0 Google destinations). Every dependency is pinned, covered by Dependabot, listed in the release SBOM, and audited by the `privacy-reviewer` subagent on introduction. Analytics, telemetry, crash reporters, convenience libraries, and test frameworks beyond XCTest/Swift Testing are forbidden. Enforced by `scripts/check-no-third-party-deps.sh` in CI. See `docs/dependencies.md` for the current allowlist and the process for adding a new dep.
3. **Background-first** — The app is designed to run unattended. BGTaskScheduler handles periodic syncs.
4. **Privacy-first** — Health data never leaves the device except to destinations the user explicitly configures.
5. **Local-first** — All configuration is stored on-device via SwiftData.
6. **Direct-delivery bias** — Prefer direct uploads or API calls from the device to the destination. Avoid HealthPush-hosted relay services.
7. **Composable destination plumbing** — Shared export, auth, batching, retry, and connectivity logic should be reusable across multiple destination types.

## Destination Strategy

When adding or refactoring destinations:

- Keep `SyncEngine`, export models, and destination configuration generic.
- Push destination-specific auth, payload shaping, and transport details to the destination layer or reusable helper services.
- Prefer capabilities that multiple destinations can share:
  - JSON and CSV export formatting
  - incremental sync and deduplication
  - connection testing
  - retry-safe uploads
  - credential validation
  - sync history and error reporting
- Do not let one destination’s quirks define the shared model unless the tradeoff clearly benefits the platform.

Examples of target destination families HealthPush should be able to support over time:

- Home automation: Home Assistant, MQTT
- Object/file storage: Amazon S3, Google Drive, local files, WebDAV
- API-based sinks: generic REST endpoints, developer webhooks
- Tabular/reporting sinks: Google Sheets, CSV exports, future reporting formats

## Development Workflow

### iOS App
```bash
cd ios/HealthPush
xcodegen                    # Generate .xcodeproj from project.yml
open HealthPush.xcodeproj   # Open in Xcode
```

### Home Assistant Integration
```bash
cp -r integrations/homeassistant/custom_components/healthpush \
  ~/.homeassistant/custom_components/
```

### Running Tests
```bash
cd ios/HealthPush && xcodegen && xcodebuild test \
  -project HealthPush.xcodeproj \
  -scheme HealthPush \
  -destination 'platform=iOS Simulator,name=iPhone 16'

cd integrations/homeassistant && python -m pytest
```

## Key Conventions

- Commit messages: imperative mood, concise (`Add background sync scheduler`)
- Branch naming: `feature/`, `fix/`, `docs/`
- PRs require passing CI before merge
- SwiftUI previews should work for view components
- All HealthKit data types use canonical `HKQuantityTypeIdentifier` / `HKCategoryTypeIdentifier` names
- Prefer adding reusable abstractions before adding destination-specific branching in shared code

## Destination Protocol

```swift
protocol SyncDestination: Identifiable, Codable {
    var id: UUID { get }
    var name: String { get }
    var isEnabled: Bool { get set }
    func sync(data: [HealthDataPoint]) async throws
    func testConnection() async throws -> Bool
}
```

Adding a new destination:

1. Create a new file in `Sources/Destinations/`
2. Implement `SyncDestination`
3. Register it in `DestinationManager`
4. Add configuration UI in `Views/Screens/`
5. Add or update tests for sync behavior, connection testing, and config validation

## Claude Code Tooling

If you use [Claude Code](https://claude.com/claude-code) for this repo, the `.claude/` directory ships project-wide automations. They're opt-in — contributors using other tools can ignore them.

- **Subagents** (`.claude/agents/`)
  - `privacy-reviewer` — audits Swift changes for the three non-negotiables (no third-party deps, no telemetry, no HealthPush-hosted relays). Invoke after touching network code, dependencies, or background tasks.
  - `destination-abstraction-reviewer` — flags Home Assistant or S3 quirks leaking into shared sync infrastructure (`SyncEngine`, `HealthDataExporter`, shared models). Invoke after touching `Sources/Services/**` or `Sources/Models/**`.
- **Skills** (`.claude/skills/`)
  - `/new-destination` — scaffolds a new `SyncDestination` end-to-end (enum case, config fields, destination struct, `DestinationManager` wiring, setup screen, tests).
  - `/ios-test` — runs the iOS test suite against the iPhone 16 simulator, regenerating the Xcode project first.
- **Hooks** (`.claude/hooks/`)
  - `xcodegen-regen.sh` — `PostToolUse` hook that automatically runs `xcodegen` whenever `ios/HealthPush/project.yml` is edited, so the generated `.xcodeproj` never drifts.

Personal overrides (extra permissions, experimental flags) belong in `.claude/settings.local.json`, which is gitignored.

## Guidance For Agents

- Preserve the positioning of HealthPush as a multi-destination open-source platform.
- If a change improves only one destination, check whether the same mechanism should be generalized first.
- Keep README and docs aligned with the actual product direction and implemented destinations.
- For MVP-oriented work, prioritize reliability, onboarding clarity, observability, and App Store readiness ahead of adding more destination count.
- If you introduce a new planned destination in docs, make clear whether it is implemented, in progress, or aspirational.
