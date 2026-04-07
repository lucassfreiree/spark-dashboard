#!/usr/bin/env bash
# ============================================================
# Session Guard — Multi-Agent Concurrency Lock System
#
# Maps to: session-guard.yml workflow in the original autopilot
# system. Prevents multiple agents (Claude Code, Codex, etc.)
# from concurrently modifying state or corporate repos.
#
# Lock is stored on the autopilot-state branch at:
#   state/workspaces/{workspace_id}/locks/session-lock.json
#
# Lock schema (from schemas/lock.schema.json):
#   Required: lockId, workspaceId, operation, acquiredAt, acquiredBy
#   Optional: runId, expiresAt, released, releasedAt, agentId, sessionId
#
# Operations enum: controller-release, agent-release, bootstrap,
#                  backup, seed
#
# Usage:
#   source core/session-guard.sh
#   acquire_lock "ws-default" "claude-code" "agent-release" 30
#   release_lock "ws-default"
# ============================================================
set -euo pipefail

# --------------- Configuration ---------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config.json"

GUARD_OWNER="lucassfreiree"
GUARD_REPO="autopilot"
GUARD_BRANCH="autopilot-state"
GUARD_BASE_PATH="state/workspaces"

# Load config if available
if [ -f "$CONFIG_FILE" ]; then
  GUARD_OWNER=$(jq -r '.github.owner // "lucassfreiree"' "$CONFIG_FILE" 2>/dev/null || echo "lucassfreiree")
  GUARD_REPO=$(jq -r '.github.repo // "autopilot"' "$CONFIG_FILE" 2>/dev/null || echo "autopilot")
  GUARD_BRANCH=$(jq -r '.github.stateBranch // "autopilot-state"' "$CONFIG_FILE" 2>/dev/null || echo "autopilot-state")
fi

# --------------- Helper Functions ---------------

# Build the lock file path for a workspace
# Args: workspace_id
_lock_path() {
  local workspace_id="$1"
  echo "${GUARD_BASE_PATH}/${workspace_id}/locks/session-lock.json"
}

# Generate a unique lock ID
_generate_lock_id() {
  echo "lock-$(date -u +%Y%m%d%H%M%S)-$$-${RANDOM}"
}

# Get current UTC ISO8601 timestamp
_utc_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Calculate expiry timestamp from now + minutes
# Args: ttl_minutes
_expiry_time() {
  local ttl_minutes="${1:-30}"
  date -u -d "+${ttl_minutes} minutes" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
    date -u -v "+${ttl_minutes}M" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

# --------------- Core Lock Functions ---------------

# acquire_lock — Acquire a session lock for a workspace
#
# MCP Tool Calls:
#   1. Check existing lock:
#      mcp__github__get_file_contents(
#        owner="lucassfreiree", repo="autopilot",
#        path="state/workspaces/{ws_id}/locks/session-lock.json",
#        branch="autopilot-state"
#      )
#   2. If no lock or expired, write new lock:
#      mcp__github__create_or_update_file(
#        owner="lucassfreiree", repo="autopilot",
#        path="state/workspaces/{ws_id}/locks/session-lock.json",
#        content=<base64 encoded lock JSON>,
#        message="lock: acquire session lock for {ws_id} by {agent}",
#        branch="autopilot-state",
#        sha=<current file sha if exists>
#      )
#
# Args:
#   $1 - workspace_id (e.g., "ws-default")
#   $2 - agent_name (e.g., "claude-code")
#   $3 - operation (e.g., "agent-release", "controller-release", "bootstrap", "backup", "seed")
#   $4 - ttl_minutes (optional, default 30)
#
# Returns: 0 if lock acquired, 1 if lock held by another agent
acquire_lock() {
  local workspace_id="${1:?ERROR: workspace_id is required}"
  local agent_name="${2:?ERROR: agent_name is required}"
  local operation="${3:?ERROR: operation is required}"
  local ttl_minutes="${4:-30}"
  local lock_path
  lock_path=$(_lock_path "$workspace_id")

  # Validate operation
  case "$operation" in
    controller-release|agent-release|bootstrap|backup|seed) ;;
    *)
      echo "ERROR: Invalid operation '${operation}'. Must be one of: controller-release, agent-release, bootstrap, backup, seed" >&2
      return 1
      ;;
  esac

  echo "# Step 1: Check existing lock" >&2
  echo "# MCP Call: mcp__github__get_file_contents" >&2
  echo "#   owner=${GUARD_OWNER}, repo=${GUARD_REPO}" >&2
  echo "#   path=${lock_path}, branch=${GUARD_BRANCH}" >&2

  # Check for existing lock
  local existing_lock=""
  if command -v gh &>/dev/null; then
    existing_lock=$(gh api "repos/${GUARD_OWNER}/${GUARD_REPO}/contents/${lock_path}?ref=${GUARD_BRANCH}" \
      --jq '.content' 2>/dev/null | base64 -d 2>/dev/null || echo "")
  fi

  if [ -n "$existing_lock" ]; then
    # Check if existing lock is released or expired
    local is_released
    is_released=$(echo "$existing_lock" | jq -r '.released // false' 2>/dev/null || echo "false")

    if [ "$is_released" = "true" ]; then
      echo "INFO: Previous lock was released, proceeding to acquire" >&2
    else
      # Check expiry
      local expires_at
      expires_at=$(echo "$existing_lock" | jq -r '.expiresAt // ""' 2>/dev/null || echo "")

      if [ -n "$expires_at" ] && ! _is_expired "$expires_at"; then
        local locked_by
        locked_by=$(echo "$existing_lock" | jq -r '.acquiredBy // "unknown"' 2>/dev/null || echo "unknown")
        local locked_op
        locked_op=$(echo "$existing_lock" | jq -r '.operation // "unknown"' 2>/dev/null || echo "unknown")
        echo "ERROR: Lock held by '${locked_by}' for operation '${locked_op}', expires at ${expires_at}" >&2
        return 1
      fi
      echo "INFO: Previous lock expired, proceeding to acquire" >&2
    fi
  fi

  # Build lock JSON per lock.schema.json
  local lock_id
  lock_id=$(_generate_lock_id)
  local now
  now=$(_utc_now)
  local expires
  expires=$(_expiry_time "$ttl_minutes")

  local lock_json
  lock_json=$(jq -n \
    --arg lockId "$lock_id" \
    --arg workspaceId "$workspace_id" \
    --arg operation "$operation" \
    --arg acquiredAt "$now" \
    --arg acquiredBy "$agent_name" \
    --arg expiresAt "$expires" \
    --argjson released false \
    --arg agentId "$agent_name" \
    --arg sessionId "session-$(date -u +%Y%m%d%H%M%S)" \
    '{
      lockId: $lockId,
      workspaceId: $workspaceId,
      operation: $operation,
      acquiredAt: $acquiredAt,
      acquiredBy: $acquiredBy,
      expiresAt: $expiresAt,
      released: $released,
      agentId: $agentId,
      sessionId: $sessionId
    }')

  echo "# Step 2: Write new lock" >&2
  echo "# MCP Call: mcp__github__create_or_update_file" >&2
  echo "#   owner=${GUARD_OWNER}, repo=${GUARD_REPO}" >&2
  echo "#   path=${lock_path}, branch=${GUARD_BRANCH}" >&2
  echo "#   message=lock: acquire session lock for ${workspace_id} by ${agent_name}" >&2

  # Write lock via gh CLI fallback
  if command -v gh &>/dev/null; then
    local encoded_content
    encoded_content=$(echo "$lock_json" | base64 -w 0)

    local current_sha
    current_sha=$(gh api "repos/${GUARD_OWNER}/${GUARD_REPO}/contents/${lock_path}?ref=${GUARD_BRANCH}" \
      --jq '.sha' 2>/dev/null || echo "")

    local payload
    if [ -n "$current_sha" ]; then
      payload=$(jq -n \
        --arg msg "lock: acquire session lock for ${workspace_id} by ${agent_name}" \
        --arg content "$encoded_content" \
        --arg branch "$GUARD_BRANCH" \
        --arg sha "$current_sha" \
        '{message: $msg, content: $content, branch: $branch, sha: $sha}')
    else
      payload=$(jq -n \
        --arg msg "lock: acquire session lock for ${workspace_id} by ${agent_name}" \
        --arg content "$encoded_content" \
        --arg branch "$GUARD_BRANCH" \
        '{message: $msg, content: $content, branch: $branch}')
    fi

    echo "$payload" | gh api "repos/${GUARD_OWNER}/${GUARD_REPO}/contents/${lock_path}" \
      --method PUT --input - >/dev/null 2>&1 || {
      echo "ERROR: Failed to write lock to ${lock_path}" >&2
      return 1
    }
  else
    echo "ERROR: gh CLI not available. Use MCP tool calls in Claude Code session." >&2
    return 1
  fi

  echo "OK: Lock acquired — lockId=${lock_id}, expires=${expires}" >&2
  echo "$lock_json"
}

# release_lock — Release a session lock
#
# MCP Tool Calls:
#   1. Read current lock to get SHA and lockId:
#      mcp__github__get_file_contents(...)
#   2. Update lock with released=true:
#      mcp__github__create_or_update_file(...)
#
# Args:
#   $1 - workspace_id
#
# Returns: 0 on success, 1 on error
release_lock() {
  local workspace_id="${1:?ERROR: workspace_id is required}"
  local lock_path
  lock_path=$(_lock_path "$workspace_id")

  echo "# MCP Call: mcp__github__get_file_contents (read current lock)" >&2
  echo "#   path=${lock_path}, branch=${GUARD_BRANCH}" >&2

  if command -v gh &>/dev/null; then
    local response
    response=$(gh api "repos/${GUARD_OWNER}/${GUARD_REPO}/contents/${lock_path}?ref=${GUARD_BRANCH}" 2>/dev/null || echo "")

    if [ -z "$response" ]; then
      echo "ERROR: No lock found at ${lock_path}" >&2
      return 1
    fi

    local current_lock
    current_lock=$(echo "$response" | jq -r '.content' 2>/dev/null | base64 -d 2>/dev/null || echo "")
    local current_sha
    current_sha=$(echo "$response" | jq -r '.sha' 2>/dev/null || echo "")

    if [ -z "$current_lock" ]; then
      echo "ERROR: Could not decode lock content" >&2
      return 1
    fi

    # Update lock: set released=true, releasedAt=now
    local now
    now=$(_utc_now)
    local updated_lock
    updated_lock=$(echo "$current_lock" | jq \
      --arg releasedAt "$now" \
      '. + {released: true, releasedAt: $releasedAt}')

    local encoded_content
    encoded_content=$(echo "$updated_lock" | base64 -w 0)

    echo "# MCP Call: mcp__github__create_or_update_file (release lock)" >&2
    echo "#   path=${lock_path}, branch=${GUARD_BRANCH}" >&2

    local payload
    payload=$(jq -n \
      --arg msg "lock: release session lock for ${workspace_id}" \
      --arg content "$encoded_content" \
      --arg branch "$GUARD_BRANCH" \
      --arg sha "$current_sha" \
      '{message: $msg, content: $content, branch: $branch, sha: $sha}')

    echo "$payload" | gh api "repos/${GUARD_OWNER}/${GUARD_REPO}/contents/${lock_path}" \
      --method PUT --input - >/dev/null 2>&1 || {
      echo "ERROR: Failed to release lock at ${lock_path}" >&2
      return 1
    }

    echo "OK: Lock released for ${workspace_id}" >&2
  else
    echo "ERROR: gh CLI not available. Use MCP tool calls in Claude Code session." >&2
    return 1
  fi
}

# check_lock — Check current lock status for a workspace
#
# MCP Tool Call:
#   mcp__github__get_file_contents(
#     owner="lucassfreiree", repo="autopilot",
#     path="state/workspaces/{ws_id}/locks/session-lock.json",
#     branch="autopilot-state"
#   )
#
# Args:
#   $1 - workspace_id
#
# Returns: Lock JSON on stdout, or empty if no lock
check_lock() {
  local workspace_id="${1:?ERROR: workspace_id is required}"
  local lock_path
  lock_path=$(_lock_path "$workspace_id")

  echo "# MCP Call: mcp__github__get_file_contents" >&2
  echo "#   owner=${GUARD_OWNER}, repo=${GUARD_REPO}" >&2
  echo "#   path=${lock_path}, branch=${GUARD_BRANCH}" >&2

  if command -v gh &>/dev/null; then
    local lock_content
    lock_content=$(gh api "repos/${GUARD_OWNER}/${GUARD_REPO}/contents/${lock_path}?ref=${GUARD_BRANCH}" \
      --jq '.content' 2>/dev/null | base64 -d 2>/dev/null || echo "")

    if [ -z "$lock_content" ]; then
      echo "INFO: No lock found for ${workspace_id}" >&2
      return 0
    fi

    local is_released
    is_released=$(echo "$lock_content" | jq -r '.released // false' 2>/dev/null || echo "false")
    local locked_by
    locked_by=$(echo "$lock_content" | jq -r '.acquiredBy // "unknown"' 2>/dev/null || echo "unknown")
    local operation
    operation=$(echo "$lock_content" | jq -r '.operation // "unknown"' 2>/dev/null || echo "unknown")
    local expires_at
    expires_at=$(echo "$lock_content" | jq -r '.expiresAt // "unknown"' 2>/dev/null || echo "unknown")

    if [ "$is_released" = "true" ]; then
      echo "INFO: Lock exists but is RELEASED (by=${locked_by}, op=${operation})" >&2
    else
      echo "INFO: Lock ACTIVE — by=${locked_by}, op=${operation}, expires=${expires_at}" >&2
    fi

    echo "$lock_content"
  else
    echo "ERROR: gh CLI not available. Use MCP tool calls in Claude Code session." >&2
    return 1
  fi
}

# is_lock_expired — Check if a lock's TTL has passed
#
# Args:
#   $1 - expiresAt ISO8601 timestamp
#
# Returns: 0 if expired, 1 if still valid
is_lock_expired() {
  local expires_at="${1:?ERROR: expiresAt timestamp is required}"
  _is_expired "$expires_at"
}

# Internal: check if a timestamp is in the past
_is_expired() {
  local expires_at="$1"

  # Convert expiresAt to epoch seconds
  local expires_epoch
  expires_epoch=$(date -u -d "$expires_at" +%s 2>/dev/null || \
    date -u -jf "%Y-%m-%dT%H:%M:%SZ" "$expires_at" +%s 2>/dev/null || echo "0")

  local now_epoch
  now_epoch=$(date -u +%s)

  if [ "$expires_epoch" -le "$now_epoch" ]; then
    return 0  # expired
  else
    return 1  # still valid
  fi
}

# force_release_lock — Emergency force release of a lock
#
# WARNING: Use only when a lock is stuck and the holding agent
# is confirmed dead/unresponsive. This bypasses normal release
# checks and forcibly marks the lock as released.
#
# MCP Tool Calls: Same as release_lock but with force flag in message
#
# Args:
#   $1 - workspace_id
#   $2 - reason (required — must document why force release)
#
# Returns: 0 on success, 1 on error
force_release_lock() {
  local workspace_id="${1:?ERROR: workspace_id is required}"
  local reason="${2:?ERROR: reason is required for force release}"
  local lock_path
  lock_path=$(_lock_path "$workspace_id")

  echo "WARNING: Force releasing lock for ${workspace_id}" >&2
  echo "WARNING: Reason: ${reason}" >&2

  if command -v gh &>/dev/null; then
    local response
    response=$(gh api "repos/${GUARD_OWNER}/${GUARD_REPO}/contents/${lock_path}?ref=${GUARD_BRANCH}" 2>/dev/null || echo "")

    if [ -z "$response" ]; then
      echo "INFO: No lock found at ${lock_path} — nothing to force release" >&2
      return 0
    fi

    local current_lock
    current_lock=$(echo "$response" | jq -r '.content' 2>/dev/null | base64 -d 2>/dev/null || echo "")
    local current_sha
    current_sha=$(echo "$response" | jq -r '.sha' 2>/dev/null || echo "")

    local now
    now=$(_utc_now)
    local updated_lock
    updated_lock=$(echo "$current_lock" | jq \
      --arg releasedAt "$now" \
      --arg reason "$reason" \
      '. + {released: true, releasedAt: $releasedAt, forceReleaseReason: $reason}')

    local encoded_content
    encoded_content=$(echo "$updated_lock" | base64 -w 0)

    local payload
    payload=$(jq -n \
      --arg msg "lock: FORCE release session lock for ${workspace_id} — ${reason}" \
      --arg content "$encoded_content" \
      --arg branch "$GUARD_BRANCH" \
      --arg sha "$current_sha" \
      '{message: $msg, content: $content, branch: $branch, sha: $sha}')

    echo "$payload" | gh api "repos/${GUARD_OWNER}/${GUARD_REPO}/contents/${lock_path}" \
      --method PUT --input - >/dev/null 2>&1 || {
      echo "ERROR: Failed to force release lock at ${lock_path}" >&2
      return 1
    }

    echo "OK: Lock FORCE released for ${workspace_id}" >&2
  else
    echo "ERROR: gh CLI not available. Use MCP tool calls in Claude Code session." >&2
    return 1
  fi
}

# --------------- Main (for testing) ---------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-help}" in
    acquire)
      acquire_lock "${2:-}" "${3:-}" "${4:-}" "${5:-30}"
      ;;
    release)
      release_lock "${2:-}"
      ;;
    check)
      check_lock "${2:-}"
      ;;
    is-expired)
      if is_lock_expired "${2:-}"; then
        echo "EXPIRED"
      else
        echo "VALID"
      fi
      ;;
    force-release)
      force_release_lock "${2:-}" "${3:-}"
      ;;
    help|*)
      echo "Usage: $0 {acquire|release|check|is-expired|force-release} [args...]"
      echo ""
      echo "Commands:"
      echo "  acquire <workspace_id> <agent_name> <operation> [ttl_minutes]"
      echo "  release <workspace_id>"
      echo "  check <workspace_id>"
      echo "  is-expired <expiresAt_timestamp>"
      echo "  force-release <workspace_id> <reason>"
      ;;
  esac
fi
