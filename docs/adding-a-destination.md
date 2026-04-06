# Adding a New Destination

This guide walks through adding a new sync destination to HealthPush. Destinations are the core extension point -- they define where health data gets sent.

## Overview

Every destination implements the `SyncDestination` protocol:

```swift
protocol SyncDestination: Identifiable, Codable {
    var id: UUID { get }
    var name: String { get }
    var isEnabled: Bool { get set }
    func sync(data: [HealthDataPoint]) async throws
    func testConnection() async throws -> Bool
}
```

## Step-by-Step

We'll use a hypothetical "CSV Export" destination as an example.

### 1. Create the Destination File

Create `ios/HealthPush/Sources/Destinations/CSVExportDestination.swift`:

```swift
import Foundation

struct CSVExportDestination: SyncDestination {
    let id: UUID
    var name: String
    var isEnabled: Bool
    var exportDirectory: URL

    init(
        id: UUID = UUID(),
        name: String = "CSV Export",
        isEnabled: Bool = true,
        exportDirectory: URL
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.exportDirectory = exportDirectory
    }

    func sync(data: [HealthDataPoint]) async throws {
        let dateFormatter = ISO8601DateFormatter()
        var csvContent = "metric,value,unit,timestamp\n"

        for point in data {
            let timestamp = dateFormatter.string(from: point.timestamp)
            csvContent += "\(point.metricType.rawValue),\(point.value),\(point.unit),\(timestamp)\n"
        }

        let fileName = "healthpush-\(dateFormatter.string(from: Date())).csv"
        let fileURL = exportDirectory.appendingPathComponent(fileName)
        try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func testConnection() async throws -> Bool {
        // Verify we can write to the export directory
        let testFile = exportDirectory.appendingPathComponent(".healthpush-test")
        do {
            try "test".write(to: testFile, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(at: testFile)
            return true
        } catch {
            return false
        }
    }
}
```

### 2. Register in DestinationManager

Open `ios/HealthPush/Sources/Destinations/DestinationManager.swift` and register the new type so the app knows it exists:

```swift
// Add to the list of available destination types
enum DestinationType: String, CaseIterable, Codable {
    case homeAssistant
    case csvExport  // Add this
}
```

### 3. Add a Setup Screen

Create `ios/HealthPush/Sources/Views/Screens/CSVExportSetupScreen.swift`:

```swift
import SwiftUI

struct CSVExportSetupScreen: View {
    @State private var exportPath: String = ""
    @State private var testResult: Bool?

    var body: some View {
        Form {
            Section("Export Location") {
                TextField("Directory path", text: $exportPath)
            }

            Section {
                Button("Test Export") {
                    Task {
                        // Test writing to the directory
                    }
                }

                if let result = testResult {
                    Label(
                        result ? "Export directory is writable" : "Cannot write to directory",
                        systemImage: result ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                    .foregroundStyle(result ? .green : .red)
                }
            }

            Section {
                Button("Save Destination") {
                    // Save via DestinationManager
                }
                .disabled(exportPath.isEmpty)
            }
        }
        .navigationTitle("CSV Export")
    }
}
```

### 4. Wire Up Navigation

In `DestinationsScreen.swift`, add the new destination to the "Add Destination" flow so users can select it.

### 5. Write Tests

Create `ios/HealthPush/Tests/CSVExportDestinationTests.swift`:

```swift
import XCTest
@testable import HealthPush

final class CSVExportDestinationTests: XCTestCase {
    func testSyncWritesCSVFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let destination = CSVExportDestination(exportDirectory: tempDir)
        let data = [
            HealthDataPoint(
                metricType: .steps,
                value: 1000,
                unit: "steps",
                timestamp: Date()
            )
        ]

        try await destination.sync(data: data)

        let files = try FileManager.default.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files[0].lastPathComponent.hasSuffix(".csv"))

        // Clean up
        try FileManager.default.removeItem(at: tempDir)
    }

    func testConnectionSucceedsForWritableDirectory() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let destination = CSVExportDestination(exportDirectory: tempDir)
        let result = try await destination.testConnection()
        XCTAssertTrue(result)
    }
}
```

### 6. Update Documentation

- Add the destination to the supported destinations table in `README.md`
- Update the roadmap in `README.md` to mark it as complete

## Checklist

- [ ] `SyncDestination` protocol implemented
- [ ] Registered in `DestinationManager`
- [ ] Setup screen created with `testConnection()` UI
- [ ] Navigation wired up in `DestinationsScreen`
- [ ] Tests written and passing
- [ ] README updated

## Tips

- Keep `sync()` idempotent where possible -- if the destination supports it, avoid duplicating data on re-sync.
- Always implement `testConnection()` meaningfully. Users rely on this to verify their setup before waiting for background syncs.
- Use `Codable` conformance to persist destination configuration via SwiftData.
- Handle network errors gracefully in `sync()` -- throw descriptive errors so the sync engine can log useful failure reasons.
