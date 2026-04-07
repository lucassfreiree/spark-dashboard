#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# seed-workspace.sh — Replaces: seed-workspace.yml (GitHub Actions workflow)
#
# Creates the complete directory structure for a workspace on the
# autopilot-state branch. Initializes all required state files:
#   - workspace.json       (workspace configuration, schema v3)
#   - health.json          (health check results, schema v2)
#   - release-freeze.json  (release freeze state)
#   - controller-release-state.json
#   - agent-release-state.json
#
# Creates subdirectories (via .gitkeep placeholders):
#   - locks/       (session and operation locks)
#   - audit/       (immutable audit trail entries)
#   - handoffs/    (agent handoff queue)
#   - improvements/ (improvement records)
#   - metrics/     (daily metrics snapshots)
#   - approvals/   (release approval records)
#
# Each file is created using the MCP create_or_update_file tool, writing
# directly to the autopilot-state branch without cloning.
#
# MCP Tool Calls (per file):
#   mcp__github__create_or_update_file(
#     owner="lucassfreiree",
#     repo="autopilot",
#     path="state/workspaces/{workspace_id}/{file}",
#     content="<base64 encoded JSON>",
#     message="seed: initialize {file} for {workspace_id}",
#     branch="autopilot-state"
#   )
#
# Usage:
#   ./seed-workspace.sh --workspace ws-default
#   ./seed-workspace.sh --workspace ws-cit --display-name "CIT"
#   ./seed-workspace.sh --workspace ws-default --force   # Overwrite existing
#
# Environment:
#   GITHUB_TOKEN — GitHub PAT with repo access (required)
###############################################################################

# ── Source core utilities ────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="${SCRIPT_DIR}/../core"
CONFIG_FILE="${SCRIPT_DIR}/../config.json"

for core_script in "${CORE_DIR}"/*.sh; do
  [ -f "$core_script" ] && source "$core_script" 2>/dev/null || true
done

# ── Constants ────────────────────────────────────────────────────────────────
REPO_OWNER="lucassfreiree"
REPO_NAME="autopilot"
STATE_BRANCH="autopilot-state"
STATE_BASE_PATH="state/workspaces"
SCHEMA_VERSION_WORKSPACE=3
SCHEMA_VERSION_HEALTH=2

# Load from config if available
if [ -f "$CONFIG_FILE" ]; then
  REPO_OWNER=$(jq -r '.autopilotRepo.owner // "lucassfreiree"' "$CONFIG_FILE" 2>/dev/null || echo "lucassfreiree")
  REPO_NAME=$(jq -r '.autopilotRepo.repo // "autopilot"' "$CONFIG_FILE" 2>/dev/null || echo "autopilot")
fi

# ── Arguments ────────────────────────────────────────────────────────────────
WORKSPACE_ID=""
DISPLAY_NAME=""
FORCE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace)     WORKSPACE_ID="$2"; shift 2 ;;
    --display-name)  DISPLAY_NAME="$2"; shift 2 ;;
    --force)         FORCE=true; shift ;;
    *)               echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [ -z "$WORKSPACE_ID" ]; then
  echo "ERROR: --workspace is required"
  echo "Usage: $0 --workspace <ws_id> [--display-name <name>] [--force]"
  exit 1
fi

# Validate workspace ID format (matches workspace.schema.json pattern)
if ! echo "$WORKSPACE_ID" | grep -qE '^[a-z0-9][a-z0-9-]{1,48}[a-z0-9]$'; then
  echo "ERROR: Invalid workspace ID '${WORKSPACE_ID}'"
  echo "Must match: ^[a-z0-9][a-z0-9-]{1,48}[a-z0-9]$"
  exit 1
fi

# Default display name from workspace ID
if [ -z "$DISPLAY_NAME" ]; then
  DISPLAY_NAME="$WORKSPACE_ID"
fi

WS_PATH="${STATE_BASE_PATH}/${WORKSPACE_ID}"

# ── Functions ────────────────────────────────────────────────────────────────

log_info()    { echo "[INFO] $(date -u +"%Y-%m-%dT%H:%M:%SZ") $*"; }
log_error()   { echo "[ERROR] $(date -u +"%Y-%m-%dT%H:%M:%SZ") $*" >&2; }
log_success() { echo "[OK] $(date -u +"%Y-%m-%dT%H:%M:%SZ") $*"; }
log_warn()    { echo "[WARN] $(date -u +"%Y-%m-%dT%H:%M:%SZ") $*"; }

check_prerequisites() {
  if [ -z "${GITHUB_TOKEN:-}" ]; then
    log_error "GITHUB_TOKEN is not set."
    exit 1
  fi
}

# Check if a file exists on the state branch
# Args: $1 = file path
# Returns: 0 if exists, 1 if not
file_exists_on_state() {
  local file_path="$1"
  local status_code
  status_code=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/${file_path}?ref=${STATE_BRANCH}")

  [ "$status_code" = "200" ]
}

# Write a file to the state branch
# Args: $1 = file path, $2 = content string, $3 = commit message
# MCP equivalent: mcp__github__create_or_update_file
write_state_file() {
  local file_path="$1"
  local content="$2"
  local commit_message="$3"

  local content_b64
  content_b64=$(echo -n "$content" | base64 -w 0)

  local api_url="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/${file_path}"

  # Get existing SHA if file exists (needed for update)
  local existing_sha=""
  existing_sha=$(curl -sS -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    "${api_url}?ref=${STATE_BRANCH}" 2>/dev/null | jq -r '.sha // empty' 2>/dev/null || echo "")

  local payload
  if [ -n "$existing_sha" ]; then
    payload=$(jq -n \
      --arg message "$commit_message" \
      --arg content "$content_b64" \
      --arg branch "$STATE_BRANCH" \
      --arg sha "$existing_sha" \
      '{ message: $message, content: $content, branch: $branch, sha: $sha }')
  else
    payload=$(jq -n \
      --arg message "$commit_message" \
      --arg content "$content_b64" \
      --arg branch "$STATE_BRANCH" \
      '{ message: $message, content: $content, branch: $branch }')
  fi

  local result
  result=$(curl -sS -X PUT \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    -d "$payload" \
    "$api_url" | jq -r '.content.path // "FAILED"' 2>/dev/null)

  if [ "$result" = "FAILED" ]; then
    log_error "Failed to write ${file_path}"
    return 1
  fi
  log_success "Created: ${file_path}"
}

# Generate ISO 8601 timestamp
now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# ── State File Generators ────────────────────────────────────────────────────

# Generate workspace.json (schema v3)
# Schema: schemas/workspace.schema.json
generate_workspace_json() {
  local now
  now=$(now_iso)

  jq -n \
    --argjson schemaVersion "$SCHEMA_VERSION_WORKSPACE" \
    --arg workspaceId "$WORKSPACE_ID" \
    --arg displayName "$DISPLAY_NAME" \
    --arg createdAt "$now" \
    --arg updatedAt "$now" \
    '{
      schemaVersion: $schemaVersion,
      workspaceId: $workspaceId,
      displayName: $displayName,
      createdAt: $createdAt,
      updatedAt: $updatedAt,
      company: {
        id: $workspaceId,
        name: $displayName
      },
      stack: {
        primary: "unknown",
        tools: [],
        platforms: []
      },
      credentials: {
        tokenSecretName: "",
        additionalSecrets: []
      },
      repos: [],
      settings: {
        promotionTarget: "both",
        autoRelease: true,
        lockTimeoutMinutes: 30,
        healthCheckEnabled: true,
        allowedAgents: ["claude-code"]
      }
    }'
}

# Generate health.json (schema v2)
# Schema: schemas/health-state.schema.json
generate_health_json() {
  local now
  now=$(now_iso)

  jq -n \
    --argjson schemaVersion "$SCHEMA_VERSION_HEALTH" \
    --arg workspaceId "$WORKSPACE_ID" \
    --arg checkedAt "$now" \
    '{
      schemaVersion: $schemaVersion,
      workspaceId: $workspaceId,
      checkedAt: $checkedAt,
      overall: "unknown",
      checks: {},
      summary: "Workspace seeded, awaiting first health check"
    }'
}

# Generate release-freeze.json
# Schema: schemas/release-freeze.schema.json
generate_release_freeze_json() {
  jq -n \
    --arg workspaceId "$WORKSPACE_ID" \
    '{
      frozen: false,
      workspaceId: $workspaceId,
      reason: null,
      frozenAt: null,
      frozenBy: null,
      expiresAt: null,
      unfrozenAt: null,
      unfrozenBy: null
    }'
}

# Generate empty release state for a component
# Args: $1 = component name (controller|agent)
generate_release_state_json() {
  local component="$1"
  local now
  now=$(now_iso)

  jq -n \
    --argjson schemaVersion 2 \
    --arg workspaceId "$WORKSPACE_ID" \
    --arg component "$component" \
    --arg updatedAt "$now" \
    '{
      schemaVersion: $schemaVersion,
      workspaceId: $workspaceId,
      component: $component,
      status: "idle",
      lastVersion: null,
      lastTag: null,
      lastSha: null,
      promoted: false,
      ciResult: null,
      updatedAt: $updatedAt
    }'
}

# ── Main ─────────────────────────────────────────────────────────────────────
main() {
  log_info "=== Seed Workspace: ${WORKSPACE_ID} ==="
  log_info "Path: ${WS_PATH}"
  log_info "Display name: ${DISPLAY_NAME}"
  echo ""

  check_prerequisites

  # Check if workspace already exists
  if file_exists_on_state "${WS_PATH}/workspace.json"; then
    if [ "$FORCE" = "true" ]; then
      log_warn "Workspace '${WORKSPACE_ID}' already exists — overwriting (--force)"
    else
      log_warn "Workspace '${WORKSPACE_ID}' already exists at ${WS_PATH}/workspace.json"
      log_warn "Use --force to overwrite existing workspace"
      exit 0
    fi
  fi

  local files_created=0
  local files_failed=0

  # 1. Create workspace.json
  log_info "Creating workspace.json..."
  local ws_json
  ws_json=$(generate_workspace_json)
  if write_state_file "${WS_PATH}/workspace.json" "$ws_json" \
    "seed: initialize workspace.json for ${WORKSPACE_ID}"; then
    files_created=$((files_created + 1))
  else
    files_failed=$((files_failed + 1))
  fi

  # 2. Create health.json
  log_info "Creating health.json..."
  local health_json
  health_json=$(generate_health_json)
  if write_state_file "${WS_PATH}/health.json" "$health_json" \
    "seed: initialize health.json for ${WORKSPACE_ID}"; then
    files_created=$((files_created + 1))
  else
    files_failed=$((files_failed + 1))
  fi

  # 3. Create release-freeze.json
  log_info "Creating release-freeze.json..."
  local freeze_json
  freeze_json=$(generate_release_freeze_json)
  if write_state_file "${WS_PATH}/release-freeze.json" "$freeze_json" \
    "seed: initialize release-freeze.json for ${WORKSPACE_ID}"; then
    files_created=$((files_created + 1))
  else
    files_failed=$((files_failed + 1))
  fi

  # 4. Create controller-release-state.json
  log_info "Creating controller-release-state.json..."
  local ctrl_json
  ctrl_json=$(generate_release_state_json "controller")
  if write_state_file "${WS_PATH}/controller-release-state.json" "$ctrl_json" \
    "seed: initialize controller-release-state.json for ${WORKSPACE_ID}"; then
    files_created=$((files_created + 1))
  else
    files_failed=$((files_failed + 1))
  fi

  # 5. Create agent-release-state.json
  log_info "Creating agent-release-state.json..."
  local agent_json
  agent_json=$(generate_release_state_json "agent")
  if write_state_file "${WS_PATH}/agent-release-state.json" "$agent_json" \
    "seed: initialize agent-release-state.json for ${WORKSPACE_ID}"; then
    files_created=$((files_created + 1))
  else
    files_failed=$((files_failed + 1))
  fi

  # 6. Create subdirectory placeholders (.gitkeep files)
  local subdirs=("locks" "audit" "handoffs" "improvements" "metrics" "approvals")
  for subdir in "${subdirs[@]}"; do
    log_info "Creating ${subdir}/ directory..."
    if write_state_file "${WS_PATH}/${subdir}/.gitkeep" "" \
      "seed: create ${subdir}/ directory for ${WORKSPACE_ID}"; then
      files_created=$((files_created + 1))
    else
      files_failed=$((files_failed + 1))
    fi
  done

  # Summary
  echo ""
  log_success "=== Seed Complete ==="
  log_success "Workspace:     ${WORKSPACE_ID}"
  log_success "Files created: ${files_created}"
  if [ "$files_failed" -gt 0 ]; then
    log_error "Files failed:  ${files_failed}"
    exit 1
  fi
  log_success "State path:    ${WS_PATH}/"
  log_success "Branch:        ${STATE_BRANCH}"
}

main "$@"
