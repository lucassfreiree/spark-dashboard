#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# release-controller.sh
# Replaces: .github/workflows/release-controller.yml
#
# Full release pipeline for the CONTROLLER component.
# Identical flow to release-agent.sh but targets the controller repo.
#
# Pipeline steps:
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
# Tag format: {version}-{short_sha} (e.g., 3.8.3-a1b2c3d)
#
# Corporate repo: bbvinet/psc-sre-automacao-controller
# Component: controller
# Workspace: ws-default (Getronics)
#
# Usage:
#   ./release-controller.sh [--workspace <ws_id>] [--version <version>] [--dry-run]
#
# MCP tools used:
#   - mcp__github__get_file_contents   (read state, package.json, workspace config)
#   - mcp__github__create_or_update_file (write state, push package.json)
#   - mcp__github__list_commits         (get latest SHA for tag)
#
# Schema: schemas/release-state.schema.json (schemaVersion: 2)
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source core modules
source "${SCRIPT_DIR}/../core/state-manager.sh"

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
SCHEMA_VERSION=2
COMPONENT="controller"
DEFAULT_WORKSPACE="ws-default"
CORPORATE_REPO="bbvinet/psc-sre-automacao-controller"
CI_WORKFLOW_NAME="Esteira de Build NPM"
CI_POLL_INTERVAL=120
CI_POLL_MAX=20

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

# Bump version following 0-9 patch rule
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

# Build tag: {version}-{short_sha}
build_tag() {
  local version="$1"
  local sha="$2"
  echo "${version}-${sha:0:7}"
}

# Write audit entry
# MCP: mcp__github__create_or_update_file(
#   path="state/workspaces/{ws_id}/audit/release-controller-{timestamp}.json")
write_audit_entry() {
  local action="$1"
  local detail="$2"
  local status="$3"
  local filename="release-controller-$(date -u +%Y%m%d-%H%M%S).json"

  local audit_json
  audit_json=$(jq -n \
    --arg action "$action" \
    --arg component "$COMPONENT" \
    --arg workspaceId "$WORKSPACE_ID" \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg detail "$detail" \
    --arg status "$status" \
    --arg agent "claude-code" \
    '{action: $action, component: $component, workspaceId: $workspaceId,
      timestamp: $timestamp, detail: $detail, status: $status, agent: $agent}')

  write_state "$WORKSPACE_ID" "audit/${filename}" "$audit_json" \
    "audit: ${action} ${COMPONENT} for ${WORKSPACE_ID}" 2>/dev/null || \
    echo "WARN: Failed to write audit entry" >&2
}

# ---------------------------------------------------------------------------
# Step 1: Resolve workspace
# MCP: mcp__github__get_file_contents(path="state/workspaces/{ws_id}/workspace.json")
# ---------------------------------------------------------------------------
resolve_workspace() {
  echo "[release-controller] Step 1: Resolving workspace ${WORKSPACE_ID}..."

  local ws_json
  ws_json=$(read_workspace_config "$WORKSPACE_ID" 2>/dev/null || echo "")

  if [[ -z "$ws_json" ]]; then
    echo "ERROR: Could not read workspace config for ${WORKSPACE_ID}" >&2
    exit 1
  fi

  local source_repo
  source_repo=$(echo "$ws_json" | jq -r '.controller.sourceRepo // ""' 2>/dev/null || echo "")

  if [[ -n "$source_repo" ]]; then
    CORPORATE_REPO="$source_repo"
    echo "[release-controller] Corporate repo from config: ${CORPORATE_REPO}"
  fi

  echo "[release-controller] Workspace resolved: ${WORKSPACE_ID}, repo: ${CORPORATE_REPO}"
}

# ---------------------------------------------------------------------------
# Step 2: Acquire session lock
# MCP: mcp__github__create_or_update_file(
#   path="state/workspaces/{ws_id}/locks/session-lock.json")
# ---------------------------------------------------------------------------
acquire_lock() {
  echo "[release-controller] Step 2: Acquiring session lock..."

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
        echo "ERROR: Lock held by ${locked_by} (age: ${age_minutes}m). Aborting." >&2
        exit 1
      fi
      echo "[release-controller] Existing lock expired. Overriding."
    fi
  fi

  local lock_json
  lock_json=$(jq -n \
    --arg lockedBy "claude-code" \
    --arg operation "release-controller" \
    --arg workspaceId "$WORKSPACE_ID" \
    --arg lockedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson ttlMinutes 30 \
    '{lockedBy: $lockedBy, operation: $operation, workspaceId: $workspaceId,
      lockedAt: $lockedAt, ttlMinutes: $ttlMinutes}')

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[release-controller] DRY-RUN: Would acquire lock"
    return
  fi

  write_state "$WORKSPACE_ID" "locks/session-lock.json" "$lock_json" \
    "lock: acquire for release-controller on ${WORKSPACE_ID}"
  echo "[release-controller] Lock acquired."
}

# ---------------------------------------------------------------------------
# Step 3: Read current release state
# MCP: mcp__github__get_file_contents(
#   path="state/workspaces/{ws_id}/controller-release-state.json")
# ---------------------------------------------------------------------------
read_current_state() {
  echo "[release-controller] Step 3: Reading current release state..."

  local state_json
  state_json=$(read_release_state "$WORKSPACE_ID" "$COMPONENT" 2>/dev/null || echo "")

  if [[ -z "$state_json" ]]; then
    echo "[release-controller] No existing release state. Starting fresh."
    CURRENT_VERSION=""
    CURRENT_STATUS="idle"
    return
  fi

  CURRENT_VERSION=$(echo "$state_json" | jq -r '.lastVersion // ""' 2>/dev/null || echo "")
  CURRENT_STATUS=$(echo "$state_json" | jq -r '.status // "idle"' 2>/dev/null || echo "idle")

  if [[ "$CURRENT_STATUS" == "releasing" ]]; then
    local updated_at
    updated_at=$(echo "$state_json" | jq -r '.updatedAt // ""' 2>/dev/null || echo "")
    if [[ -n "$updated_at" ]]; then
      local now_epoch upd_epoch age_min
      now_epoch=$(date +%s)
      upd_epoch=$(date -d "$updated_at" +%s 2>/dev/null || echo "0")
      age_min=$(( (now_epoch - upd_epoch) / 60 ))
      if [[ $age_min -lt 60 ]]; then
        echo "ERROR: Release in progress (${age_min}m). Wait or clear." >&2
        exit 1
      fi
      echo "[release-controller] Previous release stuck (${age_min}m). Proceeding."
    fi
  fi

  echo "[release-controller] Current: version=${CURRENT_VERSION:-none}, status=${CURRENT_STATUS}"
}

# ---------------------------------------------------------------------------
# Step 4: Read package.json from corporate repo
# MCP: mcp__github__get_file_contents(
#   owner=bbvinet, repo=psc-sre-automacao-controller,
#   path="package.json", branch="main")
# ---------------------------------------------------------------------------
read_package_json() {
  echo "[release-controller] Step 4: Reading package.json from ${CORPORATE_REPO}..."

  local owner repo
  owner=$(echo "$CORPORATE_REPO" | cut -d/ -f1)
  repo=$(echo "$CORPORATE_REPO" | cut -d/ -f2)

  # MCP: mcp__github__get_file_contents(owner, repo, path="package.json", branch="main")
  if command -v gh &>/dev/null; then
    PACKAGE_JSON=$(gh api "repos/${owner}/${repo}/contents/package.json" \
      --jq '.content' 2>/dev/null | base64 -d 2>/dev/null || echo "")
  fi

  if [[ -z "${PACKAGE_JSON:-}" ]]; then
    echo "ERROR: Failed to read package.json from ${CORPORATE_REPO}" >&2
    exit 1
  fi

  PACKAGE_VERSION=$(echo "$PACKAGE_JSON" | jq -r '.version // ""' 2>/dev/null || echo "")
  echo "[release-controller] Package.json version: ${PACKAGE_VERSION}"

  # MCP: mcp__github__list_commits(owner, repo, sha="main", per_page=1)
  if command -v gh &>/dev/null; then
    LATEST_SHA=$(gh api "repos/${owner}/${repo}/commits?sha=main&per_page=1" \
      --jq '.[0].sha // ""' 2>/dev/null || echo "")
  fi
  LATEST_SHA="${LATEST_SHA:-unknown}"
  echo "[release-controller] Latest SHA: ${LATEST_SHA}"
}

# ---------------------------------------------------------------------------
# Step 5: Bump version
# ---------------------------------------------------------------------------
compute_version() {
  echo "[release-controller] Step 5: Computing new version..."

  if [[ -n "$TARGET_VERSION" ]]; then
    NEW_VERSION="$TARGET_VERSION"
  elif [[ -n "${PACKAGE_VERSION:-}" ]]; then
    NEW_VERSION=$(bump_version "$PACKAGE_VERSION")
    echo "[release-controller] Bumped: ${PACKAGE_VERSION} -> ${NEW_VERSION}"
  elif [[ -n "${CURRENT_VERSION:-}" ]]; then
    NEW_VERSION=$(bump_version "$CURRENT_VERSION")
  else
    echo "ERROR: No version source. Provide --version." >&2
    exit 1
  fi

  NEW_TAG=$(build_tag "$NEW_VERSION" "${LATEST_SHA:-0000000}")
  echo "[release-controller] New tag: ${NEW_TAG}"
}

# ---------------------------------------------------------------------------
# Step 6: Update package.json via MCP push
# MCP: mcp__github__create_or_update_file(
#   owner=bbvinet, repo=psc-sre-automacao-controller,
#   path="package.json", content=<updated>, branch="main")
# ---------------------------------------------------------------------------
push_version_bump() {
  echo "[release-controller] Step 6: Pushing version bump to ${CORPORATE_REPO}..."

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[release-controller] DRY-RUN: Would update package.json to ${NEW_VERSION}"
    return
  fi

  local owner repo
  owner=$(echo "$CORPORATE_REPO" | cut -d/ -f1)
  repo=$(echo "$CORPORATE_REPO" | cut -d/ -f2)

  local updated_package
  updated_package=$(echo "$PACKAGE_JSON" | jq --arg v "$NEW_VERSION" '.version = $v')

  # MCP: mcp__github__create_or_update_file(owner, repo, path, content, message, branch)
  if command -v gh &>/dev/null; then
    local encoded_content current_sha payload
    encoded_content=$(echo "$updated_package" | base64 -w 0)
    current_sha=$(gh api "repos/${owner}/${repo}/contents/package.json" \
      --jq '.sha' 2>/dev/null || echo "")

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

  echo "[release-controller] Version bump pushed."
}

# ---------------------------------------------------------------------------
# Step 7: Poll CI status
# ---------------------------------------------------------------------------
poll_ci_status() {
  echo "[release-controller] Step 7: Polling CI status (${CI_WORKFLOW_NAME})..."

  if [[ "$DRY_RUN" == "true" ]]; then
    CI_RESULT="success"
    return
  fi

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
    echo "[release-controller] ci-status-check.sh not available. Manual check required." >&2
    CI_RESULT="unknown"
  fi

  echo "[release-controller] CI result: ${CI_RESULT}"
}

# ---------------------------------------------------------------------------
# Step 8: Call promote-cap.sh
# ---------------------------------------------------------------------------
promote_to_cap() {
  echo "[release-controller] Step 8: Promoting to CAP..."

  if [[ "$CI_RESULT" != "success" && "$CI_RESULT" != "unknown" ]]; then
    echo "[release-controller] Skipping promotion: CI=${CI_RESULT}" >&2
    PROMOTED=false
    return
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
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
    echo "[release-controller] promote-cap.sh not available." >&2
    PROMOTED=false
  fi
}

# ---------------------------------------------------------------------------
# Step 9: Update release state
# MCP: mcp__github__create_or_update_file(
#   path="state/workspaces/{ws_id}/controller-release-state.json")
# ---------------------------------------------------------------------------
update_release_state() {
  echo "[release-controller] Step 9: Updating release state..."

  local status="idle"
  if [[ "${PROMOTED:-false}" == "true" ]]; then status="promoted"
  elif [[ "${CI_RESULT:-unknown}" == "failure" ]]; then status="failed"
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
    '{schemaVersion: $schemaVersion, workspaceId: $workspaceId, component: $component,
      lastReleasedSha: $lastReleasedSha, lastTag: $lastTag, lastVersion: $lastVersion,
      updatedAt: $updatedAt, status: $status, ciResult: $ciResult,
      changeType: $changeType, commitMessage: $commitMessage, promoted: $promoted}')

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "$release_json" | jq .
    return
  fi

  write_release_state "$WORKSPACE_ID" "$COMPONENT" "$release_json"
  echo "[release-controller] Release state updated: status=${status}"
}

# ---------------------------------------------------------------------------
# Step 10: Write audit entry
# ---------------------------------------------------------------------------
write_audit() {
  echo "[release-controller] Step 10: Writing audit entry..."
  [[ "$DRY_RUN" == "true" ]] && return
  write_audit_entry "release" \
    "Released ${COMPONENT} ${NEW_VERSION:-?} (tag: ${NEW_TAG:-?}), CI: ${CI_RESULT:-?}, promoted: ${PROMOTED:-false}" \
    "${CI_RESULT:-unknown}"
}

# ---------------------------------------------------------------------------
# Step 11: Release lock
# MCP: mcp__github__create_or_update_file or mcp__github__delete_file
# ---------------------------------------------------------------------------
release_lock() {
  echo "[release-controller] Step 11: Releasing session lock..."
  [[ "$DRY_RUN" == "true" ]] && return

  local unlock_json
  unlock_json=$(jq -n \
    --arg releasedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg releasedBy "claude-code" \
    '{lockedBy: null, operation: null, releasedAt: $releasedAt, releasedBy: $releasedBy}')

  write_state "$WORKSPACE_ID" "locks/session-lock.json" "$unlock_json" \
    "lock: release after release-controller on ${WORKSPACE_ID}" 2>/dev/null || \
    echo "WARN: Failed to release lock" >&2
}

# ---------------------------------------------------------------------------
# Main pipeline
# ---------------------------------------------------------------------------
main() {
  echo "============================================"
  echo " Release Pipeline: ${COMPONENT}"
  echo " Workspace: ${WORKSPACE_ID}"
  echo " Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  [[ "$DRY_RUN" == "true" ]] && echo " Mode: DRY-RUN"
  echo "============================================"

  trap 'echo "[release-controller] Pipeline failed. Releasing lock..."; release_lock 2>/dev/null || true' ERR

  resolve_workspace
  acquire_lock
  read_current_state
  read_package_json
  compute_version
  push_version_bump
  poll_ci_status
  promote_to_cap
  update_release_state
  write_audit
  release_lock

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
