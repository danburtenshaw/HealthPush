<!-- HealthPush Logo — replace with actual logo when available -->
<!-- <p align="center"><img src="docs/assets/logo.png" alt="HealthPush" width="200"></p> -->

<h1 align="center">HealthPush</h1>

<p align="center">
  <strong>Sync your Apple Health data to Home Assistant and beyond.</strong>
</p>

<p align="center">
  <a href="https://github.com/danburtenshaw/HealthPush/actions/workflows/ci.yml"><img src="https://github.com/danburtenshaw/HealthPush/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/platform-iOS_17%2B-black.svg?logo=apple" alt="Platform: iOS 17+">
  <img src="https://img.shields.io/badge/Swift-6.0-F05138.svg?logo=swift&logoColor=white" alt="Swift 6.0">
  <a href="https://hacs.xyz"><img src="https://img.shields.io/badge/HACS-compatible-41BDF5.svg" alt="HACS"></a>
</p>

<p align="center">
  No accounts. No subscriptions. No telemetry.<br>
  Your health data, pushed where <em>you</em> decide.
</p>

---

## What is HealthPush?

HealthPush is an open-source iOS app that reads your Apple Health data and syncs it to destinations you control. The primary destination today is **Home Assistant**, but the architecture is built to support any target -- CSV exports, Google Sheets, MQTT brokers, and more.

The app runs in the background, requires zero cloud accounts, and never phones home. If you care about owning your health data, this is for you.

## Features

- **Background sync** -- Set it and forget it. BGTaskScheduler keeps your data flowing without opening the app.
- **Home Assistant native** -- A dedicated HACS-compatible custom component creates proper HA sensors with device classes, icons, and units.
- **13 health metrics** -- Steps, heart rate, blood oxygen, weight, blood pressure, body temperature, sleep, active energy, walking distance, flights climbed, respiratory rate, resting heart rate, and more coming.
- **Extensible destinations** -- Adding a new sync target means implementing one Swift protocol. CSV? Google Sheets? PDF? Build it.
- **No third-party dependencies** -- The iOS app uses zero external packages. Smaller attack surface, faster builds, full auditability.
- **Privacy first** -- No analytics, no tracking, no accounts. Health data leaves your device only to destinations you explicitly configure.
- **Fully open source** -- MIT licensed. Read every line, fork it, make it yours.

## Screenshots

<!-- Screenshots will be added here once the UI is finalized -->
<!-- <p align="center">
  <img src="docs/assets/screenshot-dashboard.png" width="250" alt="Dashboard">
  <img src="docs/assets/screenshot-destinations.png" width="250" alt="Destinations">
  <img src="docs/assets/screenshot-ha-sensors.png" width="250" alt="Home Assistant Sensors">
</p> -->

*Screenshots coming soon.*

## Quick Start

### iOS App

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

4. **Build and run** on a device or simulator (iOS 17+). Grant HealthKit permissions when prompted.

5. **Configure a destination** -- tap the + button, enter your Home Assistant webhook URL and optional webhook secret, then hit Test Connection.

6. **That's it.** HealthPush will sync in the background automatically.

### Home Assistant Integration

The Home Assistant side is a custom component that receives webhook pushes from the iOS app and updates sensor entities.

#### Install via HACS (recommended)

1. Open HACS in your Home Assistant instance.
2. Go to **Integrations** and click the three-dot menu.
3. Select **Custom repositories** and add `https://github.com/danburtenshaw/HealthPush` with category **Integration**.
4. Search for "HealthPush" and install it.
5. Restart Home Assistant.
6. Go to **Settings > Devices & Services > Add Integration** and search for "HealthPush".

#### Install manually

```bash
cp -r integrations/homeassistant/custom_components/healthpush \
  /path/to/your/homeassistant/custom_components/
```

Restart Home Assistant, then add the integration from Settings.

### Supported Metrics

| Metric | Unit | HA Device Class |
|---|---|---|
| Steps | steps | -- |
| Heart Rate | bpm | -- |
| Blood Oxygen | % | -- |
| Weight | kg | weight |
| Blood Pressure (systolic) | mmHg | -- |
| Blood Pressure (diastolic) | mmHg | -- |
| Body Temperature | C | temperature |
| Sleep Duration | h | duration |
| Active Energy | kcal | -- |
| Walking + Running Distance | km | distance |
| Flights Climbed | flights | -- |
| Respiratory Rate | breaths/min | -- |
| Resting Heart Rate | bpm | -- |

## Architecture

HealthPush follows a clean, protocol-oriented architecture:

```
Apple Health (HealthKit)
        |
   Sync Engine          <-- Reads data, manages scheduling
        |
  Destination Protocol  <-- Abstract interface for all targets
       / \
      /   \
  HA    CSV   ...       <-- Concrete implementations
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
