#!/usr/bin/env bash
# ============================================================
# Audit Writer — Immutable Audit Trail for All Operations
#
# Maps to: The audit step (Stage 6) in apply-source-change.yml,
# and audit entries written by release-*.yml, health-check.yml,
# backup-state.yml, and other state-mutating workflows.
#
# Every state mutation in the autopilot system MUST produce an
# audit entry. Entries are immutable (write-once, never updated).
#
# Audit path pattern:
#   state/workspaces/{ws_id}/audit/{timestamp}-{operation}.json
#
# Audit schema (from schemas/audit.schema.json):
#   Required: operation, workspaceId, timestamp, runId
#   Optional: runUrl, component, version, sha, tag, status,
#             steps, ciResult, promoted, stages, changeType,
#             commitMessage, preExistingFailure, gateDecision,
#             error, detail
#
# Usage:
#   source core/audit-writer.sh
#   write_audit "ws-default" "agent-release" "success" "Released v2.3.4" "claude-code"
# ============================================================
set -euo pipefail

# --------------- Configuration ---------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config.json"

AUDIT_OWNER="lucassfreiree"
AUDIT_REPO="autopilot"
AUDIT_BRANCH="autopilot-state"
AUDIT_BASE_PATH="state/workspaces"

# Load config if available
if [ -f "$CONFIG_FILE" ]; then
  AUDIT_OWNER=$(jq -r '.github.owner // "lucassfreiree"' "$CONFIG_FILE" 2>/dev/null || echo "lucassfreiree")
  AUDIT_REPO=$(jq -r '.github.repo // "autopilot"' "$CONFIG_FILE" 2>/dev/null || echo "autopilot")
  AUDIT_BRANCH=$(jq -r '.github.stateBranch // "autopilot-state"' "$CONFIG_FILE" 2>/dev/null || echo "autopilot-state")
fi

# --------------- Helper Functions ---------------

# Get current UTC ISO8601 timestamp
_audit_utc_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Get timestamp suitable for filename (no colons)
_audit_file_timestamp() {
  date -u +"%Y%m%d-%H%M%S"
}

# Generate a unique run ID
_audit_run_id() {
  echo "run-$(date -u +%Y%m%d%H%M%S)-$$-${RANDOM}"
}

# Build audit file path
# Args: workspace_id, timestamp_str, operation
_audit_path() {
  local workspace_id="$1"
  local timestamp_str="$2"
  local operation="$3"
  echo "${AUDIT_BASE_PATH}/${workspace_id}/audit/${timestamp_str}-${operation}.json"
}

# --------------- Core Audit Functions ---------------

# write_audit — Write an immutable audit entry
#
# MCP Tool Call:
#   mcp__github__create_or_update_file(
#     owner="lucassfreiree",
#     repo="autopilot",
#     path="state/workspaces/{ws_id}/audit/{timestamp}-{operation}.json",
#     content=<base64 encoded audit JSON>,
#     message="audit: {operation} {status} for {workspace_id}",
#     branch="autopilot-state"
#   )
#
# Args:
#   $1 - workspace_id (e.g., "ws-default")
#   $2 - operation (e.g., "agent-release", "controller-release", "health-check")
#   $3 - status ("success", "failure", "skipped")
#   $4 - detail (human-readable description of what happened)
#   $5 - agent (who performed the operation, e.g., "claude-code")
#   $6 - extra_json (optional — additional JSON fields to merge, e.g., '{"version":"2.3.4","sha":"abc123"}')
#
# Returns: 0 on success, 1 on error. Audit JSON on stdout.
write_audit() {
  local workspace_id="${1:?ERROR: workspace_id is required}"
  local operation="${2:?ERROR: operation is required}"
  local status="${3:?ERROR: status is required (success|failure|skipped)}"
  local detail="${4:-}"
  local agent="${5:-claude-code}"
  local extra_json="${6:-{\}}"

  # Validate status
  case "$status" in
    success|failure|skipped) ;;
    *)
      echo "ERROR: Invalid status '${status}'. Must be one of: success, failure, skipped" >&2
      return 1
      ;;
  esac

  local now
  now=$(_audit_utc_now)
  local file_ts
  file_ts=$(_audit_file_timestamp)
  local run_id
  run_id=$(_audit_run_id)
  local audit_path
  audit_path=$(_audit_path "$workspace_id" "$file_ts" "$operation")

  # Build audit JSON per audit.schema.json
  local audit_json
  audit_json=$(jq -n \
    --arg operation "$operation" \
    --arg workspaceId "$workspace_id" \
    --arg timestamp "$now" \
    --arg runId "$run_id" \
    --arg status "$status" \
    --arg detail "$detail" \
    --arg agent "$agent" \
    '{
      operation: $operation,
      workspaceId: $workspaceId,
      timestamp: $timestamp,
      runId: $runId,
      status: $status,
      detail: $detail,
      component: $agent
    }')

  # Merge extra JSON fields if provided
  if [ "$extra_json" != "{}" ] && [ -n "$extra_json" ]; then
    if echo "$extra_json" | jq empty 2>/dev/null; then
      audit_json=$(echo "$audit_json" "$extra_json" | jq -s '.[0] * .[1]')
    else
      echo "WARNING: extra_json is not valid JSON, ignoring: ${extra_json}" >&2
    fi
  fi

  echo "# MCP Call: mcp__github__create_or_update_file" >&2
  echo "#   owner=${AUDIT_OWNER}" >&2
  echo "#   repo=${AUDIT_REPO}" >&2
  echo "#   path=${audit_path}" >&2
  echo "#   message=audit: ${operation} ${status} for ${workspace_id}" >&2
  echo "#   branch=${AUDIT_BRANCH}" >&2

  # Write via gh CLI fallback
  if command -v gh &>/dev/null; then
    local encoded_content
    encoded_content=$(echo "$audit_json" | base64 -w 0)

    local payload
    payload=$(jq -n \
      --arg msg "audit: ${operation} ${status} for ${workspace_id}" \
      --arg content "$encoded_content" \
      --arg branch "$AUDIT_BRANCH" \
      '{message: $msg, content: $content, branch: $branch}')

    echo "$payload" | gh api "repos/${AUDIT_OWNER}/${AUDIT_REPO}/contents/${audit_path}" \
      --method PUT --input - >/dev/null 2>&1 || {
      echo "ERROR: Failed to write audit entry to ${audit_path}" >&2
      return 1
    }

    echo "OK: Audit entry written to ${audit_path}" >&2
  else
    echo "ERROR: gh CLI not available. Use MCP tool calls in Claude Code session." >&2
    return 1
  fi

  echo "$audit_json"
}

# read_audit_history — Read recent audit entries for a workspace
#
# MCP Tool Call:
#   mcp__github__get_file_contents(
#     owner="lucassfreiree",
#     repo="autopilot",
#     path="state/workspaces/{ws_id}/audit",
#     branch="autopilot-state"
#   )
#   Then for each entry file:
#   mcp__github__get_file_contents(
#     owner="lucassfreiree",
#     repo="autopilot",
#     path="state/workspaces/{ws_id}/audit/{filename}",
#     branch="autopilot-state"
#   )
#
# Args:
#   $1 - workspace_id
#   $2 - limit (optional, default 10 — number of most recent entries)
#   $3 - operation_filter (optional — filter by operation name)
#
# Returns: JSON array of audit entries on stdout (most recent first)
read_audit_history() {
  local workspace_id="${1:?ERROR: workspace_id is required}"
  local limit="${2:-10}"
  local operation_filter="${3:-}"
  local audit_dir="${AUDIT_BASE_PATH}/${workspace_id}/audit"

  echo "# MCP Call: mcp__github__get_file_contents" >&2
  echo "#   owner=${AUDIT_OWNER}, repo=${AUDIT_REPO}" >&2
  echo "#   path=${audit_dir}, branch=${AUDIT_BRANCH}" >&2

  if command -v gh &>/dev/null; then
    # List audit directory contents
    local file_list
    file_list=$(gh api "repos/${AUDIT_OWNER}/${AUDIT_REPO}/contents/${audit_dir}?ref=${AUDIT_BRANCH}" \
      --jq '.[].name' 2>/dev/null || echo "")

    if [ -z "$file_list" ]; then
      echo "INFO: No audit entries found for ${workspace_id}" >&2
      echo "[]"
      return 0
    fi

    # Filter by operation if specified
    if [ -n "$operation_filter" ]; then
      file_list=$(echo "$file_list" | grep -- "-${operation_filter}.json" || echo "")
    fi

    # Sort reverse (newest first) and limit
    file_list=$(echo "$file_list" | sort -r | head -n "$limit")

    if [ -z "$file_list" ]; then
      echo "[]"
      return 0
    fi

    # Read each audit entry
    local entries="[]"
    while IFS= read -r filename; do
      [ -z "$filename" ] && continue
      local entry
      entry=$(gh api "repos/${AUDIT_OWNER}/${AUDIT_REPO}/contents/${audit_dir}/${filename}?ref=${AUDIT_BRANCH}" \
        --jq '.content' 2>/dev/null | base64 -d 2>/dev/null || echo "")

      if [ -n "$entry" ] && echo "$entry" | jq empty 2>/dev/null; then
        entries=$(echo "$entries" | jq --argjson e "$entry" '. + [$e]')
      fi
    done <<< "$file_list"

    echo "$entries"
  else
    echo "ERROR: gh CLI not available. Use MCP tool calls in Claude Code session." >&2
    return 1
  fi
}

# --------------- Main (for testing) ---------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-help}" in
    write)
      write_audit "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-claude-code}" "${7:-{\}}"
      ;;
    history)
      read_audit_history "${2:-}" "${3:-10}" "${4:-}"
      ;;
    help|*)
      echo "Usage: $0 {write|history} [args...]"
      echo ""
      echo "Commands:"
      echo "  write <workspace_id> <operation> <status> [detail] [agent] [extra_json]"
      echo "  history <workspace_id> [limit] [operation_filter]"
      echo ""
      echo "Examples:"
      echo "  $0 write ws-default agent-release success 'Released v2.3.4' claude-code"
      echo "  $0 history ws-default 5 agent-release"
      ;;
  esac
fi
