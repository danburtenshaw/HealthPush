# Getting Help with HealthPush

Thanks for using HealthPush. Here's how to get the right kind of help for the right kind of question.

## 📖 Read the docs first

Most questions are answered in the docs:

- **[Quickstart](docs/quickstart.mdx)** — set up the app and your first destination.
- **[Home Assistant setup](docs/setup-home-assistant.mdx)** — configure the HA integration end-to-end.
- **[Amazon S3 setup](docs/setup-amazon-s3.mdx)** — configure S3 or S3-compatible storage.
- **[Sync behavior](docs/sync-behavior.mdx)** — what to expect from background sync and why iOS decides when.
- **[Privacy & open source](docs/privacy-and-open-source.mdx)** — the privacy architecture and what HealthPush does and doesn't do.
- **[Architecture](docs/architecture.md)** — how the app is structured if you want to contribute.

## 💬 Ask a question

For general questions, configuration help, setup troubleshooting, or feature ideas, please use [**GitHub Discussions**](https://github.com/danburtenshaw/HealthPush/discussions). The Discussions tab has dedicated categories for:

- **Q&A** — "how do I configure X?", "why isn't sync running?", "what does this error mean?"
- **Ideas** — feature proposals and open-ended suggestions.
- **Show and tell** — dashboards, integrations, or automations you've built on top of HealthPush.
- **Announcements** — release notes and project updates.

Discussions is much better than filing an issue for this kind of thing: answers are searchable, the community can help, and issues stay focused on bugs and confirmed work.

## 🐛 Report a bug

If you believe you've found a bug, please [open an issue using the Bug Report template](https://github.com/danburtenshaw/HealthPush/issues/new?template=bug_report.yml). Include:

- What you expected to happen.
- What actually happened.
- Reproduction steps.
- Your iOS version, HealthPush version, device model, and HA version if applicable.
- Any relevant logs from Console.app (filter by "HealthPush") or Home Assistant.

## 🔒 Report a security vulnerability

**Do not open a public issue for security problems.**

Use [GitHub Security Advisories](https://github.com/danburtenshaw/HealthPush/security/advisories/new) to report the vulnerability privately. Full details on scope and disclosure are in [`SECURITY.md`](SECURITY.md).

## 🛠 Propose a new destination

Use the [Destination Request template](https://github.com/danburtenshaw/HealthPush/issues/new?template=destination_request.yml). Destination proposals are evaluated against the criteria in [`GOVERNANCE.md`](GOVERNANCE.md).

## 🙋 Contribute

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the development environment, commit style, and pull request process.

## 📬 What HealthPush doesn't provide

HealthPush is a free, open-source project. There is no commercial support contract, no SLA, and no guaranteed response time. Maintainers respond as time allows. If you need a particular fix urgently, the fastest path is usually a well-scoped PR.

There is also no HealthPush backend, no account system, and no telemetry — so if you're asking "can you check what my device did", the answer is "no, only you can, on your device."
