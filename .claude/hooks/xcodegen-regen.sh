#!/usr/bin/env bash
# PostToolUse hook: regenerate HealthPush.xcodeproj whenever project.yml is edited.
#
# project.yml is the source of truth; HealthPush.xcodeproj is gitignored and
# can drift stale between sessions. This hook keeps them in lockstep so
# `xcodebuild` always sees the current target/source configuration.
#
# Hook contract: receives JSON on stdin describing the tool invocation.
# We only care about .tool_input.file_path. Any non-matching path is a no-op.

set -euo pipefail

payload=$(cat)

# jq may not be present on a fresh contributor machine — fail open.
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

file_path=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty')

case "$file_path" in
  */ios/HealthPush/project.yml|ios/HealthPush/project.yml)
    repo_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
    if command -v xcodegen >/dev/null 2>&1; then
      (cd "$repo_root/ios/HealthPush" && xcodegen) >&2
      echo "[claude-hook] regenerated HealthPush.xcodeproj from project.yml" >&2
    else
      echo "[claude-hook] project.yml changed but xcodegen not on PATH — run it manually" >&2
    fi
    ;;
esac
