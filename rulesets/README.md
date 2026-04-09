# GitHub Rulesets

This directory holds repository rulesets as JSON files, imported into GitHub via the API. The JSON is the source of truth; the UI is secondary.

## Current state

**No ruleset is currently applied to `main`.** Direct commits and force-pushes are technically allowed, though the project convention is to squash-merge via PRs. Apply `main-protection.json` when you're ready to enforce that convention.

## Importing

Find any existing rulesets first:

```bash
gh api /repos/danburtenshaw/HealthPush/rulesets
```

Create the ruleset:

```bash
gh api --method POST \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  /repos/danburtenshaw/HealthPush/rulesets \
  --input rulesets/main-protection.json
```

Update an existing ruleset (replace `RULESET_ID` with the value from the list call above):

```bash
gh api --method PUT \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  /repos/danburtenshaw/HealthPush/rulesets/RULESET_ID \
  --input rulesets/main-protection.json
```

Delete it:

```bash
gh api --method DELETE /repos/danburtenshaw/HealthPush/rulesets/RULESET_ID
```

## What `main-protection.json` does

- Requires pull requests for all changes to `main`.
- Required approving reviews: **0** — solo-maintainer friendly. Bump to `1` when another maintainer joins.
- Requires **code owner review** (via CODEOWNERS).
- Requires **linear history** — squash-merge only (`allowed_merge_methods: ["squash"]`).
- Requires **signed commits**.
- Dismisses stale reviews when a push happens after approval.
- Requires all listed status checks to pass, up-to-date with base branch.
- Blocks force-push and branch deletion.
- Empty `bypass_actors` — nobody can bypass, not even the project lead.

## When to apply

Apply after:

1. The initial scaffolding commit has landed on `main`.
2. All workflows referenced in `required_status_checks` have run at least once, so GitHub knows the check names exist. The listed contexts must match the `name:` field of each job in its workflow YAML — if a job is renamed, update this file before re-applying.

## Separate ruleset for release tags

A future `rulesets/tag-protection.json` will handle `ios-v*` and `ha-v*` tags with deployment environment gates for App Store submission. It is not included in the initial tooling pass.
