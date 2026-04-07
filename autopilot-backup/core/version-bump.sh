#!/usr/bin/env bash
# ============================================================
# Autopilot Product Version Bump
#
# Usage: ./scripts/version-bump.sh <patch|minor|major>
#
# Rules:
#   - Patch goes 0-9 only (never X.Y.10)
#   - After X.Y.9, auto-promotes to X.(Y+1).0
#   - Updates version.json
#   - Validates result
# ============================================================
set -euo pipefail

BUMP_TYPE="${1:-patch}"
VERSION_FILE="version.json"

if [ ! -f "$VERSION_FILE" ]; then
  echo "::error ::version.json not found"
  exit 1
fi

CURRENT=$(jq -r '.version' "$VERSION_FILE")
if [ -z "$CURRENT" ] || [ "$CURRENT" = "null" ]; then
  echo "::error ::version.json missing version field"
  exit 1
fi

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"

case "$BUMP_TYPE" in
  patch)
    if [ "$PATCH" -ge 9 ]; then
      # X.Y.9 → X.(Y+1).0 — never X.Y.10
      MINOR=$((MINOR + 1))
      PATCH=0
      echo "Note: patch overflow 9→0, minor bumped"
    else
      PATCH=$((PATCH + 1))
    fi
    ;;
  minor)
    MINOR=$((MINOR + 1))
    PATCH=0
    ;;
  major)
    MAJOR=$((MAJOR + 1))
    MINOR=0
    PATCH=0
    ;;
  *)
    echo "::error ::Invalid bump type: $BUMP_TYPE (use patch|minor|major)"
    exit 1
    ;;
esac

NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"

# Validate the new version
if ! echo "$NEW_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "::error ::Generated invalid version: $NEW_VERSION"
  exit 1
fi
if [ "$PATCH" -gt 9 ]; then
  echo "::error ::Patch overflow: $PATCH > 9"
  exit 1
fi

# Update version.json
jq --arg v "$NEW_VERSION" '.version = $v' "$VERSION_FILE" > /tmp/version-bump.json
mv /tmp/version-bump.json "$VERSION_FILE"

echo "Bumped: $CURRENT → $NEW_VERSION ($BUMP_TYPE)"
echo "version=$NEW_VERSION"
echo "previous=$CURRENT"
