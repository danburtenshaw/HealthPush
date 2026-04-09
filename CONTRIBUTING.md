# Contributing to HealthPush

Thank you for your interest in contributing to HealthPush! This document covers everything you need to get started -- from setting up your development environment to submitting a pull request.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Development Environment](#development-environment)
- [Project Structure](#project-structure)
- [Code Style](#code-style)
- [Making Changes](#making-changes)
- [Adding a New Destination](#adding-a-new-destination)
- [Running Tests](#running-tests)
- [Pull Request Process](#pull-request-process)
- [Reporting Issues](#reporting-issues)

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md). By participating, you agree to uphold a welcoming, inclusive, and respectful environment.

## Development Environment

### Prerequisites

| Tool     | Version | Purpose                                   |
| -------- | ------- | ----------------------------------------- |
| Xcode    | 16.0+   | iOS app development                       |
| XcodeGen | latest  | Generates `.xcodeproj` from `project.yml` |
| Swift    | 6.0+    | iOS app language                          |
| Python   | 3.12+   | Home Assistant integration                |
| Git      | latest  | Version control                           |

### iOS App Setup

```bash
# 1. Clone the repository
git clone https://github.com/danburtenshaw/HealthPush.git
cd HealthPush

# 2. Install XcodeGen (if not already installed)
brew install xcodegen

# 3. Generate the Xcode project
cd ios/HealthPush
xcodegen

# 4. Open in Xcode
open HealthPush.xcodeproj
```

The generated `.xcodeproj` is in `.gitignore` -- always regenerate it from `project.yml` after pulling changes.

### Home Assistant Integration Setup

```bash
# 1. Create a virtual environment
cd integrations/homeassistant
python3 -m venv .venv
source .venv/bin/activate

# 2. Install development dependencies
pip install -r requirements-dev.txt  # (when available)
pip install pytest ruff

# 3. Run tests
python -m pytest
```

### Recommended Editor Setup

- **iOS**: Xcode with default Swift formatting
- **Python**: VS Code with the Ruff extension, or any editor with ruff integration
- **Markdown**: Any editor with a markdown preview

### Local Git Hooks (optional)

HealthPush ships a [`lefthook`](https://github.com/evilmartian/lefthook) config at `.lefthook.yml`. It runs the same checks CI uses, but on your staged files before you commit — `swiftformat`, `swiftlint`, `gitleaks`, `shellcheck`, `ruff`, `markdownlint`, and the third-party-deps guard.

Hooks are **opt-in**. CI re-runs everything on every push, so skipping them is never a shortcut past CI.

```bash
# Install lefthook and the tools it calls
brew install lefthook swiftformat swiftlint gitleaks shellcheck markdownlint-cli

# Wire lefthook into this clone's .git/hooks
lefthook install

# Run every pre-commit hook against the whole tree (useful after pulling)
lefthook run pre-commit --all-files

# Turn it off
lefthook uninstall
```

If you don't want local hooks, just don't install lefthook — nothing else depends on it.

## Project Structure

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

See [AGENTS.md](AGENTS.md) for a detailed architecture and conventions guide.

## Code Style

### Swift (iOS App)

- **Swift 6** with strict concurrency enabled (`SWIFT_STRICT_CONCURRENCY: complete`)
- SwiftLint will be integrated soon -- the configuration will be checked in as `.swiftlint.yml`
- Use `async/await` for all asynchronous work. No completion handlers.
- Prefer value types (`struct`, `enum`) over reference types where practical.
- All public APIs must have documentation comments using `///` syntax.
- SwiftUI previews should be provided for all view components.
- No third-party dependencies in the iOS app. This is a firm policy.

General conventions:

```swift
// Use descriptive names
func syncHealthData(to destination: SyncDestination) async throws { ... }

// Document public interfaces
/// Fetches health data points for the given date range.
/// - Parameters:
///   - start: The beginning of the date range.
///   - end: The end of the date range.
/// - Returns: An array of health data points.
func fetchData(from start: Date, to end: Date) async throws -> [HealthDataPoint] { ... }

// Prefer guard for early exits
guard let destination = selectedDestination else { return }
```

### Python (Home Assistant Integration)

- Python 3.12+
- Ruff for linting and formatting (will be enforced in CI)
- Follow Home Assistant's [development guidelines](https://developers.home-assistant.io/)
- Type hints on all function signatures
- Docstrings on all public functions and classes

### Commit Messages — Conventional Commits

HealthPush uses [Conventional Commits](https://www.conventionalcommits.org/) on **PR titles**. The PR title becomes the commit on `main` (squash-merge only). `release-please` parses commit history to open release PRs automatically, so the format matters.

Format:

```text
<type>(<scope>): <Subject>
```

**Valid types:**

| Type       | Meaning                                                  |
| ---------- | -------------------------------------------------------- |
| `feat`     | New user-visible functionality                           |
| `fix`      | Bug fix                                                  |
| `perf`     | Performance improvement                                  |
| `refactor` | Code change that does not add functionality or fix a bug |
| `docs`     | Documentation only                                       |
| `test`     | Test additions or corrections                            |
| `chore`    | Routine maintenance, tooling, configuration              |
| `ci`       | CI/CD pipeline changes                                   |
| `build`    | Build system, packaging, Fastlane                        |
| `security` | Security-related change or hardening                     |
| `revert`   | Revert of a previous commit                              |

**Valid scopes** (optional but recommended):

`ios`, `ha`, `destinations`, `sync`, `docs`, `ci`, `deps`, `release`.

**Subject rules:**

- Starts with an uppercase letter.
- Imperative mood: *"Add background sync scheduler"*, not *"Added"* or *"Adding"*.
- No trailing period.
- Under ~70 characters.

**Examples:**

```text
feat(destinations): Add REST webhook destination
fix(sync): Handle DST transition in Calendar.date(byAdding:)
refactor(ios): Split SyncEngine.performSync into stage functions
docs(ha): Document LAN HTTP policy and private-IP allowlist
ci: Bump codeql-action to v3.29.4
security(ha): Require webhook secret at registration time
feat(destinations)!: Lock v1 schema layout — breaking change
```

**Breaking changes:** append `!` after the type/scope, and add a `BREAKING CHANGE:` footer in the PR body. `release-please` will bump the MAJOR version.

**Enforcement:** the `Lint PR Title` workflow (`.github/workflows/commitlint.yml`) validates the PR title on every pull request. CI fails if the title does not conform.

**Work in progress:** PR titles prefixed with `WIP:` or `[WIP]` skip validation. Remove the prefix before marking ready for review.

### Branch Naming

Use prefixed branch names (style only — release-please does not parse them):

- `feat/csv-export-destination`
- `fix/background-sync-timing`
- `docs/update-setup-guide`

## Making Changes

1. **Fork the repository** and create a branch from `main`.
2. **Make your changes** following the code style guidelines above.
3. **Write or update tests** for any logic changes.
4. **Test locally** -- build the iOS app, run the test suite, verify HealthKit integration on a real device if relevant.
5. **Commit** with clear, imperative-mood messages.
6. **Open a pull request** against `main`.

## Adding a New Destination

Adding a new sync destination is the most common type of contribution. See the full step-by-step guide at [docs/adding-a-destination.md](docs/adding-a-destination.md).

The short version:

1. Create a new Swift file in `ios/HealthPush/Sources/Destinations/`.
2. Implement the `SyncDestination` protocol.
3. Register the destination in `DestinationManager`.
4. Add a configuration UI in `Views/Screens/`.
5. Write tests.
6. Update documentation.

## Running Tests

### iOS Unit Tests

```bash
cd ios/HealthPush
xcodegen
xcodebuild test \
  -project HealthPush.xcodeproj \
  -scheme HealthPush \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Or use Xcode: `Cmd+U` to run all tests.

### Home Assistant Integration Tests

```bash
cd integrations/homeassistant
python -m pytest
```

### What to Test

- **Destinations**: Test `sync()` and `testConnection()` with mocked network responses.
- **Models**: Test data transformations and encoding/decoding.
- **Services**: Test HealthKit query construction and background task scheduling logic.
- **Views**: Provide SwiftUI previews for visual verification. Snapshot tests are a welcome addition.

## Pull Request Process

1. **Fill out the PR template** completely. Describe what changed and why.
2. **Ensure CI passes** -- all tests must pass, and lint must be clean.
3. **Keep PRs focused** -- one feature or fix per PR. Large PRs are harder to review.
4. **Update documentation** if your change affects usage, configuration, or the public API.
5. **Respond to review feedback** promptly. Discussions are part of the process.
6. **Squash and merge** is the default merge strategy.

### PR Size Guidelines

| Size   | Lines Changed | Review Time        |
| ------ | ------------- | ------------------ |
| Small  | < 100         | Same day           |
| Medium | 100 - 400     | 1-2 days           |
| Large  | 400+          | Consider splitting |

## Reporting Issues

### Bug Reports

Use the [bug report template](https://github.com/danburtenshaw/HealthPush/issues/new?template=bug_report.yml). Include:

- Your iOS version and device model
- The app version (from Settings)
- Steps to reproduce the issue
- What you expected to happen
- What actually happened
- Any relevant logs or screenshots

### Feature Requests

Use the [feature request template](https://github.com/danburtenshaw/HealthPush/issues/new?template=feature_request.yml). Include:

- A clear description of the problem you want solved
- Your proposed solution (if any)
- Whether this involves a new destination type

### Security Issues

If you discover a security vulnerability, **do not** open a public issue. Instead, email the maintainers directly. Details will be in a `SECURITY.md` file (coming soon).

## Questions?

If you are unsure about something, open a [discussion](https://github.com/danburtenshaw/HealthPush/discussions) or comment on a relevant issue. There are no dumb questions -- the goal is to make contributing as smooth as possible.

---

Thank you for helping make HealthPush better. Every contribution, no matter the size, is valued.
