#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# workspace-lock-gc.sh — Replaces: workspace-lock-gc.yml (GitHub Actions)
#
# Garbage collector for expired workspace locks. In the original system,
# this runs on a 15-minute cron schedule via GitHub Actions. It iterates
# all workspaces, checks each workspace's session-lock.json, and deletes
# locks that have exceeded their TTL.
#
# Lock files are stored at:
#   state/workspaces/{workspace_id}/locks/session-lock.json
#
# A lock is considered expired when:
#   (current_time - lockedAt) > ttlMinutes
#
# The default TTL is 30 minutes (configurable in config.json).
#
# MCP Tool Calls:
#   - mcp__github__get_file_contents: List workspaces directory
#   - mcp__github__get_file_contents: Read each workspace's session-lock.json
#   - mcp__github__delete_file: Delete expired lock files
#   - mcp__github__create_or_update_file: Write audit entry for each cleanup
#
# Usage:
#   ./workspace-lock-gc.sh                  # GC all workspaces
#   ./workspace-lock-gc.sh --workspace ws-default  # GC specific workspace
#   ./workspace-lock-gc.sh --dry-run        # Report only, don't delete
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
DEFAULT_TTL_MINUTES=30

# Load from config
if [ -f "$CONFIG_FILE" ]; then
  REPO_OWNER=$(jq -r '.autopilotRepo.owner // "lucassfreiree"' "$CONFIG_FILE" 2>/dev/null || echo "lucassfreiree")
  REPO_NAME=$(jq -r '.autopilotRepo.repo // "autopilot"' "$CONFIG_FILE" 2>/dev/null || echo "autopilot")
  DEFAULT_TTL_MINUTES=$(jq -r '.sessionGuard.defaultTTL // 30' "$CONFIG_FILE" 2>/dev/null || echo "30")
fi

# ── Arguments ────────────────────────────────────────────────────────────────
TARGET_WORKSPACE=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace) TARGET_WORKSPACE="$2"; shift 2 ;;
    --dry-run)   DRY_RUN=true; shift ;;
    *)           echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ── Functions ────────────────────────────────────────────────────────────────

log_info()    { echo "[INFO] $(date -u +"%Y-%m-%dT%H:%M:%SZ") $*"; }
log_error()   { echo "[ERROR] $(date -u +"%Y-%m-%dT%H:%M:%SZ") $*" >&2; }
log_success() { echo "[OK] $(date -u +"%Y-%m-%dT%H:%M:%SZ") $*"; }
log_warn()    { echo "[WARN] $(date -u +"%Y-%m-%dT%H:%M:%SZ") $*"; }
log_gc()      { echo "[GC] $(date -u +"%Y-%m-%dT%H:%M:%SZ") $*"; }

check_prerequisites() {
  if [ -z "${GITHUB_TOKEN:-}" ]; then
    log_error "GITHUB_TOKEN is not set."
    exit 1
  fi
}

# List all workspace IDs from the state branch
# MCP equivalent: mcp__github__get_file_contents(path="state/workspaces", branch="autopilot-state")
list_workspaces() {
  curl -sS -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/${STATE_BASE_PATH}?ref=${STATE_BRANCH}" \
    | jq -r '.[] | select(.type == "dir") | .name' 2>/dev/null || echo ""
}

# Read a file from the state branch and return its content (decoded)
# Args: $1 = file path
# MCP equivalent: mcp__github__get_file_contents
read_state_content() {
  local file_path="$1"
  local response
  response=$(curl -sS -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/${file_path}?ref=${STATE_BRANCH}" 2>/dev/null)

  local content
  content=$(echo "$response" | jq -r '.content // empty' 2>/dev/null | base64 -d 2>/dev/null || echo "")
  echo "$content"
}

# Get the SHA of a file on the state branch (needed for delete)
# Args: $1 = file path
get_file_sha() {
  local file_path="$1"
  curl -sS -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/${file_path}?ref=${STATE_BRANCH}" \
    | jq -r '.sha // empty' 2>/dev/null || echo ""
}

# Delete a file from the state branch
# Args: $1 = file path, $2 = file SHA, $3 = commit message
# MCP equivalent: mcp__github__delete_file
delete_state_file() {
  local file_path="$1"
  local file_sha="$2"
  local commit_message="$3"

  local payload
  payload=$(jq -n \
    --arg message "$commit_message" \
    --arg sha "$file_sha" \
    --arg branch "$STATE_BRANCH" \
    '{ message: $message, sha: $sha, branch: $branch }')

  local result
  result=$(curl -sS -X DELETE \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    -d "$payload" \
    "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/${file_path}" \
    | jq -r '.commit.sha // "FAILED"' 2>/dev/null)

  if [ "$result" = "FAILED" ]; then
    return 1
  fi
  return 0
}

# Write an audit entry for the lock cleanup
# Args: $1 = workspace_id, $2 = lock details JSON
write_gc_audit() {
  local workspace_id="$1"
  local lock_details="$2"
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local audit_filename="lock-gc-$(date -u +"%Y%m%d-%H%M%S").json"
  local audit_path="${STATE_BASE_PATH}/${workspace_id}/audit/${audit_filename}"

  local audit_entry
  audit_entry=$(jq -n \
    --arg operation "lock-gc" \
    --arg workspaceId "$workspace_id" \
    --arg timestamp "$timestamp" \
    --arg agent "lock-gc-script" \
    --argjson details "$lock_details" \
    '{
      operation: $operation,
      workspaceId: $workspaceId,
      timestamp: $timestamp,
      agent: $agent,
      details: $details
    }')

  local content_b64
  content_b64=$(echo -n "$audit_entry" | base64 -w 0)

  local api_url="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/${audit_path}"
  local payload
  payload=$(jq -n \
    --arg message "audit: lock-gc for ${workspace_id}" \
    --arg content "$content_b64" \
    --arg branch "$STATE_BRANCH" \
    '{ message: $message, content: $content, branch: $branch }')

  curl -sS -X PUT \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    -d "$payload" \
    "$api_url" >/dev/null 2>&1 || log_warn "Failed to write audit entry for ${workspace_id}"
}

# Check and clean up locks for a single workspace
# Args: $1 = workspace_id
# Returns: 0 if cleaned, 1 if no action needed
gc_workspace() {
  local workspace_id="$1"
  local lock_path="${STATE_BASE_PATH}/${workspace_id}/locks/session-lock.json"

  # Read the lock file
  local lock_content
  lock_content=$(read_state_content "$lock_path")

  if [ -z "$lock_content" ]; then
    log_info "  ${workspace_id}: No session lock found"
    return 1
  fi

  # Parse lock fields
  local locked_at ttl_minutes locked_by operation
  locked_at=$(echo "$lock_content" | jq -r '.lockedAt // ""' 2>/dev/null || echo "")
  ttl_minutes=$(echo "$lock_content" | jq -r '.ttlMinutes // '"$DEFAULT_TTL_MINUTES"'' 2>/dev/null || echo "$DEFAULT_TTL_MINUTES")
  locked_by=$(echo "$lock_content" | jq -r '.lockedBy // "unknown"' 2>/dev/null || echo "unknown")
  operation=$(echo "$lock_content" | jq -r '.operation // "unknown"' 2>/dev/null || echo "unknown")

  if [ -z "$locked_at" ]; then
    log_warn "  ${workspace_id}: Lock exists but has no timestamp — marking for cleanup"
    # Treat locks without timestamps as expired
  else
    # Calculate age
    local now_epoch lock_epoch age_minutes
    now_epoch=$(date +%s)
    lock_epoch=$(date -d "$locked_at" +%s 2>/dev/null || echo "0")

    if [ "$lock_epoch" = "0" ]; then
      log_warn "  ${workspace_id}: Lock has unparseable timestamp '${locked_at}'"
      age_minutes=999
    else
      age_minutes=$(( (now_epoch - lock_epoch) / 60 ))
    fi

    if [ "$age_minutes" -le "$ttl_minutes" ]; then
      log_info "  ${workspace_id}: Lock is active (age: ${age_minutes}m / TTL: ${ttl_minutes}m, by: ${locked_by})"
      return 1
    fi

    log_gc "  ${workspace_id}: EXPIRED lock detected (age: ${age_minutes}m > TTL: ${ttl_minutes}m)"
    log_gc "    Locked by: ${locked_by}, operation: ${operation}, at: ${locked_at}"
  fi

  # Delete the expired lock
  if [ "$DRY_RUN" = "true" ]; then
    log_gc "  ${workspace_id}: [DRY RUN] Would delete ${lock_path}"
    return 0
  fi

  local file_sha
  file_sha=$(get_file_sha "$lock_path")

  if [ -z "$file_sha" ]; then
    log_error "  ${workspace_id}: Could not get SHA for lock file"
    return 1
  fi

  if delete_state_file "$lock_path" "$file_sha" \
    "lock-gc: remove expired lock for ${workspace_id} (age: ${age_minutes:-unknown}m, by: ${locked_by})"; then
    log_success "  ${workspace_id}: Expired lock deleted"

    # Write audit entry
    local lock_details
    lock_details=$(jq -n \
      --arg lockedBy "$locked_by" \
      --arg lockedAt "$locked_at" \
      --arg operation "$operation" \
      --argjson ttlMinutes "$ttl_minutes" \
      --argjson ageMinutes "${age_minutes:-0}" \
      --arg action "deleted" \
      '{
        lockedBy: $lockedBy,
        lockedAt: $lockedAt,
        operation: $operation,
        ttlMinutes: $ttlMinutes,
        ageMinutes: $ageMinutes,
        action: $action
      }')

    write_gc_audit "$workspace_id" "$lock_details"
    return 0
  else
    log_error "  ${workspace_id}: Failed to delete expired lock"
    return 1
  fi
}

# ── Main ─────────────────────────────────────────────────────────────────────
main() {
  log_info "=== Workspace Lock Garbage Collector ==="
  log_info "Default TTL: ${DEFAULT_TTL_MINUTES} minutes"
  if [ "$DRY_RUN" = "true" ]; then
    log_warn "DRY RUN MODE — no locks will be deleted"
  fi
  echo ""

  check_prerequisites

  # Determine which workspaces to check
  local workspaces
  if [ -n "$TARGET_WORKSPACE" ]; then
    workspaces="$TARGET_WORKSPACE"
  else
    workspaces=$(list_workspaces)
  fi

  if [ -z "$workspaces" ]; then
    log_warn "No workspaces found on state branch"
    exit 0
  fi

  local total=0
  local cleaned=0
  local active=0
  local errors=0

  while IFS= read -r ws_id; do
    [ -z "$ws_id" ] && continue
    # Skip .gitkeep and non-directory entries
    [[ "$ws_id" == .* ]] && continue

    total=$((total + 1))

    if gc_workspace "$ws_id"; then
      cleaned=$((cleaned + 1))
    else
      # Return code 1 means "no action needed" (not an error)
      active=$((active + 1))
    fi
  done <<< "$workspaces"

  # Summary
  echo ""
  log_success "=== Lock GC Complete ==="
  log_success "Workspaces checked: ${total}"
  log_success "Locks cleaned:      ${cleaned}"
  log_success "Locks active/none:  ${active}"
  if [ "$errors" -gt 0 ]; then
    log_error "Errors:             ${errors}"
  fi
  if [ "$DRY_RUN" = "true" ]; then
    log_warn "(DRY RUN — no actual changes made)"
  fi
}

main "$@"
