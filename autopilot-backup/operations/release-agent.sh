#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# release-agent.sh
# Replaces: .github/workflows/release-agent.yml
#
# Full release pipeline for the AGENT component (workspace ws-default).
# Executes the complete release flow:
#   1. Source core scripts (state-manager, session-guard)
#   2. Resolve workspace configuration
#   3. Acquire session lock
#   4. Read current release state
#   5. Read package.json from corporate repo via MCP
#   6. Bump version (0-9 patch rule: X.Y.9 -> X.(Y+1).0)
#   7. Update package.json via MCP push
#   8. Poll CI status ("Esteira de Build NPM")
#   9. Call promote-cap.sh
#  10. Update release state on autopilot-state
#  11. Write audit entry
#  12. Release lock
#
# Tag format: {version}-{short_sha} (e.g., 2.1.1-3a58260)
#
# Corporate repo: bbvinet/psc-sre-automacao-agent
# Component: agent
# Workspace: ws-default (Getronics)
#
# Usage:
#   ./release-agent.sh [--workspace <ws_id>] [--version <version>] [--dry-run]
#
# MCP tools used:
#   - mcp__github__get_file_contents   (read state, package.json, workspace config)
#   - mcp__github__create_or_update_file (write state, push package.json)
#   - mcp__github__list_commits         (get latest SHA for tag)
#
# Schema: schemas/release-state.schema.json (schemaVersion: 2)
# Release state fields:
#   required: schemaVersion (2), component ("agent"), workspaceId
#   status: idle | releasing | promoted | failed
#   ciResult: success | failure | unknown | no-ci | timeout
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source core modules
source "${SCRIPT_DIR}/../core/state-manager.sh"

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
SCHEMA_VERSION=2
COMPONENT="agent"
DEFAULT_WORKSPACE="ws-default"
CORPORATE_REPO="bbvinet/psc-sre-automacao-agent"
CI_WORKFLOW_NAME="Esteira de Build NPM"
CI_POLL_INTERVAL=120   # seconds between CI polls
CI_POLL_MAX=20         # max polls (~40 minutes)

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
WORKSPACE_ID="${WORKSPACE_ID:-$DEFAULT_WORKSPACE}"
TARGET_VERSION=""
DRY_RUN=false

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace) WORKSPACE_ID="$2"; shift 2 ;;
    --version)   TARGET_VERSION="$2"; shift 2 ;;
    --dry-run)   DRY_RUN=true; shift ;;
    *) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Bump version following 0-9 patch rule:
#   X.Y.Z where Z < 9  -> X.Y.(Z+1)
#   X.Y.9              -> X.(Y+1).0
bump_version() {
  local current="$1"
  local major minor patch
  major=$(echo "$current" | cut -d. -f1)
  minor=$(echo "$current" | cut -d. -f2)
  patch=$(echo "$current" | cut -d. -f3)

  if [[ $patch -ge 9 ]]; then
    echo "${major}.$((minor + 1)).0"
  else
    echo "${major}.${minor}.$((patch + 1))"
  fi
}

# Build tag from version and SHA
# Format: {version}-{short_sha} (e.g., 2.1.1-3a58260)
build_tag() {
  local version="$1"
  local sha="$2"
  local short_sha="${sha:0:7}"
  echo "${version}-${short_sha}"
}

# Write audit entry for an operation
# MCP: mcp__github__create_or_update_file(
#   path="state/workspaces/{ws_id}/audit/release-agent-{timestamp}.json",
#   branch=autopilot-state)
write_audit_entry() {
  local action="$1"
  local detail="$2"
  local status="$3"
  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local filename="release-agent-$(date -u +%Y%m%d-%H%M%S).json"

  local audit_json
  audit_json=$(jq -n \
    --arg action "$action" \
    --arg component "$COMPONENT" \
    --arg workspaceId "$WORKSPACE_ID" \
    --arg timestamp "$timestamp" \
    --arg detail "$detail" \
    --arg status "$status" \
    --arg agent "claude-code" \
    '{
      action: $action,
      component: $component,
      workspaceId: $workspaceId,
      timestamp: $timestamp,
      detail: $detail,
      status: $status,
      agent: $agent
    }')

  write_state "$WORKSPACE_ID" "audit/${filename}" "$audit_json" \
    "audit: ${action} ${COMPONENT} for ${WORKSPACE_ID}" 2>/dev/null || \
    echo "WARN: Failed to write audit entry" >&2
}

# ---------------------------------------------------------------------------
# Step 0: Pre-release validation
# Validates token, lock state, and release state consistency before starting
# ---------------------------------------------------------------------------
pre_release_validation() {
  echo "[release-agent] Step 0: Pre-release validation..."

  # 0a. Check token availability
  local token="${BBVINET_TOKEN:-}"
  if [[ -z "$token" && -f "$HOME/.autopilot-token" ]]; then
    token=$(cat "$HOME/.autopilot-token")
  fi
  if [[ -z "$token" ]]; then
    echo "ERROR: No token available. Set BBVINET_TOKEN or ~/.autopilot-token" >&2
    exit 1
  fi

  # 0b. Test token validity
  local owner repo
  owner=$(echo "$CORPORATE_REPO" | cut -d/ -f1)
  repo=$(echo "$CORPORATE_REPO" | cut -d/ -f2)
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: token $token" "https://api.github.com/repos/${owner}/${repo}" 2>/dev/null || echo "000")
  if [[ "$http_code" != "200" ]]; then
    echo "ERROR: Token cannot access ${CORPORATE_REPO} (HTTP ${http_code})" >&2
    exit 1
  fi
  echo "[release-agent] Token valid for ${CORPORATE_REPO}"

  # 0c. Source safe-commit for Rule #0 enforcement
  if [[ -f "${SCRIPT_DIR}/../core/safe-commit.sh" ]]; then
    source "${SCRIPT_DIR}/../core/safe-commit.sh"
    echo "[release-agent] Rule #0 enforcement loaded"
  fi

  echo "[release-agent] Pre-release validation passed."
}

# ---------------------------------------------------------------------------
# Step 1: Resolve workspace
# MCP: mcp__github__get_file_contents(path="state/workspaces/{ws_id}/workspace.json")
# ---------------------------------------------------------------------------
resolve_workspace() {
  echo "[release-agent] Step 1: Resolving workspace ${WORKSPACE_ID}..."

  local ws_json
  ws_json=$(read_workspace_config "$WORKSPACE_ID" 2>/dev/null || echo "")

  if [[ -z "$ws_json" ]]; then
    echo "ERROR: Could not read workspace config for ${WORKSPACE_ID}" >&2
    exit 1
  fi

  # Extract agent-specific config
  local source_repo
  source_repo=$(echo "$ws_json" | jq -r '.agent.sourceRepo // ""' 2>/dev/null || echo "")

  if [[ -n "$source_repo" ]]; then
    CORPORATE_REPO="$source_repo"
    echo "[release-agent] Corporate repo from workspace config: ${CORPORATE_REPO}"
  fi

  echo "[release-agent] Workspace resolved: ${WORKSPACE_ID}, repo: ${CORPORATE_REPO}"
}

# ---------------------------------------------------------------------------
# Step 2: Acquire session lock
# MCP: mcp__github__create_or_update_file(
#   path="state/workspaces/{ws_id}/locks/session-lock.json",
#   branch=autopilot-state)
# ---------------------------------------------------------------------------
acquire_lock() {
  echo "[release-agent] Step 2: Acquiring session lock..."

  # Check for existing lock
  local existing_lock
  existing_lock=$(read_state "$WORKSPACE_ID" "locks/session-lock.json" 2>/dev/null || echo "")

  if [[ -n "$existing_lock" ]]; then
    local locked_by locked_at ttl_minutes
    locked_by=$(echo "$existing_lock" | jq -r '.lockedBy // "unknown"' 2>/dev/null || echo "unknown")
    locked_at=$(echo "$existing_lock" | jq -r '.lockedAt // ""' 2>/dev/null || echo "")
    ttl_minutes=$(echo "$existing_lock" | jq -r '.ttlMinutes // 30' 2>/dev/null || echo "30")

    if [[ -n "$locked_at" ]]; then
      local now_epoch lock_epoch age_minutes
      now_epoch=$(date +%s)
      lock_epoch=$(date -d "$locked_at" +%s 2>/dev/null || echo "0")
      age_minutes=$(( (now_epoch - lock_epoch) / 60 ))

      if [[ $age_minutes -lt $ttl_minutes ]]; then
        echo "ERROR: Lock held by ${locked_by} (age: ${age_minutes}m / TTL: ${ttl_minutes}m). Aborting." >&2
        exit 1
      fi
      echo "[release-agent] Existing lock expired (age: ${age_minutes}m). Overriding."
    fi
  fi

  local lock_json
  lock_json=$(jq -n \
    --arg lockedBy "claude-code" \
    --arg operation "release-agent" \
    --arg workspaceId "$WORKSPACE_ID" \
    --arg lockedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson ttlMinutes 30 \
    '{
      lockedBy: $lockedBy,
      operation: $operation,
      workspaceId: $workspaceId,
      lockedAt: $lockedAt,
      ttlMinutes: $ttlMinutes
    }')

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[release-agent] DRY-RUN: Would acquire lock"
    return
  fi

  write_state "$WORKSPACE_ID" "locks/session-lock.json" "$lock_json" \
    "lock: acquire for release-agent on ${WORKSPACE_ID}"
  echo "[release-agent] Lock acquired."
}

# ---------------------------------------------------------------------------
# Step 3: Read current release state
# MCP: mcp__github__get_file_contents(path="state/workspaces/{ws_id}/agent-release-state.json")
# ---------------------------------------------------------------------------
read_current_state() {
  echo "[release-agent] Step 3: Reading current release state..."

  local state_json
  state_json=$(read_release_state "$WORKSPACE_ID" "$COMPONENT" 2>/dev/null || echo "")

  if [[ -z "$state_json" ]]; then
    echo "[release-agent] No existing release state. Starting fresh."
    CURRENT_VERSION=""
    CURRENT_STATUS="idle"
    return
  fi

  CURRENT_VERSION=$(echo "$state_json" | jq -r '.lastVersion // ""' 2>/dev/null || echo "")
  CURRENT_STATUS=$(echo "$state_json" | jq -r '.status // "idle"' 2>/dev/null || echo "idle")

  # Guard: do not release if already in releasing state
  if [[ "$CURRENT_STATUS" == "releasing" ]]; then
    echo "WARN: Component is already in releasing state. Checking if stuck..." >&2
    local updated_at
    updated_at=$(echo "$state_json" | jq -r '.updatedAt // ""' 2>/dev/null || echo "")
    if [[ -n "$updated_at" ]]; then
      local now_epoch upd_epoch age_min
      now_epoch=$(date +%s)
      upd_epoch=$(date -d "$updated_at" +%s 2>/dev/null || echo "0")
      age_min=$(( (now_epoch - upd_epoch) / 60 ))
      if [[ $age_min -lt 60 ]]; then
        echo "ERROR: Release in progress (${age_min}m). Wait or clear the state." >&2
        exit 1
      fi
      echo "[release-agent] Previous release appears stuck (${age_min}m). Proceeding."
    fi
  fi

  echo "[release-agent] Current version: ${CURRENT_VERSION:-none}, status: ${CURRENT_STATUS}"
}

# ---------------------------------------------------------------------------
# Step 4: Read package.json from corporate repo
# MCP: mcp__github__get_file_contents(
#   owner=bbvinet, repo=psc-sre-automacao-agent,
#   path="package.json", branch="main")
# ---------------------------------------------------------------------------
read_package_json() {
  echo "[release-agent] Step 4: Reading package.json from ${CORPORATE_REPO}..."

  local owner repo
  owner=$(echo "$CORPORATE_REPO" | cut -d/ -f1)
  repo=$(echo "$CORPORATE_REPO" | cut -d/ -f2)

  # MCP call: mcp__github__get_file_contents
  #   owner: ${owner}
  #   repo: ${repo}
  #   path: "package.json"
  #   branch: "main"
  if command -v gh &>/dev/null; then
    PACKAGE_JSON=$(gh api "repos/${owner}/${repo}/contents/package.json" \
      --jq '.content' 2>/dev/null | base64 -d 2>/dev/null || echo "")
  fi

  if [[ -z "${PACKAGE_JSON:-}" ]]; then
    echo "ERROR: Failed to read package.json from ${CORPORATE_REPO}" >&2
    exit 1
  fi

  PACKAGE_VERSION=$(echo "$PACKAGE_JSON" | jq -r '.version // ""' 2>/dev/null || echo "")
  echo "[release-agent] Package.json version: ${PACKAGE_VERSION}"

  # Get latest commit SHA for tag building
  # MCP call: mcp__github__list_commits(owner, repo, sha="main", per_page=1)
  if command -v gh &>/dev/null; then
    LATEST_SHA=$(gh api "repos/${owner}/${repo}/commits?sha=main&per_page=1" \
      --jq '.[0].sha // ""' 2>/dev/null || echo "")
  fi
  LATEST_SHA="${LATEST_SHA:-unknown}"
  echo "[release-agent] Latest SHA: ${LATEST_SHA}"
}

# ---------------------------------------------------------------------------
# Step 5: Bump version
# ---------------------------------------------------------------------------
compute_version() {
  echo "[release-agent] Step 5: Computing new version..."

  if [[ -n "$TARGET_VERSION" ]]; then
    NEW_VERSION="$TARGET_VERSION"
    echo "[release-agent] Using explicit version: ${NEW_VERSION}"
  elif [[ -n "${PACKAGE_VERSION:-}" ]]; then
    NEW_VERSION=$(bump_version "$PACKAGE_VERSION")
    echo "[release-agent] Bumped: ${PACKAGE_VERSION} -> ${NEW_VERSION}"
  elif [[ -n "${CURRENT_VERSION:-}" ]]; then
    NEW_VERSION=$(bump_version "$CURRENT_VERSION")
    echo "[release-agent] Bumped from state: ${CURRENT_VERSION} -> ${NEW_VERSION}"
  else
    echo "ERROR: No version source available. Provide --version." >&2
    exit 1
  fi

  NEW_TAG=$(build_tag "$NEW_VERSION" "${LATEST_SHA:-0000000}")
  echo "[release-agent] New tag: ${NEW_TAG}"
}

# ---------------------------------------------------------------------------
# Step 6: Update package.json via MCP push
# MCP: mcp__github__create_or_update_file(
#   owner=bbvinet, repo=psc-sre-automacao-agent,
#   path="package.json", content=<updated>, message="chore: bump to {version}",
#   branch="main")
# ---------------------------------------------------------------------------
push_version_bump() {
  echo "[release-agent] Step 6: Pushing version bump to ${CORPORATE_REPO}..."

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[release-agent] DRY-RUN: Would update package.json to version ${NEW_VERSION}"
    return
  fi

  local owner repo
  owner=$(echo "$CORPORATE_REPO" | cut -d/ -f1)
  repo=$(echo "$CORPORATE_REPO" | cut -d/ -f2)

  # Update version in package.json
  local updated_package
  updated_package=$(echo "$PACKAGE_JSON" | jq --arg v "$NEW_VERSION" '.version = $v')

  # MCP call: mcp__github__create_or_update_file
  #   owner: ${owner}
  #   repo: ${repo}
  #   path: "package.json"
  #   content: ${updated_package}
  #   message: "chore: bump version to ${NEW_VERSION}"
  #   branch: "main"
  echo "[release-agent] MCP push: package.json -> version ${NEW_VERSION}"

  if command -v gh &>/dev/null; then
    local encoded_content current_sha
    encoded_content=$(echo "$updated_package" | base64 -w 0)
    current_sha=$(gh api "repos/${owner}/${repo}/contents/package.json" \
      --jq '.sha' 2>/dev/null || echo "")

    local payload
    payload=$(jq -n \
      --arg msg "chore: bump version to ${NEW_VERSION}" \
      --arg content "$encoded_content" \
      --arg sha "$current_sha" \
      '{message: $msg, content: $content, sha: $sha}')

    echo "$payload" | gh api "repos/${owner}/${repo}/contents/package.json" \
      --method PUT --input - >/dev/null 2>&1 || {
      echo "ERROR: Failed to push package.json update" >&2
      exit 1
    }
  fi

  echo "[release-agent] Version bump pushed."
}

# ---------------------------------------------------------------------------
# Step 7: Poll CI status ("Esteira de Build NPM")
# MCP: mcp__github__get_file_contents or GitHub API for workflow runs
# ---------------------------------------------------------------------------
poll_ci_status() {
  echo "[release-agent] Step 7: Polling CI status (${CI_WORKFLOW_NAME})..."

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[release-agent] DRY-RUN: Would poll CI. Assuming success."
    CI_RESULT="success"
    return
  fi

  # Delegate to ci-status-check.sh if available
  if [[ -x "${SCRIPT_DIR}/ci-status-check.sh" ]]; then
    local ci_output
    ci_output=$("${SCRIPT_DIR}/ci-status-check.sh" \
      --workspace "$WORKSPACE_ID" \
      --repo "$CORPORATE_REPO" \
      --workflow "$CI_WORKFLOW_NAME" \
      --poll \
      --max-polls "$CI_POLL_MAX" \
      --interval "$CI_POLL_INTERVAL" 2>&1) || true
    CI_RESULT=$(echo "$ci_output" | tail -1 | jq -r '.conclusion // "unknown"' 2>/dev/null || echo "unknown")
  else
    echo "[release-agent] ci-status-check.sh not available. Manual CI check required." >&2
    CI_RESULT="unknown"
  fi

  echo "[release-agent] CI result: ${CI_RESULT}"
}

# ---------------------------------------------------------------------------
# Step 8: Call promote-cap.sh
# ---------------------------------------------------------------------------
promote_to_cap() {
  echo "[release-agent] Step 8: Promoting to CAP..."

  if [[ "$CI_RESULT" != "success" && "$CI_RESULT" != "unknown" ]]; then
    echo "[release-agent] Skipping CAP promotion: CI result is ${CI_RESULT}" >&2
    PROMOTED=false
    return
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[release-agent] DRY-RUN: Would call promote-cap.sh"
    PROMOTED=true
    return
  fi

  if [[ -x "${SCRIPT_DIR}/promote-cap.sh" ]]; then
    "${SCRIPT_DIR}/promote-cap.sh" \
      --workspace "$WORKSPACE_ID" \
      --component "$COMPONENT" \
      --tag "$NEW_TAG" || {
      echo "WARN: CAP promotion failed" >&2
      PROMOTED=false
      return
    }
    PROMOTED=true
  else
    echo "[release-agent] promote-cap.sh not available. Manual promotion required." >&2
    PROMOTED=false
  fi

  echo "[release-agent] Promoted: ${PROMOTED}"
}

# ---------------------------------------------------------------------------
# Step 9: Update release state on autopilot-state
# MCP: mcp__github__create_or_update_file(
#   path="state/workspaces/{ws_id}/agent-release-state.json")
# ---------------------------------------------------------------------------
update_release_state() {
  echo "[release-agent] Step 9: Updating release state..."

  local status="idle"
  if [[ "${PROMOTED:-false}" == "true" ]]; then
    status="promoted"
  elif [[ "${CI_RESULT:-unknown}" == "failure" ]]; then
    status="failed"
  fi

  local release_json
  release_json=$(jq -n \
    --argjson schemaVersion "$SCHEMA_VERSION" \
    --arg workspaceId "$WORKSPACE_ID" \
    --arg component "$COMPONENT" \
    --arg lastReleasedSha "${LATEST_SHA:-}" \
    --arg lastTag "${NEW_TAG:-}" \
    --arg lastVersion "${NEW_VERSION:-}" \
    --arg updatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg status "$status" \
    --arg ciResult "${CI_RESULT:-unknown}" \
    --arg changeType "version-bump" \
    --arg commitMessage "chore: bump version to ${NEW_VERSION:-}" \
    --argjson promoted "${PROMOTED:-false}" \
    '{
      schemaVersion: $schemaVersion,
      workspaceId: $workspaceId,
      component: $component,
      lastReleasedSha: $lastReleasedSha,
      lastTag: $lastTag,
      lastVersion: $lastVersion,
      updatedAt: $updatedAt,
      status: $status,
      ciResult: $ciResult,
      changeType: $changeType,
      commitMessage: $commitMessage,
      promoted: $promoted
    }')

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[release-agent] DRY-RUN: Would write release state:"
    echo "$release_json" | jq .
    return
  fi

  write_release_state "$WORKSPACE_ID" "$COMPONENT" "$release_json"
  echo "[release-agent] Release state updated: status=${status}"
}

# ---------------------------------------------------------------------------
# Step 10: Write audit entry
# ---------------------------------------------------------------------------
write_audit() {
  echo "[release-agent] Step 10: Writing audit entry..."

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[release-agent] DRY-RUN: Would write audit entry"
    return
  fi

  write_audit_entry "release" \
    "Released ${COMPONENT} ${NEW_VERSION:-?} (tag: ${NEW_TAG:-?}), CI: ${CI_RESULT:-?}, promoted: ${PROMOTED:-false}" \
    "${CI_RESULT:-unknown}"
}

# ---------------------------------------------------------------------------
# Step 11: Release lock
# MCP: mcp__github__create_or_update_file (write empty/cleared lock)
#   or mcp__github__delete_file(path="state/workspaces/{ws_id}/locks/session-lock.json")
# ---------------------------------------------------------------------------
release_lock() {
  echo "[release-agent] Step 11: Releasing session lock..."

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[release-agent] DRY-RUN: Would release lock"
    return
  fi

  # Write an empty/released lock state
  local unlock_json
  unlock_json=$(jq -n \
    --arg releasedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg releasedBy "claude-code" \
    '{
      lockedBy: null,
      operation: null,
      releasedAt: $releasedAt,
      releasedBy: $releasedBy
    }')

  write_state "$WORKSPACE_ID" "locks/session-lock.json" "$unlock_json" \
    "lock: release after release-agent on ${WORKSPACE_ID}" 2>/dev/null || \
    echo "WARN: Failed to release lock" >&2

  echo "[release-agent] Lock released."
}

# ---------------------------------------------------------------------------
# Main pipeline
# ---------------------------------------------------------------------------
main() {
  echo "============================================"
  echo " Release Pipeline: ${COMPONENT}"
  echo " Workspace: ${WORKSPACE_ID}"
  echo " Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo " Mode: DRY-RUN"
  fi
  echo "============================================"

  # Ensure lock is released on failure
  trap 'echo "[release-agent] Pipeline failed. Releasing lock..."; release_lock 2>/dev/null || true' ERR

  pre_release_validation   # Step 0
  resolve_workspace        # Step 1
  acquire_lock             # Step 2
  read_current_state       # Step 3
  read_package_json        # Step 4
  compute_version          # Step 5
  push_version_bump        # Step 6
  poll_ci_status           # Step 7
  promote_to_cap           # Step 8
  update_release_state     # Step 9
  write_audit              # Step 10
  release_lock             # Step 11

  echo ""
  echo "============================================"
  echo " Release Complete: ${COMPONENT}"
  echo " Version: ${NEW_VERSION:-?}"
  echo " Tag: ${NEW_TAG:-?}"
  echo " CI: ${CI_RESULT:-?}"
  echo " Promoted: ${PROMOTED:-false}"
  echo "============================================"
}

main "$@"
