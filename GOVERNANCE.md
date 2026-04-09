# HealthPush Governance

This document describes how decisions are made in the HealthPush project. It is intentionally lightweight — HealthPush is a small open-source project and the governance model should match that reality.

## Project Mission

HealthPush exists to give iPhone users a trustworthy, open-source path to export their Apple Health data to destinations **they control**. The project is privacy-first, local-first, and account-free. There is no HealthPush-operated backend and there never will be.

## Principles

1. **User data sovereignty comes first.** Any decision that would weaken the user's control over their own health data is rejected.
2. **Minimal attack surface.** Dependencies, entitlements, and network surface are kept as small as possible. See [`docs/dependencies.md`](docs/dependencies.md) for the tiered allowlist policy.
3. **Direct delivery.** The iOS app talks to user-configured destinations directly. HealthPush does not operate relay services and does not accept proposals that require one.
4. **Open and auditable.** All code that touches user data is open source and can be reviewed by anyone.
5. **Destination-agnostic architecture.** No single destination's quirks are allowed to leak into shared sync infrastructure.

## Maintainers

The current maintainer list lives in [`MAINTAINERS.md`](MAINTAINERS.md). Maintainers have commit access to the repository and are responsible for code review, releases, and triage.

## Decision Making

### Lazy Consensus

Most decisions are made by **lazy consensus**. A maintainer proposes a change in a PR or issue; if no other maintainer objects within a reasonable period (typically 72 hours for PRs, 7 days for architectural changes), the proposal is considered accepted.

### Objection Resolution

If a maintainer objects to a proposal:

1. The author and the objector discuss on the PR/issue and try to reach agreement.
2. If they can't agree, any other maintainer may weigh in. A rough majority of responding maintainers carries the decision.
3. If there is still no consensus, the project lead (currently `@danburtenshaw`) makes the tie-breaking call.

### Project Lead

The project lead has the final word on:

- Inclusion or rejection of new destinations.
- Changes to the core architecture principles in `CLAUDE.md` / `AGENTS.md`.
- Changes to the dependency allowlist in `docs/dependencies.md`.
- Releases tagged `1.0.0` and later majors.

The project lead is `@danburtenshaw` at launch. If the role transitions, this document will be updated and the change announced in GitHub Discussions.

## Destination Inclusion Criteria

A new sync destination is accepted if it meets **all** of the following:

- [ ] **User-owned.** The user stands up the destination themselves — no HealthPush-operated account or relay.
- [ ] **Direct delivery.** The iOS app talks to the destination directly, without a middle service.
- [ ] **Test fixture.** The destination can be exercised in CI via a Docker container or a scoped fixture account.
- [ ] **Maintainer willing to own it.** At least one maintainer commits to reviewing and fixing bugs for the integration.
- [ ] **Dependency policy compliant.** Any new library required by the destination is reviewed under the tiered allowlist in `docs/dependencies.md`.
- [ ] **Schema compatible.** The destination can ingest the frozen `v1` schema contract without forcing changes to shared models.

Maintainers may reject otherwise-compliant destinations if the integration would add disproportionate maintenance burden or if a better alternative already exists.

## Becoming a Maintainer

There is no fixed path, but the following are signals that a contributor is ready:

- Multiple accepted PRs over at least a few months.
- Demonstrated understanding of the privacy-first, destination-agnostic architecture.
- Willingness to review other contributors' PRs.
- Agreement with the project's principles.

Existing maintainers nominate and vote on new maintainers by lazy consensus.

## Commit and Release Policy

- **Conventional Commits** are required for all PR titles — see [`CONTRIBUTING.md`](CONTRIBUTING.md).
- **Squash-merge only.** The PR title becomes the commit message on `main`.
- **Two independent release trains** — iOS and HA integration — are versioned and released independently. They are never bundled.
- **release-please** opens per-component release PRs automatically based on Conventional Commit history.

## Security

Security reports are handled privately — see [`SECURITY.md`](SECURITY.md) for the disclosure process.

## Code of Conduct

All participation in the project is governed by our [Code of Conduct](CODE_OF_CONDUCT.md). Violations are handled by the maintainer team.

## Amending This Document

Changes to this document require a PR, a 7-day review period, and approval from the project lead.
