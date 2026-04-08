# HealthPush Dependency Policy

HealthPush takes supply-chain security and auditability seriously. This document describes the tiered allowlist that governs every dependency in the iOS app, internal packages, and the Home Assistant integration.

## Principle

> Keep the dependency graph minimal, auditable, and aligned with Apple's own stewardship. Every dependency is a trust delegation — we only delegate when rolling our own would be *less* secure.

## Tiers

### Tier 0 — Apple system frameworks

Unlimited. These ship with iOS/macOS and have no separate supply chain risk.

- `HealthKit`, `SwiftUI`, `SwiftData`, `BackgroundTasks`, `CryptoKit`, `URLSession`, `UserNotifications`, `os.Logger`, `Combine`, `Foundation`, `CoreLocation`, etc.

### Tier 1 — Apple-stewarded / Swift Server Workgroup packages

Allowlisted by **exact repository URL** in `scripts/check-no-third-party-deps.sh`. These are effectively Apple code shipped as Swift packages. Current members:

| Package                                                       | Role             | Why allowlisted                                                                                                                              |
| ------------------------------------------------------------- | ---------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| [`apple/swift-crypto`](https://github.com/apple/swift-crypto) | `Crypto` library | Used by `HealthPushStorageCore` to provide a stable crypto API across Apple and non-Apple platforms. Apple-maintained. Already in the graph. |
| [`apple/swift-asn1`](https://github.com/apple/swift-asn1)     | ASN.1 codec      | Transitive dependency of `swift-crypto`. Apple-maintained.                                                                                   |

Adding a new Tier 1 package requires updating the allowlist in the check script and this table in the same PR.

Packages that **could** become Tier 1 when and if they're needed (not added pre-emptively):

- `apple/swift-log`
- `apple/swift-async-algorithms`
- `apple/swift-collections`
- `apple/swift-http-types`
- `apple/swift-atomics`
- `apple/swift-system`

### Tier 2 — Security-critical packages with strong pedigree

Currently empty. Added case-by-case when rolling our own would be *less* secure than using the library. Every Tier 2 addition requires:

1. A written justification in this file explaining why the dep is necessary and why rolling our own would be a worse outcome.
2. Approval from the `privacy-reviewer` subagent on the introducing PR (see `.claude/agents/privacy-reviewer.md`).
3. An explicit allowlist entry in `scripts/check-no-third-party-deps.sh`.
4. An entry in every release SBOM.
5. Renovate coverage.
6. A vendor health check: last commit < 90 days, security advisory history, maintainer reputation.

Planned Tier 2 additions (not yet in the graph):

| Package                                                       | When it would be added                                           | Rationale                                                                                                                                                                                                                                                                                                                        |
| ------------------------------------------------------------- | ---------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`openid/AppAuth-iOS`](https://github.com/openid/AppAuth-iOS) | When Google Drive or Google Sheets destinations ship (post v1.0) | Rolling your own OAuth2 PKCE client is a known CVE farm — redirect URI validation, token leakage, refresh token races, state parameter handling, timing attacks. `AppAuth-iOS` is the canonical OAuth2 library from the OpenID Foundation (the same group that authored the spec). Apache-2.0. Used by Google's own sample apps. |

### Tier 3 — Everything else

**Forbidden by default.** This includes:

- Analytics, telemetry, and crash reporting SDKs (Firebase, Sentry, Bugsnag, etc.).
- Convenience networking libraries (Alamofire, Moya, etc.).
- UI convenience libraries (SnapKit, RxSwift, RxCocoa, etc.).
- Test frameworks beyond XCTest and Swift Testing (Quick, Nimble, SwiftCheck, SnapshotTesting, etc.).
- ORMs, JSON helpers, and other "quality-of-life" libraries the standard library already covers.

Proposing a Tier 3 → Tier 2 promotion requires the same process as a new Tier 2 addition plus an explicit maintainer decision that the benefit outweighs the supply chain cost.

## iOS app target (`ios/HealthPush/project.yml`)

**Zero third-party dependencies of any kind**, including Tier 1. The iOS app target consumes Tier 1 packages only transitively via internal packages under `packages/`.

This is enforced by `scripts/check-no-third-party-deps.sh`, which runs in the `Lint & Guards` workflow on every push and pull request.

## Internal Swift packages (`packages/**`)

- `packages/HealthPushStorageCore/Package.swift`: may depend on Tier 0 and Tier 1 packages only.
- Any Tier 2 additions require a separate PR through the full process above.

## Home Assistant integration (`integrations/homeassistant/`)

The Python side is governed by Home Assistant's own `manifest.json` `requirements` field, which must remain **empty** — the integration may only depend on packages that are already part of Home Assistant Core. External PyPI dependencies require a separate review and a very good reason.

Dev-time tooling (ruff, mypy, bandit, pytest-cov, etc., pinned in `requirements_dev.txt`) is **not** part of the shipped integration and is out of scope for this policy.

## Enforcement

1. `scripts/check-no-third-party-deps.sh` — runs on every push/PR via `.github/workflows/lint.yml`, fails the build on any unexpected dependency.
2. `.github/workflows/dependency-review.yml` — blocks PRs that introduce moderate+ severity vulnerabilities or licenses outside the allow-list.
3. Renovate — configured in `renovate.json` for all ecosystems including `swift`. GitHub's Dependabot **security alerts** remain enabled at the repository level so Renovate can react to GHSA advisories via its `vulnerabilityAlerts` feature, but Dependabot version updates are disabled in favour of Renovate to avoid duplicate PRs.
4. `privacy-reviewer` subagent — `.claude/agents/privacy-reviewer.md` audits any PR that changes the dependency graph.
5. Release SBOM — generated on every release tag and attached to the GitHub Release (planned).

## Revising this policy

Changes to this document or to the allowlist in `check-no-third-party-deps.sh` require:

1. A PR with the proposed change.
2. Approval from the project lead (see `GOVERNANCE.md`).
3. An update to `CLAUDE.md` / `AGENTS.md` if the architecture principle changes.
