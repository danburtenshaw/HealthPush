---
name: new-destination
description: Scaffold a new HealthPush sync destination end-to-end — DestinationType enum case, DestinationConfig fields, Destination struct conforming to SyncDestination, DestinationManager wiring, setup screen, and tests. Use when the user wants to add support for a new destination (generic REST, Google Drive, Google Sheets, MQTT, WebDAV, etc.).
---

# New Destination Scaffold

HealthPush is a destination-agnostic health data exporter. Adding a destination touches ~6 coordinated files — this skill walks through the full change set so nothing gets forgotten and the multi-destination abstraction stays clean.

## Step 0 — Gather requirements

Before writing code, confirm with the user:

1. **Destination name and display name** — e.g. `googleSheets` / "Google Sheets"
2. **Transport model** — HTTP request/response? File upload with overwrite? Pub/sub? Append-only?
3. **Auth model** — bearer token? OAuth? signed request? anonymous?
4. **Config fields** — what does the user enter in the setup screen (URL, sheet ID, topic, token…)?
5. **Sync semantics** — can you re-send the same data point safely? How does the destination deduplicate?
6. **SF Symbol** — pick one from `SF Symbols.app` for the destination card

If any answer is unclear, **ask before scaffolding**. Guessing here creates rework.

## Step 1 — Add the enum case

File: `ios/HealthPush/Sources/Models/DestinationConfig.swift`

```swift
enum DestinationType: String, Codable, Sendable, CaseIterable, Identifiable {
    case homeAssistant = "Home Assistant"
    case s3 = "Amazon S3"
    case <newCase> = "<Display Name>"

    var displayName: String {
        switch self {
        case .homeAssistant: return "Home Assistant"
        case .s3: return "S3-Compatible Storage"
        case .<newCase>: return "<Display Name>"
        }
    }

    var symbolName: String {
        switch self {
        case .homeAssistant: return "house.fill"
        case .s3: return "cloud.fill"
        case .<newCase>: return "<sf-symbol-name>"
        }
    }
}
```

## Step 2 — Extend DestinationConfig if necessary

**First try to reuse existing fields.** `DestinationConfig` already has `baseURL`, `apiToken`, and the `enabledMetrics` set, plus a `s3*` prefix for S3-only fields. Only add new fields if none of the existing ones fit.

If you must add fields:
- Use a prefix that makes ownership obvious (`rest…`, `gdrive…`, `mqtt…`)
- Give them defaults so existing SwiftData records don't need a migration
- Store any credentials via the keychain pattern — mirror `s3SecretAccessKeyKeychainKey` (`secureStoredSecretsIfNeeded`, `apiTokenValue(migratingIfNeeded:)`)

**Never** put destination-specific fields on `HealthDataPoint`, `SyncRecord`, or `ExportFormat` — those must stay destination-agnostic.

## Step 3 — Create the destination struct

File: `ios/HealthPush/Sources/Destinations/<Name>Destination.swift`

Reference: `S3Destination.swift` (struct, uses `HealthDataExporter`) or `HomeAssistantDestination.swift` (more request/response-oriented).

Required:

```swift
import Foundation
import os

enum <Name>DestinationError: LocalizedError, Sendable {
    case invalidConfiguration(String)
    case syncFailed(String)

    var errorDescription: String? { /* ... */ }
}

struct <Name>Destination: SyncDestination {
    let id: UUID
    let name: String
    let isEnabled: Bool

    private let logger = Logger(subsystem: "app.healthpush", category: "<Name>Destination")
    // ... destination-specific client/service

    init(config: DestinationConfig) throws {
        self.id = config.id
        self.name = config.name
        self.isEnabled = config.isEnabled
        // validate + build client
    }

    func sync(data: [HealthDataPoint]) async throws -> SyncStats {
        // 1. Use HealthDataExporter for grouping/dedup/serialization
        // 2. Hand the exported payloads to your transport
        // 3. Return SyncStats(processedCount:, newCount:)
    }

    func testConnection() async throws -> Bool {
        // Cheap read-only probe — HEAD, GET /api/, etc.
    }
}
```

**Hard rules**:
- Must be `Sendable` (struct, let-only, or explicit `@unchecked Sendable` with justification)
- Use shared `HealthDataExporter` for grouping, UUID dedup, and format serialization — **do not reimplement**
- Only import Apple frameworks (no third-party SDKs — see the `privacy-reviewer` agent)
- The destination may only contact hosts derived from `config` — never hardcoded

## Step 4 — Wire up DestinationManager

File: `ios/HealthPush/Sources/Destinations/DestinationManager.swift`

Add a `create<Name>Destination(...)` method mirroring `createS3Destination`:

```swift
@discardableResult
func create<Name>Destination(
    name: String,
    // ... config fields
    enabledMetrics: Set<HealthMetricType>,
    syncFrequency: SyncFrequency = .oneHour,
    modelContext: ModelContext
) throws -> DestinationConfig {
    let config = DestinationConfig(
        name: name,
        destinationType: .<newCase>,
        // ... map inputs to DestinationConfig fields
        enabledMetrics: enabledMetrics
    )
    config.syncFrequency = syncFrequency
    modelContext.insert(config)

    do {
        try config.secureStoredSecretsIfNeeded()
        try modelContext.save()
        loadDestinations(modelContext: modelContext)
        onDestinationsChanged?()
        logger.info("Created <Name> destination: \(name)")
    } catch {
        modelContext.delete(config)
        if error is KeychainError {
            throw DestinationManagerError.secretStorageFailed(error.localizedDescription)
        }
        throw DestinationManagerError.persistenceFailed(error.localizedDescription)
    }

    return config
}
```

Also add a case to `testConnection(for:)`:

```swift
case .<newCase>:
    let destination = try <Name>Destination(config: config)
    success = try await destination.testConnection()
```

And grep for any other `switch config.destinationType` — if there are more than 2 switches, stop and ask whether a protocol method would be cleaner. **Scattered switches are a destination-abstraction smell.**

## Step 5 — Add the setup screen

File: `ios/HealthPush/Sources/Views/Screens/<Name>SetupScreen.swift`

Reference: `S3SetupScreen.swift` (610 lines — comprehensive example) or `HomeAssistantSetupScreen.swift`.

Required sections:
1. Config fields (`TextField`, `SecureField`, etc.)
2. Metric picker (reuse the pattern from existing setup screens)
3. Sync frequency picker
4. "Test connection" button → `destinationManager.testConnection(for:)` + surface `lastTestResult`
5. Save button → calls `destinationManager.create<Name>Destination(...)`

Also update `AddDestinationSheet.swift` to list the new destination type in the picker.

## Step 6 — Tests

File: `ios/HealthPush/Tests/<Name>DestinationTests.swift`

Reference: `S3DestinationIntegrationTests.swift`.

Minimum coverage:
- `init(config:)` — valid config, invalid config (missing fields, malformed URLs)
- `testConnection()` — success path and failure path (use a mock URLSession or a fake client)
- `sync(data:)` — empty array, single data point, multiple metrics, duplicate detection

## Step 7 — Docs

- Add `docs/setup-<name>.mdx` (mirror `docs/setup-amazon-s3.mdx`)
- Register it in `docs/docs.json`
- Update `README.md` destination list if the scaffolding adds the first destination of a new category

## Step 8 — Verify

Run the tests:

```bash
cd ios/HealthPush && xcodegen && xcodebuild test \
  -project HealthPush.xcodeproj \
  -scheme HealthPush \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

(Or use the `ios-test` skill if it's available.)

Then consider asking the `privacy-reviewer` and `destination-abstraction-reviewer` agents to bless the change before opening a PR.

## Anti-patterns to avoid

- Adding a `switch destinationType` to `SyncEngine`, `HealthDataExporter`, or `BackgroundSyncScheduler`. If the shared code needs new behavior, add a method to the `SyncDestination` protocol instead.
- Importing any third-party library. HealthPush is strict about Apple-frameworks-only.
- Hardcoding any hostname. All network destinations must derive from user-provided `DestinationConfig`.
- Reimplementing dedup or serialization. `HealthDataExporter` owns both — use it.
- Forgetting to run `xcodegen` after adding files. (The `xcodegen-regen` hook handles this automatically when `project.yml` changes, but new source files are picked up from the `Sources/` directory without needing a yml edit.)
