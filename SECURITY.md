# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in HealthPush, **please do not open a public GitHub issue.**

Instead, report it privately by emailing the maintainers or using GitHub's [private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability) feature on this repository.

Please include:

- A description of the vulnerability
- Steps to reproduce the issue
- The potential impact
- Any suggested fixes (if you have them)

We will acknowledge your report within 48 hours and aim to provide a fix or mitigation within 7 days for critical issues.

## Supported Versions

| Component | Version | Supported |
|---|---|---|
| iOS App | latest | Yes |
| HA Integration | latest | Yes |

## Security Design

HealthPush is designed with security and privacy as core principles:

- **No third-party dependencies** in the iOS app, minimizing supply chain risk
- **No remote servers** -- data flows directly from the device to configured destinations
- **No analytics or telemetry** -- nothing phones home
- **Local-only storage** -- non-secret configuration is stored on-device via SwiftData and credentials are stored in Keychain
- **Direct connections only** -- data is sent directly to user-configured destinations, with no HealthPush relay service
- **Minimal permissions** -- the app requests only the HealthKit permissions it needs

## Scope

The following are in scope for security reports:

- Unintended data leakage from the iOS app
- Authentication bypass in the Home Assistant integration
- Insecure data transmission
- Vulnerabilities in webhook handling
- Privacy violations (data sent to unintended destinations)

The following are out of scope:

- Issues requiring physical access to an unlocked device
- Issues in third-party software (Home Assistant core, iOS itself)
- Social engineering attacks
