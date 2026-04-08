<!-- HealthPush Logo — replace with actual logo when available -->
<!-- <p align="center"><img src="docs/assets/logo.png" alt="HealthPush" width="200"></p> -->

<h1 align="center">HealthPush</h1>

<p align="center">
  <strong>Sync your Apple Health data to Home Assistant and beyond.</strong>
</p>

<p align="center">
  <a href="https://github.com/danburtenshaw/HealthPush/actions/workflows/ios-ci.yml"><img src="https://github.com/danburtenshaw/HealthPush/actions/workflows/ios-ci.yml/badge.svg" alt="iOS CI"></a>
  <a href="https://github.com/danburtenshaw/HealthPush/actions/workflows/ha-integration-ci.yml"><img src="https://github.com/danburtenshaw/HealthPush/actions/workflows/ha-integration-ci.yml/badge.svg" alt="HA CI"></a>
  <a href="https://github.com/danburtenshaw/HealthPush/actions/workflows/s3-core-ci.yml"><img src="https://github.com/danburtenshaw/HealthPush/actions/workflows/s3-core-ci.yml/badge.svg" alt="S3 Core CI"></a>
  <a href="https://github.com/danburtenshaw/HealthPush/actions/workflows/codeql.yml"><img src="https://github.com/danburtenshaw/HealthPush/actions/workflows/codeql.yml/badge.svg" alt="CodeQL"></a>
  <a href="https://github.com/danburtenshaw/HealthPush/actions/workflows/lint.yml"><img src="https://github.com/danburtenshaw/HealthPush/actions/workflows/lint.yml/badge.svg" alt="Lint & Guards"></a>
  <a href="https://securityscorecards.dev/viewer/?uri=github.com/danburtenshaw/HealthPush"><img src="https://api.securityscorecards.dev/projects/github.com/danburtenshaw/HealthPush/badge" alt="OSSF Scorecard"></a>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/platform-iOS_17%2B-black.svg?logo=apple" alt="Platform: iOS 17+">
  <img src="https://img.shields.io/badge/Swift-6.0-F05138.svg?logo=swift&logoColor=white" alt="Swift 6.0">
  <a href="https://hacs.xyz"><img src="https://img.shields.io/badge/HACS-compatible-41BDF5.svg" alt="HACS"></a>
  <a href="https://conventionalcommits.org"><img src="https://img.shields.io/badge/Conventional_Commits-1.0.0-%23FE5196?logo=conventionalcommits&logoColor=white" alt="Conventional Commits"></a>
</p>

<p align="center">
  No accounts. No subscriptions. No telemetry.<br>
  Your health data, pushed where <em>you</em> decide.
</p>

---

## What is HealthPush?

HealthPush is an open-source iPhone app that reads your Apple Health data and syncs it to destinations you control. The current app supports **S3-compatible storage** and **Home Assistant**, with the broader architecture designed to support REST endpoints, Google Drive, Google Sheets, CSV exports, MQTT, and more.

There is no HealthPush backend, no account system, and no telemetry. Data goes directly from your device to the destinations you configure.

If you care about owning your health data, this is what the app is for.

## Start Here

- User documentation: [`docs/index.mdx`](docs/index.mdx)
- Quick start: [`docs/quickstart.mdx`](docs/quickstart.mdx)
- Privacy and open-source guarantees: [`docs/privacy-and-open-source.mdx`](docs/privacy-and-open-source.mdx)
- Real background sync expectations: [`docs/sync-behavior.mdx`](docs/sync-behavior.mdx)
- Home Assistant setup: [`docs/setup-home-assistant.mdx`](docs/setup-home-assistant.mdx)
- S3-compatible storage setup: [`docs/setup-amazon-s3.mdx`](docs/setup-amazon-s3.mdx)

## Features

- **Background sync** -- HealthPush can sync in the background, but iOS controls exact timing. The app also listens for HealthKit background delivery when new data arrives.
- **S3-compatible export** -- Direct export to your own bucket with JSON or CSV output, configurable sync windows, deduplicated uploads, and optional custom endpoints.
- **Home Assistant native** -- A dedicated HACS-compatible custom component creates proper HA sensors with device classes, icons, and units.
- **Guided first-run setup** -- A welcome flow walks through Health access, privacy expectations, and destination setup.
- **25 health metrics** -- Activity, body, vitals, sleep, and nutrition metrics are supported today.
- **Extensible destinations** -- Adding a new sync target means implementing one Swift protocol. CSV? Google Sheets? PDF? Build it.
- **No third-party dependencies** -- The iOS app uses zero external packages. Smaller attack surface, faster builds, full auditability.
- **Privacy first** -- No analytics, no tracking, no accounts. Health data leaves your device only to destinations you explicitly configure.
- **Fully open source** -- MIT licensed. Read every line, fork it, make it yours.

## Before You Rely On Background Sync

HealthPush does background sync in the iOS-approved way, which means there are some hard limits:

- The sync frequency you choose is a minimum interval, not an exact schedule.
- iOS may delay work because of battery state, device activity, network conditions, Low Power Mode, or its own scheduling heuristics.
- HealthKit background delivery can wake the app when new data arrives, but that is still managed by iOS.
- If you force-quit the app, background sync stops until you open the app again.
- Health data is protected while the device is locked, so some sync work may wait until the phone is unlocked.

If you need the full detail, read [`docs/sync-behavior.mdx`](docs/sync-behavior.mdx).

## Screenshots

<!-- Screenshots will be added here once the UI is finalized -->
<!-- <p align="center">
  <img src="docs/assets/screenshot-dashboard.png" width="250" alt="Dashboard">
  <img src="docs/assets/screenshot-destinations.png" width="250" alt="Destinations">
  <img src="docs/assets/screenshot-ha-sensors.png" width="250" alt="Home Assistant Sensors">
</p> -->

*Screenshots coming soon.*

## Setup Guides

### Run The App

1. **Clone the repo**

   ```bash
   git clone https://github.com/danburtenshaw/HealthPush.git
   cd HealthPush/ios/HealthPush
   ```

2. **Generate the Xcode project** (requires [XcodeGen](https://github.com/yonaskolb/XcodeGen))

   ```bash
   brew install xcodegen
   xcodegen
   ```

3. **Open in Xcode**

   ```bash
   open HealthPush.xcodeproj
   ```

4. **Build and run** on a device or simulator (iOS 17+).

5. **Finish the welcome flow** -- review privacy details, grant Health access, and add your first destination.

6. **Run a manual sync once** to verify the full path.

### Home Assistant

- Full guide: [`docs/setup-home-assistant.mdx`](docs/setup-home-assistant.mdx)
- Install the custom integration in Home Assistant.
- Copy the generated webhook URL into the iOS app.
- Optional: configure a shared secret on both sides.
- Test the connection and save.

### S3-Compatible Storage

- Full guide: [`docs/setup-amazon-s3.mdx`](docs/setup-amazon-s3.mdx)
- Enter the bucket, region, and credentials.
- Optionally set a custom endpoint for MinIO or another compatible service.
- Choose JSON or CSV export.
- Pick how far back to backfill on first sync.
- Test the connection and save.

### Supported Metrics

#### Activity

- Steps
- Active Energy
- Resting Energy
- Walking + Running Distance
- Cycling Distance
- Flights Climbed
- Exercise Minutes
- Stand Time
- Move Time

#### Body

- Weight
- BMI
- Body Fat
- Height
- Lean Body Mass

#### Vitals

- Heart Rate
- Resting Heart Rate
- Heart Rate Variability
- Blood Pressure (Systolic)
- Blood Pressure (Diastolic)
- Blood Oxygen
- Respiratory Rate
- Body Temperature

#### Sleep

- Sleep Analysis

#### Nutrition

- Dietary Energy
- Water Intake

## Architecture

HealthPush follows a clean, protocol-oriented architecture:

```text
Apple Health (HealthKit)
        |
   Sync Engine          <-- Reads data, manages scheduling
        |
  Destination Protocol  <-- Abstract interface for all targets
       / \
      /   \
  S3    HA    ...       <-- Concrete implementations
```

- **Sync Engine** -- Queries HealthKit on a schedule via `BGTaskScheduler`, batches data points, and dispatches them to enabled destinations.
- **Destination Protocol** -- Every sync target implements `SyncDestination`. This is the single extension point for adding new destinations.
- **SwiftData + Keychain** -- Destination settings and sync history are stored locally on-device, and secrets are stored in Keychain.
- **No server** -- The app pushes directly to your destinations. There is no intermediary.

For a deeper dive, see [docs/architecture.md](docs/architecture.md) and [AGENTS.md](AGENTS.md).

## How Destinations Work

Destinations are protocol-based and fully extensible. The core protocol:

```swift
protocol SyncDestination: Identifiable, Codable {
    var id: UUID { get }
    var name: String { get }
    var isEnabled: Bool { get set }
    func sync(data: [HealthDataPoint]) async throws
    func testConnection() async throws -> Bool
}
```

To add a new destination (say, CSV export), you:

1. Create a new file in `ios/HealthPush/Sources/Destinations/`
2. Implement `SyncDestination`
3. Register it in `DestinationManager`
4. Add a configuration UI in `Views/Screens/`

See [docs/adding-a-destination.md](docs/adding-a-destination.md) for the full guide.

## Roadmap

- [x] Amazon S3 destination
- [x] Home Assistant webhook destination
- [x] Background sync with BGTaskScheduler
- [x] HACS-compatible custom component
- [ ] CSV file export destination
- [ ] PDF health report destination
- [ ] Google Sheets destination
- [ ] MQTT broker destination
- [ ] Apple Watch companion app
- [ ] Configurable sync intervals
- [ ] Historical data backfill
- [ ] Widgets for sync status

Have an idea? [Open a feature request.](https://github.com/danburtenshaw/HealthPush/issues/new?template=feature_request.yml)

## Contributing

Contributions are welcome and appreciated! Whether it is fixing a typo, adding a new destination, or improving the Home Assistant integration -- every contribution matters.

Please read [CONTRIBUTING.md](CONTRIBUTING.md) before submitting a pull request.

## Privacy

HealthPush is built on a simple principle: **your health data is yours.**

- **No accounts** -- The app does not require sign-up, sign-in, or any form of registration.
- **No telemetry** -- Zero analytics, zero crash reporting, zero usage tracking. Nothing phones home.
- **No cloud** -- There is no HealthPush server. Data goes directly from your device to destinations you configure.
- **No third-party code** -- The iOS app has zero external dependencies. Every line of networking code is auditable in this repo.
- **Local storage only** -- Settings and sync history stay on-device, and destination credentials are stored in Keychain.
- **Open source** -- The entire codebase is here. You can verify every claim above by reading the source.

Health data leaves your device **only** when sent to a destination you have explicitly configured and enabled. That is it.

## License

HealthPush is released under the [MIT License](LICENSE).

---

<p align="center">
  Built with care for people who own their data.
</p>
