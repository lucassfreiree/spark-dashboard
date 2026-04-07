#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# release-freeze.sh — Replaces: release-freeze.yml (GitHub Actions workflow)
#
# Manages the release freeze state for a workspace. In the original system,
# this is a manually-triggered workflow that freezes or unfreezes releases.
# When frozen, release workflows (release-controller.yml, release-agent.yml)
# check this state and refuse to proceed.
#
# State file: state/workspaces/{ws_id}/release-freeze.json
# Schema: schemas/release-freeze.schema.json
#
# Required fields (from schema):
#   - frozen: boolean
#   - workspaceId: string (pattern: ^[a-z0-9][a-z0-9-]{1,48}[a-z0-9]$)
#
# Optional fields:
#   - reason, frozenAt, frozenBy, runId, expiresAt, unfrozenAt, unfrozenBy
#
# Operations:
#   freeze   — Set frozen=true with reason, optional duration
#   unfreeze — Set frozen=false, record who/when
#   check    — Return current freeze status (exit 0=unfrozen, 1=frozen)
#   status   — Human-readable output
#
# MCP Tool Calls:
#   - mcp__github__get_file_contents: Read release-freeze.json from
#       state/workspaces/{ws_id}/release-freeze.json on autopilot-state
#   - mcp__github__create_or_update_file: Write updated release-freeze.json
#       to the same path on autopilot-state
#
# Usage:
#   ./release-freeze.sh freeze   --workspace ws-default --reason "Sprint deploy"
#   ./release-freeze.sh freeze   --workspace ws-default --reason "Hotfix" --duration 2h
#   ./release-freeze.sh unfreeze --workspace ws-default --by "lucas"
#   ./release-freeze.sh check    --workspace ws-default
#   ./release-freeze.sh status   --workspace ws-default
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

if [ -f "$CONFIG_FILE" ]; then
  REPO_OWNER=$(jq -r '.autopilotRepo.owner // "lucassfreiree"' "$CONFIG_FILE" 2>/dev/null || echo "lucassfreiree")
  REPO_NAME=$(jq -r '.autopilotRepo.repo // "autopilot"' "$CONFIG_FILE" 2>/dev/null || echo "autopilot")
fi

# ── Arguments ────────────────────────────────────────────────────────────────
ACTION=""
WORKSPACE_ID=""
REASON=""
FROZEN_BY="claude-code-backup"
DURATION=""
RUN_ID=""

# Parse action first (positional argument)
if [[ $# -gt 0 ]]; then
  ACTION="$1"
  shift
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace)  WORKSPACE_ID="$2"; shift 2 ;;
    --reason)     REASON="$2"; shift 2 ;;
    --by)         FROZEN_BY="$2"; shift 2 ;;
    --duration)   DURATION="$2"; shift 2 ;;
    --run-id)     RUN_ID="$2"; shift 2 ;;
    *)            echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [ -z "$ACTION" ]; then
  echo "Usage: $0 {freeze|unfreeze|check|status} --workspace <ws_id> [options]"
  echo ""
  echo "Actions:"
  echo "  freeze   --workspace <ws_id> --reason <text> [--duration <Nh|Nm>] [--by <who>]"
  echo "  unfreeze --workspace <ws_id> [--by <who>]"
  echo "  check    --workspace <ws_id>   (exit 0=unfrozen, 1=frozen)"
  echo "  status   --workspace <ws_id>   (human-readable output)"
  exit 1
fi

if [ -z "$WORKSPACE_ID" ]; then
  echo "ERROR: --workspace is required"
  exit 1
fi

FREEZE_PATH="${STATE_BASE_PATH}/${WORKSPACE_ID}/release-freeze.json"

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

# Read the current release-freeze.json from the state branch
# Returns: JSON content on stdout, empty string if file not found
#
# MCP equivalent:
#   mcp__github__get_file_contents(
#     owner="lucassfreiree",
#     repo="autopilot",
#     path="state/workspaces/{ws_id}/release-freeze.json",
#     branch="autopilot-state"
#   )
read_freeze_state() {
  local response
  response=$(curl -sS -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/${FREEZE_PATH}?ref=${STATE_BRANCH}" 2>/dev/null)

  echo "$response" | jq -r '.content // empty' 2>/dev/null | base64 -d 2>/dev/null || echo ""
}

# Get the SHA of the freeze file (needed for update operations)
get_freeze_sha() {
  curl -sS -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/${FREEZE_PATH}?ref=${STATE_BRANCH}" \
    | jq -r '.sha // empty' 2>/dev/null || echo ""
}

# Write the release-freeze.json file to the state branch
# Args: $1 = JSON content, $2 = commit message
#
# MCP equivalent:
#   mcp__github__create_or_update_file(
#     owner="lucassfreiree",
#     repo="autopilot",
#     path="state/workspaces/{ws_id}/release-freeze.json",
#     content=<base64 encoded JSON>,
#     message=<commit message>,
#     branch="autopilot-state",
#     sha=<current file SHA if updating>
#   )
write_freeze_state() {
  local content="$1"
  local commit_message="$2"

  # Validate JSON before writing
  if ! echo "$content" | jq empty 2>/dev/null; then
    log_error "Content is not valid JSON"
    return 1
  fi

  local content_b64
  content_b64=$(echo -n "$content" | base64 -w 0)

  local api_url="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/${FREEZE_PATH}"

  local existing_sha
  existing_sha=$(get_freeze_sha)

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
    log_error "Failed to write release-freeze.json"
    return 1
  fi
  return 0
}

# Calculate expiration timestamp from a duration string
# Args: $1 = duration string (e.g., "2h", "30m", "1d")
# Returns: ISO 8601 timestamp on stdout
calculate_expiry() {
  local duration="$1"
  local seconds=0

  if [[ "$duration" =~ ^([0-9]+)h$ ]]; then
    seconds=$(( ${BASH_REMATCH[1]} * 3600 ))
  elif [[ "$duration" =~ ^([0-9]+)m$ ]]; then
    seconds=$(( ${BASH_REMATCH[1]} * 60 ))
  elif [[ "$duration" =~ ^([0-9]+)d$ ]]; then
    seconds=$(( ${BASH_REMATCH[1]} * 86400 ))
  else
    log_error "Invalid duration format: ${duration} (use Nh, Nm, or Nd)"
    return 1
  fi

  date -u -d "+${seconds} seconds" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || {
    # Fallback: calculate from epoch
    local now_epoch
    now_epoch=$(date +%s)
    date -u -d "@$((now_epoch + seconds))" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo ""
  }
}

# ── Actions ──────────────────────────────────────────────────────────────────

# Freeze releases for the workspace
# Sets frozen=true with reason, optional expiry based on --duration
do_freeze() {
  if [ -z "$REASON" ]; then
    log_error "--reason is required for freeze action"
    exit 1
  fi

  log_info "Freezing releases for workspace '${WORKSPACE_ID}'..."
  log_info "Reason: ${REASON}"

  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Calculate expiry if duration was specified
  local expires_at_value="null"
  if [ -n "$DURATION" ]; then
    local calculated
    calculated=$(calculate_expiry "$DURATION") || exit 1
    if [ -n "$calculated" ]; then
      expires_at_value="\"${calculated}\""
      log_info "Duration: ${DURATION} (expires at: ${calculated})"
    fi
  fi

  # Build the freeze state JSON (matches release-freeze.schema.json)
  local freeze_json
  freeze_json=$(jq -n \
    --argjson frozen true \
    --arg workspaceId "$WORKSPACE_ID" \
    --arg reason "$REASON" \
    --arg frozenAt "$now" \
    --arg frozenBy "$FROZEN_BY" \
    --arg runId "${RUN_ID:-}" \
    '{
      frozen: $frozen,
      workspaceId: $workspaceId,
      reason: $reason,
      frozenAt: $frozenAt,
      frozenBy: $frozenBy,
      runId: (if $runId == "" then null else $runId end),
      expiresAt: null,
      unfrozenAt: null,
      unfrozenBy: null
    }')

  # Inject expiresAt if duration was provided
  if [ "$expires_at_value" != "null" ]; then
    local exp_str="${expires_at_value//\"/}"
    freeze_json=$(echo "$freeze_json" | jq --arg exp "$exp_str" '.expiresAt = $exp')
  fi

  if write_freeze_state "$freeze_json" \
    "release-freeze: FROZEN ${WORKSPACE_ID} — ${REASON}"; then
    log_success "Releases FROZEN for ${WORKSPACE_ID}"
    echo "$freeze_json" | jq .
  else
    log_error "Failed to freeze releases"
    exit 1
  fi
}

# Unfreeze releases for the workspace
# Preserves freeze history from previous state, sets frozen=false
do_unfreeze() {
  log_info "Unfreezing releases for workspace '${WORKSPACE_ID}'..."

  # Read current state to preserve freeze history fields
  local current
  current=$(read_freeze_state)

  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local freeze_json
  if [ -n "$current" ]; then
    # Update existing state: set frozen=false, add unfreeze metadata
    freeze_json=$(echo "$current" | jq \
      --argjson frozen false \
      --arg unfrozenAt "$now" \
      --arg unfrozenBy "$FROZEN_BY" \
      '.frozen = $frozen | .unfrozenAt = $unfrozenAt | .unfrozenBy = $unfrozenBy')
  else
    # No previous state exists; create a fresh unfrozen record
    freeze_json=$(jq -n \
      --argjson frozen false \
      --arg workspaceId "$WORKSPACE_ID" \
      --arg unfrozenAt "$now" \
      --arg unfrozenBy "$FROZEN_BY" \
      '{
        frozen: $frozen,
        workspaceId: $workspaceId,
        reason: null,
        frozenAt: null,
        frozenBy: null,
        expiresAt: null,
        unfrozenAt: $unfrozenAt,
        unfrozenBy: $unfrozenBy
      }')
  fi

  if write_freeze_state "$freeze_json" \
    "release-freeze: UNFROZEN ${WORKSPACE_ID} by ${FROZEN_BY}"; then
    log_success "Releases UNFROZEN for ${WORKSPACE_ID}"
    echo "$freeze_json" | jq .
  else
    log_error "Failed to unfreeze releases"
    exit 1
  fi
}

# Machine-readable freeze check
# Exit 0 = unfrozen (releases allowed)
# Exit 1 = frozen (releases blocked)
# Also detects expired freezes and reports them as unfrozen
do_check() {
  local current
  current=$(read_freeze_state)

  if [ -z "$current" ]; then
    # No freeze file means releases are allowed
    echo '{"frozen": false}'
    exit 0
  fi

  local is_frozen
  is_frozen=$(echo "$current" | jq -r '.frozen // false' 2>/dev/null)

  # Check if freeze has expired based on expiresAt
  if [ "$is_frozen" = "true" ]; then
    local expires_at
    expires_at=$(echo "$current" | jq -r '.expiresAt // ""' 2>/dev/null)

    if [ -n "$expires_at" ] && [ "$expires_at" != "null" ]; then
      local now_epoch expires_epoch
      now_epoch=$(date +%s)
      expires_epoch=$(date -d "$expires_at" +%s 2>/dev/null || echo "0")

      if [ "$expires_epoch" -gt 0 ] && [ "$now_epoch" -gt "$expires_epoch" ]; then
        log_info "Freeze has expired (was set to expire at ${expires_at})"
        echo "$current" | jq '.frozen = false | .unfrozenAt = "auto-expired" | .unfrozenBy = "release-freeze-check"'
        exit 0
      fi
    fi
  fi

  echo "$current" | jq .

  if [ "$is_frozen" = "true" ]; then
    exit 1
  else
    exit 0
  fi
}

# Human-readable status output
do_status() {
  local current
  current=$(read_freeze_state)

  echo "=== Release Freeze Status: ${WORKSPACE_ID} ==="
  echo ""

  if [ -z "$current" ]; then
    echo "Status:  UNFROZEN (no freeze file exists)"
    echo "Releases are ALLOWED"
    exit 0
  fi

  local is_frozen reason frozen_at frozen_by expires_at
  is_frozen=$(echo "$current" | jq -r '.frozen // false' 2>/dev/null)
  reason=$(echo "$current" | jq -r '.reason // "N/A"' 2>/dev/null)
  frozen_at=$(echo "$current" | jq -r '.frozenAt // "N/A"' 2>/dev/null)
  frozen_by=$(echo "$current" | jq -r '.frozenBy // "N/A"' 2>/dev/null)
  expires_at=$(echo "$current" | jq -r '.expiresAt // "none"' 2>/dev/null)

  if [ "$is_frozen" = "true" ]; then
    echo "Status:     FROZEN"
    echo "Reason:     ${reason}"
    echo "Frozen at:  ${frozen_at}"
    echo "Frozen by:  ${frozen_by}"
    echo "Expires at: ${expires_at}"
    echo ""
    echo "Releases are BLOCKED"

    # Warn if freeze has expired but not cleared
    if [ "$expires_at" != "none" ] && [ "$expires_at" != "null" ]; then
      local now_epoch exp_epoch
      now_epoch=$(date +%s)
      exp_epoch=$(date -d "$expires_at" +%s 2>/dev/null || echo "0")
      if [ "$exp_epoch" -gt 0 ] && [ "$now_epoch" -gt "$exp_epoch" ]; then
        echo ""
        log_warn "NOTE: Freeze has EXPIRED but has not been auto-cleared"
        echo "Run: $0 unfreeze --workspace ${WORKSPACE_ID}"
      fi
    fi
  else
    local unfrozen_at unfrozen_by
    unfrozen_at=$(echo "$current" | jq -r '.unfrozenAt // "N/A"' 2>/dev/null)
    unfrozen_by=$(echo "$current" | jq -r '.unfrozenBy // "N/A"' 2>/dev/null)

    echo "Status:      UNFROZEN"
    echo "Last reason: ${reason}"
    echo "Unfrozen at: ${unfrozen_at}"
    echo "Unfrozen by: ${unfrozen_by}"
    echo ""
    echo "Releases are ALLOWED"
  fi
}

# ── Main ─────────────────────────────────────────────────────────────────────
main() {
  check_prerequisites

  case "$ACTION" in
    freeze)    do_freeze ;;
    unfreeze)  do_unfreeze ;;
    check)     do_check ;;
    status)    do_status ;;
    *)
      echo "ERROR: Unknown action '${ACTION}'"
      echo "Valid actions: freeze, unfreeze, check, status"
      exit 1
      ;;
  esac
}

main
