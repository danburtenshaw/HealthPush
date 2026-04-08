# HealthPush Maintainers

This file lists the people who currently maintain HealthPush.
Governance, decision-making, and how to become a maintainer are described in [`GOVERNANCE.md`](GOVERNANCE.md).

## Project Lead

- **Dan Burtenshaw** — [@danburtenshaw](https://github.com/danburtenshaw)
  - Project direction, releases, dependency policy, architecture.

## Active Maintainers

| Maintainer     | GitHub                                              | Areas of ownership                                            |
| -------------- | --------------------------------------------------- | ------------------------------------------------------------- |
| Dan Burtenshaw | [@danburtenshaw](https://github.com/danburtenshaw)  | iOS app, Home Assistant integration, docs, release management |

## Areas of Ownership

These areas describe which maintainer is the first reviewer for changes in each part of the repo. Any maintainer may review any change; this is just a default routing.

| Area                           | Path                                             | Primary owner(s) |
| ------------------------------ | ------------------------------------------------ | ---------------- |
| iOS app                        | `ios/HealthPush/`                                | @danburtenshaw   |
| Fastlane + release automation  | `fastlane/`, `.github/workflows/release-*.yml`   | @danburtenshaw   |
| Home Assistant integration     | `integrations/homeassistant/`                    | @danburtenshaw   |
| Storage core package           | `packages/HealthPushStorageCore/`                | @danburtenshaw   |
| Shared docs + architecture     | `docs/`, `CLAUDE.md`, `AGENTS.md`                | @danburtenshaw   |
| CI/CD and repo tooling         | `.github/`, `scripts/`, `.lefthook.yml`          | @danburtenshaw   |

When the maintainer team grows, this table should be updated before `CODEOWNERS` references any new handles.

## Emeritus Maintainers

None yet.

## Contact

For routine questions, use [GitHub Discussions](https://github.com/danburtenshaw/HealthPush/discussions).
For security reports, use [GitHub Security Advisories](https://github.com/danburtenshaw/HealthPush/security/advisories/new) — see [`SECURITY.md`](SECURITY.md).
