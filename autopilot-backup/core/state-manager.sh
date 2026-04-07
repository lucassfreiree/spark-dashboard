#!/usr/bin/env bash
# ============================================================
# State Manager — CRUD Interface for autopilot-state branch
#
# Maps to: GitHub Actions workflows that read/write state via
# the GitHub API on branch autopilot-state in repo
# lucassfreiree/autopilot.
#
# In the original autopilot system, state is managed by
# workflows like bootstrap.yml, seed-workspace.yml,
# health-check.yml, and release-*.yml. This script provides
# the equivalent operations as shell functions that document
# the exact MCP tool calls to make from a Claude Code session.
#
# State path pattern:
#   state/workspaces/{workspace_id}/{file}
#
# Usage:
#   source core/state-manager.sh
#   read_state "ws-default" "workspace.json"
#   write_state "ws-default" "health.json" '{"status":"ok"}'
# ============================================================
set -euo pipefail

# --------------- Configuration ---------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config.json"

STATE_OWNER="lucassfreiree"
STATE_REPO="autopilot"
STATE_BRANCH="autopilot-state"
STATE_BASE_PATH="state/workspaces"

# Load config if available
if [ -f "$CONFIG_FILE" ]; then
  STATE_OWNER=$(jq -r '.github.owner // "lucassfreiree"' "$CONFIG_FILE" 2>/dev/null || echo "lucassfreiree")
  STATE_REPO=$(jq -r '.github.repo // "autopilot"' "$CONFIG_FILE" 2>/dev/null || echo "autopilot")
  STATE_BRANCH=$(jq -r '.github.stateBranch // "autopilot-state"' "$CONFIG_FILE" 2>/dev/null || echo "autopilot-state")
fi

# --------------- Helper Functions ---------------

# Build the full state path for a workspace file
# Args: workspace_id, file_path
_state_path() {
  local workspace_id="$1"
  local file_path="$2"
  echo "${STATE_BASE_PATH}/${workspace_id}/${file_path}"
}

# --------------- Core CRUD Functions ---------------

# read_state — Read a file from the autopilot-state branch
#
# MCP Tool Call:
#   mcp__github__get_file_contents(
#     owner="lucassfreiree",
#     repo="autopilot",
#     path="state/workspaces/{workspace_id}/{file_path}",
#     branch="autopilot-state"
#   )
#
# Args:
#   $1 - workspace_id (e.g., "ws-default")
#   $2 - file_path relative to workspace dir (e.g., "workspace.json")
#
# Returns: File content (JSON) on stdout, or error on stderr
read_state() {
  local workspace_id="${1:?ERROR: workspace_id is required}"
  local file_path="${2:?ERROR: file_path is required}"
  local full_path
  full_path=$(_state_path "$workspace_id" "$file_path")

  echo "# MCP Call: mcp__github__get_file_contents" >&2
  echo "#   owner=${STATE_OWNER}" >&2
  echo "#   repo=${STATE_REPO}" >&2
  echo "#   path=${full_path}" >&2
  echo "#   branch=${STATE_BRANCH}" >&2

  # In a Claude Code session, execute:
  # mcp__github__get_file_contents(
  #   owner="lucassfreiree",
  #   repo="autopilot",
  #   path="${full_path}",
  #   branch="autopilot-state"
  # )

  # CLI fallback using gh API:
  if command -v gh &>/dev/null; then
    gh api "repos/${STATE_OWNER}/${STATE_REPO}/contents/${full_path}?ref=${STATE_BRANCH}" \
      --jq '.content' 2>/dev/null | base64 -d 2>/dev/null || {
      echo "ERROR: Failed to read ${full_path} from ${STATE_BRANCH}" >&2
      return 1
    }
  else
    echo "ERROR: gh CLI not available. Use MCP tool call in Claude Code session." >&2
    return 1
  fi
}

# write_state — Write/update a file on the autopilot-state branch
#
# MCP Tool Call:
#   mcp__github__create_or_update_file(
#     owner="lucassfreiree",
#     repo="autopilot",
#     path="state/workspaces/{workspace_id}/{file_path}",
#     content="{base64-encoded content}",
#     message="state: update {file_path} for {workspace_id}",
#     branch="autopilot-state",
#     sha="{current file sha, if updating existing file}"
#   )
#
# Args:
#   $1 - workspace_id
#   $2 - file_path relative to workspace dir
#   $3 - content (JSON string)
#   $4 - commit message (optional, auto-generated if omitted)
#
# Returns: 0 on success, 1 on error
write_state() {
  local workspace_id="${1:?ERROR: workspace_id is required}"
  local file_path="${2:?ERROR: file_path is required}"
  local content="${3:?ERROR: content is required}"
  local message="${4:-state: update ${file_path} for ${workspace_id}}"
  local full_path
  full_path=$(_state_path "$workspace_id" "$file_path")

  # Validate content is valid JSON
  if ! echo "$content" | jq empty 2>/dev/null; then
    echo "ERROR: Content is not valid JSON" >&2
    return 1
  fi

  echo "# MCP Call: mcp__github__create_or_update_file" >&2
  echo "#   owner=${STATE_OWNER}" >&2
  echo "#   repo=${STATE_REPO}" >&2
  echo "#   path=${full_path}" >&2
  echo "#   content=(base64 encoded)" >&2
  echo "#   message=${message}" >&2
  echo "#   branch=${STATE_BRANCH}" >&2

  # In a Claude Code session, execute:
  # 1. First get current SHA (if file exists):
  #    mcp__github__get_file_contents(owner, repo, path, branch) -> extract sha
  # 2. Then write:
  #    mcp__github__create_or_update_file(owner, repo, path, content, message, branch, sha)

  # CLI fallback using gh API:
  if command -v gh &>/dev/null; then
    local encoded_content
    encoded_content=$(echo "$content" | base64 -w 0)

    # Try to get existing file SHA for update
    local current_sha
    current_sha=$(gh api "repos/${STATE_OWNER}/${STATE_REPO}/contents/${full_path}?ref=${STATE_BRANCH}" \
      --jq '.sha' 2>/dev/null || echo "")

    local payload
    if [ -n "$current_sha" ]; then
      payload=$(jq -n \
        --arg msg "$message" \
        --arg content "$encoded_content" \
        --arg branch "$STATE_BRANCH" \
        --arg sha "$current_sha" \
        '{message: $msg, content: $content, branch: $branch, sha: $sha}')
    else
      payload=$(jq -n \
        --arg msg "$message" \
        --arg content "$encoded_content" \
        --arg branch "$STATE_BRANCH" \
        '{message: $msg, content: $content, branch: $branch}')
    fi

    echo "$payload" | gh api "repos/${STATE_OWNER}/${STATE_REPO}/contents/${full_path}" \
      --method PUT --input - >/dev/null 2>&1 || {
      echo "ERROR: Failed to write ${full_path} to ${STATE_BRANCH}" >&2
      return 1
    }
    echo "OK: Written ${full_path}" >&2
  else
    echo "ERROR: gh CLI not available. Use MCP tool call in Claude Code session." >&2
    return 1
  fi
}

# --------------- Specialized Read Functions ---------------

# read_release_state — Read release-state.json for a component
#
# MCP Tool Call:
#   mcp__github__get_file_contents(
#     owner="lucassfreiree", repo="autopilot",
#     path="state/workspaces/{ws_id}/{component}-release-state.json",
#     branch="autopilot-state"
#   )
#
# Args:
#   $1 - workspace_id
#   $2 - component ("controller" or "agent")
#
# Returns: Release state JSON on stdout
read_release_state() {
  local workspace_id="${1:?ERROR: workspace_id is required}"
  local component="${2:?ERROR: component is required (controller|agent)}"

  if [[ "$component" != "controller" && "$component" != "agent" ]]; then
    echo "ERROR: component must be 'controller' or 'agent', got '${component}'" >&2
    return 1
  fi

  read_state "$workspace_id" "${component}-release-state.json"
}

# write_release_state — Update release state for a component
#
# MCP Tool Call:
#   mcp__github__create_or_update_file(
#     owner="lucassfreiree", repo="autopilot",
#     path="state/workspaces/{ws_id}/{component}-release-state.json",
#     content=..., message=..., branch="autopilot-state"
#   )
#
# Args:
#   $1 - workspace_id
#   $2 - component ("controller" or "agent")
#   $3 - content (JSON string)
write_release_state() {
  local workspace_id="${1:?ERROR: workspace_id is required}"
  local component="${2:?ERROR: component is required (controller|agent)}"
  local content="${3:?ERROR: content is required}"

  if [[ "$component" != "controller" && "$component" != "agent" ]]; then
    echo "ERROR: component must be 'controller' or 'agent', got '${component}'" >&2
    return 1
  fi

  write_state "$workspace_id" "${component}-release-state.json" "$content" \
    "state: update ${component} release state for ${workspace_id}"
}

# read_workspace_config — Read workspace.json for a workspace
#
# MCP Tool Call:
#   mcp__github__get_file_contents(
#     owner="lucassfreiree", repo="autopilot",
#     path="state/workspaces/{ws_id}/workspace.json",
#     branch="autopilot-state"
#   )
#
# Args:
#   $1 - workspace_id
#
# Returns: Workspace config JSON on stdout
read_workspace_config() {
  local workspace_id="${1:?ERROR: workspace_id is required}"
  read_state "$workspace_id" "workspace.json"
}

# list_workspaces — List all workspaces on the state branch
#
# MCP Tool Call:
#   mcp__github__get_file_contents(
#     owner="lucassfreiree", repo="autopilot",
#     path="state/workspaces",
#     branch="autopilot-state"
#   )
#
# Returns: List of workspace IDs, one per line
list_workspaces() {
  echo "# MCP Call: mcp__github__get_file_contents" >&2
  echo "#   owner=${STATE_OWNER}" >&2
  echo "#   repo=${STATE_REPO}" >&2
  echo "#   path=${STATE_BASE_PATH}" >&2
  echo "#   branch=${STATE_BRANCH}" >&2

  # CLI fallback:
  if command -v gh &>/dev/null; then
    gh api "repos/${STATE_OWNER}/${STATE_REPO}/contents/${STATE_BASE_PATH}?ref=${STATE_BRANCH}" \
      --jq '.[].name' 2>/dev/null || {
      echo "ERROR: Failed to list workspaces" >&2
      return 1
    }
  else
    echo "ERROR: gh CLI not available. Use MCP tool call in Claude Code session." >&2
    return 1
  fi
}

# read_health — Read health.json for a workspace
#
# MCP Tool Call:
#   mcp__github__get_file_contents(
#     owner="lucassfreiree", repo="autopilot",
#     path="state/workspaces/{ws_id}/health.json",
#     branch="autopilot-state"
#   )
#
# Args:
#   $1 - workspace_id
#
# Returns: Health state JSON on stdout
read_health() {
  local workspace_id="${1:?ERROR: workspace_id is required}"
  read_state "$workspace_id" "health.json"
}

# write_health — Update health.json for a workspace
#
# MCP Tool Call:
#   mcp__github__create_or_update_file(
#     owner="lucassfreiree", repo="autopilot",
#     path="state/workspaces/{ws_id}/health.json",
#     content=..., message=..., branch="autopilot-state"
#   )
#
# Args:
#   $1 - workspace_id
#   $2 - content (JSON string)
write_health() {
  local workspace_id="${1:?ERROR: workspace_id is required}"
  local content="${2:?ERROR: content is required}"
  write_state "$workspace_id" "health.json" "$content" \
    "state: update health for ${workspace_id}"
}

# --------------- Main (for testing) ---------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-help}" in
    read)
      read_state "${2:-}" "${3:-}"
      ;;
    write)
      write_state "${2:-}" "${3:-}" "${4:-}"
      ;;
    read-release)
      read_release_state "${2:-}" "${3:-}"
      ;;
    write-release)
      write_release_state "${2:-}" "${3:-}" "${4:-}"
      ;;
    read-workspace)
      read_workspace_config "${2:-}"
      ;;
    list)
      list_workspaces
      ;;
    read-health)
      read_health "${2:-}"
      ;;
    write-health)
      write_health "${2:-}" "${3:-}"
      ;;
    help|*)
      echo "Usage: $0 {read|write|read-release|write-release|read-workspace|list|read-health|write-health} [args...]"
      echo ""
      echo "Commands:"
      echo "  read <workspace_id> <file_path>              Read a state file"
      echo "  write <workspace_id> <file_path> <content>   Write a state file"
      echo "  read-release <workspace_id> <component>      Read release state"
      echo "  write-release <workspace_id> <component> <content>  Write release state"
      echo "  read-workspace <workspace_id>                Read workspace.json"
      echo "  list                                         List all workspaces"
      echo "  read-health <workspace_id>                   Read health.json"
      echo "  write-health <workspace_id> <content>        Write health.json"
      ;;
  esac
fi
