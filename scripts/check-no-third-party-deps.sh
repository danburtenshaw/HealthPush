#!/usr/bin/env bash
#
# check-no-third-party-deps.sh
#
# Enforces HealthPush's tiered dependency policy (see docs/dependencies.md and
# CLAUDE.md "Architecture Principles" #2).
#
# Tiered allowlist:
#
#   Tier 0 — Apple system frameworks (HealthKit, SwiftUI, SwiftData,
#            CryptoKit, URLSession, BGTaskScheduler, os.Logger, etc.).
#            Not expressed in SPM; never flagged.
#
#   Tier 1 — Apple-stewarded / Swift Server Workgroup packages.
#            Allowlisted by exact repo URL below.
#
#   Tier 2 — Security-critical packages with strong pedigree, added
#            only with justification in docs/dependencies.md.
#            Currently empty.
#
#   Tier 3 — Everything else: forbidden.
#
# The iOS app target (ios/HealthPush/project.yml) must have zero SPM
# dependencies of any kind. Tier 1 packages are only permitted inside
# the internal packages/ tree.
#
# The script also blocks CocoaPods and Carthage outright.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

STATUS=0
RED=$'\033[0;31m'
YELLOW=$'\033[0;33m'
GREEN=$'\033[0;32m'
NC=$'\033[0m'

log_err() { printf "%sERROR%s %s\n" "$RED" "$NC" "$*" >&2; STATUS=1; }
log_warn() { printf "%sWARN%s  %s\n" "$YELLOW" "$NC" "$*" >&2; }
log_ok() { printf "%sOK%s    %s\n" "$GREEN" "$NC" "$*"; }

# ── Tier 1: allowlist by exact repo URL (lowercased for comparison) ─────
# Add a new entry only after writing a justification in docs/dependencies.md.
TIER1_ALLOWLIST=(
  "https://github.com/apple/swift-crypto.git"
  "https://github.com/apple/swift-crypto"
  # swift-asn1 is a transitive dep of swift-crypto (Apple-stewarded)
  "https://github.com/apple/swift-asn1.git"
  "https://github.com/apple/swift-asn1"
)

# Tier 2 is empty at launch. AppAuth-iOS will be added here when Google
# destinations land (post v1.0).
TIER2_ALLOWLIST=()

ALL_ALLOWED=(
  "${TIER1_ALLOWLIST[@]+${TIER1_ALLOWLIST[@]}}"
  "${TIER2_ALLOWLIST[@]+${TIER2_ALLOWLIST[@]}}"
)

is_allowed() {
  local url_lower
  url_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  if [ "${#ALL_ALLOWED[@]}" -eq 0 ]; then
    return 1
  fi
  for allowed in "${ALL_ALLOWED[@]}"; do
    if [ "$url_lower" = "$allowed" ]; then
      return 0
    fi
  done
  return 1
}

# ── 1. iOS app target: zero third-party deps, period ───────────────────
IOS_PROJECT_YML="ios/HealthPush/project.yml"
if [ -f "$IOS_PROJECT_YML" ]; then
  # xcodegen `packages:` block at top level declares SPM deps for the app.
  if awk '/^packages:/{flag=1; next} /^[a-zA-Z]/{flag=0} flag && /url:/{print}' "$IOS_PROJECT_YML" | grep -q .; then
    log_err "$IOS_PROJECT_YML has a 'packages:' block with SPM dependencies."
    log_err "The iOS app target must have zero third-party SPM dependencies."
    log_err "If you need a Tier 1 package, add it to an internal package in packages/ instead."
  else
    log_ok "$IOS_PROJECT_YML has no SPM dependencies"
  fi
fi

# ── 2. Internal packages: only allowlisted URLs ────────────────────────
while IFS= read -r manifest; do
  [ -z "$manifest" ] && continue
  # Extract .package(url: "...") URLs.
  urls=$(
    grep -Eo '\.package\([^)]*url:[[:space:]]*"[^"]+"' "$manifest" \
      | sed -E 's/.*url:[[:space:]]*"([^"]+)".*/\1/' || true
  )
  if [ -z "$urls" ]; then
    log_ok "$manifest has no SPM dependencies"
    continue
  fi
  while IFS= read -r url; do
    [ -z "$url" ] && continue
    if is_allowed "$url"; then
      log_ok "$manifest: allowlisted → $url"
    else
      log_err "$manifest: non-allowlisted dependency → $url"
      log_err "  See docs/dependencies.md for the tiered allowlist."
      log_err "  To add a new dependency, update TIER1/TIER2 in this script"
      log_err "  and document the justification in docs/dependencies.md."
    fi
  done <<<"$urls"
done < <(find packages -name 'Package.swift' 2>/dev/null || true)

# ── 3. Package.resolved cross-check (catch transitive surprises) ───────
while IFS= read -r resolved; do
  [ -z "$resolved" ] && continue
  # Extract every "location": "..." line from Package.resolved (v2/v3).
  locations=$(grep -Eo '"(location|repositoryURL)"[[:space:]]*:[[:space:]]*"[^"]+"' "$resolved" \
    | sed -E 's/.*:[[:space:]]*"([^"]+)".*/\1/' | sort -u || true)
  if [ -z "$locations" ]; then
    continue
  fi
  while IFS= read -r loc; do
    [ -z "$loc" ] && continue
    if is_allowed "$loc"; then
      :
    else
      log_err "$resolved: non-allowlisted package locked → $loc"
    fi
  done <<<"$locations"
done < <(find packages -name 'Package.resolved' 2>/dev/null || true)

# ── 4. Block CocoaPods / Carthage outright ─────────────────────────────
if find . -name 'Podfile' -not -path './.git/*' -not -path './.local/*' 2>/dev/null | grep -q .; then
  log_err "Podfile detected — CocoaPods is forbidden."
fi
if find . -name 'Cartfile' -not -path './.git/*' -not -path './.local/*' 2>/dev/null | grep -q .; then
  log_err "Cartfile detected — Carthage is forbidden."
fi

if [ "$STATUS" -eq 0 ]; then
  printf "\n%sdependency policy: PASS%s\n" "$GREEN" "$NC"
else
  printf "\n%sdependency policy: FAIL%s\n" "$RED" "$NC"
fi
exit "$STATUS"
