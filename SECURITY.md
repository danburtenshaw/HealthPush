# Security Policy

HealthPush is a privacy-first, open-source iOS app and Home Assistant integration. We take security reports seriously and will work with researchers in good faith.

## Supported Versions

| Component                       | Version                   | Supported                                           |
| ------------------------------- | ------------------------- | --------------------------------------------------- |
| iOS App                         | latest App Store build    | ✅                                                  |
| iOS App                         | previous minor release    | ✅ for critical issues during a 30-day grace window |
| Home Assistant Integration      | latest tag + HACS default | ✅                                                  |
| `HealthPushStorageCore` package | latest tag                | ✅                                                  |

Older versions are unsupported. Please reproduce issues on the latest release before reporting.

## Reporting a Vulnerability

**Do not open a public GitHub issue for security problems.**

Please report privately via **[GitHub Security Advisories](https://github.com/danburtenshaw/HealthPush/security/advisories/new)** on this repository. This routes directly to the maintainers and keeps the report confidential until a fix is ready.

If GitHub Security Advisories is unavailable, you may email the maintainers at:

> **<security@healthpush.app>**

Please include:

- A description of the vulnerability and the affected component.
- Reproduction steps, ideally with a proof-of-concept.
- The potential impact (what an attacker could achieve).
- Your assessment of severity (optional).
- Suggested mitigations (optional).

### PGP / age encryption

GitHub Security Advisories encrypts your report in transit and at rest, which is the recommended path. If you need to send mail with additional encryption, ask via GitHub Security Advisories first and we'll coordinate a key exchange.

### What to expect

| When                | What                                                                                                                                |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| Within **48 hours** | We acknowledge receipt of the report.                                                                                               |
| Within **7 days**   | Initial assessment — severity, likely fix timeline, any clarifying questions.                                                       |
| Within **90 days**  | Fix released, advisory published, and credit (if desired) given. Critical issues are addressed faster — typically within 7-14 days. |

We follow **90-day coordinated disclosure**. If we cannot ship a fix within 90 days we will coordinate a mutually acceptable extension with the reporter.

## Safe Harbor

We will not pursue legal action against security researchers who:

- Act in good faith to discover and report vulnerabilities.
- Only interact with accounts and data that belong to them or that they have explicit permission to test.
- Do not exfiltrate user data, degrade service availability, or publish details of unpatched vulnerabilities.
- Give us a reasonable time window to respond before any public disclosure.
- Comply with all applicable laws.

If you are unsure whether your activity falls within this safe harbor, please contact us before proceeding.

## Scope

**In scope:**

- The HealthPush iOS app (sources under `ios/HealthPush/`).
- The Home Assistant custom integration (`integrations/homeassistant/custom_components/healthpush/`).
- The `HealthPushStorageCore` Swift package.
- HealthPush's GitHub Actions workflows under `.github/workflows/` (e.g., insufficient permissions, command injection, supply chain weakness).
- HealthPush's release artefacts and installation pathways.

**Out of scope:**

- Issues in Apple frameworks (HealthKit, SwiftUI, SwiftData, URLSession, etc.) — report those to Apple directly.
- Issues in Home Assistant Core itself — report those to Home Assistant.
- Issues requiring physical access to an unlocked device.
- Social engineering attacks against users or maintainers.
- Denial of service attacks against a user's own destinations.
- Spam or missing rate limiting on informational endpoints.
- Self-XSS in local debugging views.
- Vulnerabilities in unsupported / older versions.
- Issues requiring an attacker to already have full control of the device or the user's destination credentials.

## Security Design

HealthPush is designed with security and privacy as core principles:

- **Tiered, audited dependencies** — the iOS app and internal packages use only Apple system frameworks, Apple-stewarded Swift Server Workgroup packages, and specific security-critical libraries with strong pedigree. See [`docs/dependencies.md`](docs/dependencies.md) for the allowlist. Analytics, telemetry, crash reporters, and convenience libraries are forbidden.
- **No HealthPush-operated backend** — data flows directly from the device to user-configured destinations. There is no relay, no account system, no telemetry.
- **Direct connections only** — destinations receive data from the user's device over TLS wherever supported. See the Home Assistant section below for the LAN HTTP policy.
- **Local-first storage** — non-secret configuration is stored on-device via SwiftData. Credentials are stored in the Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- **Read-only HealthKit** — the app requests read permissions only.
- **Minimal entitlements** — HealthKit, background modes, and nothing else.
- **SHA-pinned Actions** — every GitHub Action is pinned to a full commit SHA, not a floating tag.

### Home Assistant LAN networking policy

HealthPush allows `http://` connections **only** to Home Assistant instances on private networks:

- RFC1918 ranges: `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`
- `.local` / `.lan` / `.home.arpa` domains

Any other `http://` destination is refused. The Home Assistant setup screen shows a persistent warning banner when the user chooses an HTTP URL. HTTPS is strongly preferred and is the default suggestion.

This policy exists because forcing HTTPS on LAN HA installations would push users toward public port forwarding, which is a worse outcome for privacy. See [`docs/setup-home-assistant.mdx`](docs/setup-home-assistant.mdx) for the user-facing documentation.

## Security Contact

Primary: [GitHub Security Advisories](https://github.com/danburtenshaw/HealthPush/security/advisories/new)

Project lead: [@danburtenshaw](https://github.com/danburtenshaw)

See [`MAINTAINERS.md`](MAINTAINERS.md) for the full maintainer list.
