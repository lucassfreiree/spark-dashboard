#!/usr/bin/env bash
# ============================================================
# Workspace Resolver — Workspace Identification & Validation
#
# Maps to: The workspace identification logic used throughout
# the autopilot system. Every operation MUST identify the target
# workspace before proceeding. There is NO default workspace.
#
# Known workspaces:
#   ws-default  — Getronics (BB) — Node/TypeScript, bbvinet repos
#   ws-cit      — CIT — DevOps, K8s, Terraform, CI/CD
#   ws-corp-1   — BLOCKED (third-party, requires explicit auth)
#   ws-socnew   — BLOCKED (third-party, requires explicit auth)
#
# CRITICAL RULE: NEVER assume a default workspace. Always
# identify explicitly from context before any operation.
#
# Usage:
#   source core/workspace-resolver.sh
#   resolve_workspace "controller release for Getronics"
#   validate_workspace "ws-default"
#   get_workspace_repos "ws-default"
# ============================================================
set -euo pipefail

# --------------- Configuration ---------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config.json"

WR_OWNER="lucassfreiree"
WR_REPO="autopilot"
WR_BRANCH="autopilot-state"
WR_BASE_PATH="state/workspaces"

# Load config if available
if [ -f "$CONFIG_FILE" ]; then
  WR_OWNER=$(jq -r '.github.owner // "lucassfreiree"' "$CONFIG_FILE" 2>/dev/null || echo "lucassfreiree")
  WR_REPO=$(jq -r '.github.repo // "autopilot"' "$CONFIG_FILE" 2>/dev/null || echo "autopilot")
  WR_BRANCH=$(jq -r '.github.stateBranch // "autopilot-state"' "$CONFIG_FILE" 2>/dev/null || echo "autopilot-state")
fi

# --------------- Known Workspace Definitions ---------------

# Context keywords that map to each workspace
# Format: workspace_id|keyword1|keyword2|...
WORKSPACE_KEYWORDS=(
  "ws-default|getronics|bb|bbvinet|controller|agent|nestjs|node|typescript|psc-sre|automacao|esteira"
  "ws-cit|cit|devops|terraform|k8s|kubernetes|docker|cloud|monitoring|infra|infrastructure|itau"
  "ws-corp-1|corp-1|corp1"
  "ws-socnew|socnew|soc-new"
)

# Blocked workspaces (third-party, require explicit authorization)
BLOCKED_WORKSPACES=("ws-corp-1" "ws-socnew")

# --------------- Helper Functions ---------------

# Check if a workspace is blocked (third-party)
# Args: workspace_id
# Returns: 0 if blocked, 1 if allowed
_is_blocked_workspace() {
  local workspace_id="$1"
  for blocked in "${BLOCKED_WORKSPACES[@]}"; do
    if [ "$workspace_id" = "$blocked" ]; then
      return 0
    fi
  done
  return 1
}

# --------------- Core Resolver Functions ---------------

# resolve_workspace — Identify workspace from context clues
#
# Analyzes the input text for keywords that match known workspace
# patterns. Returns the identified workspace_id or an error if
# ambiguous or unidentifiable.
#
# CRITICAL: This function NEVER assumes a default. If the context
# is ambiguous, it returns an error asking for clarification.
#
# Args:
#   $1 - context_text (description, trigger content, user message, etc.)
#
# Returns: workspace_id on stdout, or error on stderr with return 1
resolve_workspace() {
  local context_text="${1:?ERROR: context_text is required}"
  local context_lower
  context_lower=$(echo "$context_text" | tr '[:upper:]' '[:lower:]')

  local matched_workspace=""
  local match_count=0

  for entry in "${WORKSPACE_KEYWORDS[@]}"; do
    local ws_id
    ws_id=$(echo "$entry" | cut -d'|' -f1)
    local keywords
    keywords=$(echo "$entry" | cut -d'|' -f2-)

    IFS='|' read -ra kw_array <<< "$keywords"
    for keyword in "${kw_array[@]}"; do
      if [[ "$context_lower" == *"$keyword"* ]]; then
        if [ -z "$matched_workspace" ] || [ "$matched_workspace" = "$ws_id" ]; then
          matched_workspace="$ws_id"
          match_count=$((match_count + 1))
        elif [ "$matched_workspace" != "$ws_id" ]; then
          echo "ERROR: Ambiguous context — matches both '${matched_workspace}' and '${ws_id}'. Please specify workspace explicitly." >&2
          return 1
        fi
        break  # One keyword match per workspace is enough
      fi
    done
  done

  if [ -z "$matched_workspace" ]; then
    echo "ERROR: Could not identify workspace from context. Known workspaces: ws-default (Getronics), ws-cit (CIT). Please specify explicitly." >&2
    return 1
  fi

  # Check if resolved workspace is blocked
  if _is_blocked_workspace "$matched_workspace"; then
    echo "ERROR: Workspace '${matched_workspace}' is BLOCKED (third-party). Requires explicit written authorization from account owner (lucassfreiree). DO NOT OPERATE." >&2
    return 1
  fi

  echo "$matched_workspace"
}

# validate_workspace — Check that a workspace exists on the state branch
#
# MCP Tool Call:
#   mcp__github__get_file_contents(
#     owner="lucassfreiree",
#     repo="autopilot",
#     path="state/workspaces/{ws_id}/workspace.json",
#     branch="autopilot-state"
#   )
#
# Args:
#   $1 - workspace_id
#
# Returns: 0 if valid, 1 if not found or blocked
validate_workspace() {
  local workspace_id="${1:?ERROR: workspace_id is required}"

  # Check blocked list first
  if _is_blocked_workspace "$workspace_id"; then
    echo "ERROR: Workspace '${workspace_id}' is BLOCKED (third-party). DO NOT OPERATE." >&2
    return 1
  fi

  # Validate workspace_id format (must match schema pattern: ^[a-z0-9][a-z0-9-]{1,48}[a-z0-9]$)
  if ! echo "$workspace_id" | grep -qE '^[a-z0-9][a-z0-9-]{1,48}[a-z0-9]$'; then
    echo "ERROR: Invalid workspace_id format: '${workspace_id}'. Must match ^[a-z0-9][a-z0-9-]{1,48}[a-z0-9]$" >&2
    return 1
  fi

  local ws_path="${WR_BASE_PATH}/${workspace_id}/workspace.json"

  echo "# MCP Call: mcp__github__get_file_contents" >&2
  echo "#   owner=${WR_OWNER}, repo=${WR_REPO}" >&2
  echo "#   path=${ws_path}, branch=${WR_BRANCH}" >&2

  if command -v gh &>/dev/null; then
    local response
    response=$(gh api "repos/${WR_OWNER}/${WR_REPO}/contents/${ws_path}?ref=${WR_BRANCH}" \
      --jq '.name' 2>/dev/null || echo "")

    if [ -z "$response" ]; then
      echo "ERROR: Workspace '${workspace_id}' not found on state branch (no workspace.json)" >&2
      return 1
    fi

    echo "OK: Workspace '${workspace_id}' validated" >&2
    return 0
  else
    echo "ERROR: gh CLI not available. Use MCP tool calls in Claude Code session." >&2
    return 1
  fi
}

# get_workspace_repos — Return repos configuration for a workspace
#
# MCP Tool Call:
#   mcp__github__get_file_contents(
#     owner="lucassfreiree", repo="autopilot",
#     path="state/workspaces/{ws_id}/workspace.json",
#     branch="autopilot-state"
#   )
#   Then extract .repos[] (or legacy .controller/.agent for ws-default)
#
# Args:
#   $1 - workspace_id
#
# Returns: JSON array of repos on stdout
get_workspace_repos() {
  local workspace_id="${1:?ERROR: workspace_id is required}"

  if _is_blocked_workspace "$workspace_id"; then
    echo "ERROR: Workspace '${workspace_id}' is BLOCKED. DO NOT OPERATE." >&2
    return 1
  fi

  local ws_path="${WR_BASE_PATH}/${workspace_id}/workspace.json"

  echo "# MCP Call: mcp__github__get_file_contents" >&2
  echo "#   owner=${WR_OWNER}, repo=${WR_REPO}" >&2
  echo "#   path=${ws_path}, branch=${WR_BRANCH}" >&2

  if command -v gh &>/dev/null; then
    local ws_content
    ws_content=$(gh api "repos/${WR_OWNER}/${WR_REPO}/contents/${ws_path}?ref=${WR_BRANCH}" \
      --jq '.content' 2>/dev/null | base64 -d 2>/dev/null || echo "")

    if [ -z "$ws_content" ]; then
      echo "ERROR: Could not read workspace.json for '${workspace_id}'" >&2
      return 1
    fi

    # Try modern repos[] array first, fall back to legacy controller/agent objects
    local repos
    repos=$(echo "$ws_content" | jq '.repos // []' 2>/dev/null || echo "[]")

    if [ "$repos" = "[]" ] || [ "$repos" = "null" ]; then
      # Fall back to legacy format (controller + agent as separate top-level objects)
      local controller
      controller=$(echo "$ws_content" | jq '.controller // null' 2>/dev/null || echo "null")
      local agent
      agent=$(echo "$ws_content" | jq '.agent // null' 2>/dev/null || echo "null")

      repos=$(jq -n \
        --argjson ctrl "$controller" \
        --argjson agt "$agent" \
        '[
          (if $ctrl != null then ($ctrl + {id: "controller"}) else empty end),
          (if $agt != null then ($agt + {id: "agent"}) else empty end)
        ]')
    fi

    echo "$repos"
  else
    echo "ERROR: gh CLI not available. Use MCP tool calls in Claude Code session." >&2
    return 1
  fi
}

# get_workspace_token_name — Return the token secret name for a workspace
#
# MCP Tool Call:
#   mcp__github__get_file_contents(
#     owner="lucassfreiree", repo="autopilot",
#     path="state/workspaces/{ws_id}/workspace.json",
#     branch="autopilot-state"
#   )
#   Then extract .credentials.tokenSecretName
#
# Args:
#   $1 - workspace_id
#
# Returns: Token secret name on stdout (e.g., "BBVINET_TOKEN")
get_workspace_token_name() {
  local workspace_id="${1:?ERROR: workspace_id is required}"

  if _is_blocked_workspace "$workspace_id"; then
    echo "ERROR: Workspace '${workspace_id}' is BLOCKED. DO NOT OPERATE." >&2
    return 1
  fi

  local ws_path="${WR_BASE_PATH}/${workspace_id}/workspace.json"

  echo "# MCP Call: mcp__github__get_file_contents" >&2
  echo "#   owner=${WR_OWNER}, repo=${WR_REPO}" >&2
  echo "#   path=${ws_path}, branch=${WR_BRANCH}" >&2

  if command -v gh &>/dev/null; then
    local token_name
    token_name=$(gh api "repos/${WR_OWNER}/${WR_REPO}/contents/${ws_path}?ref=${WR_BRANCH}" \
      --jq '.content' 2>/dev/null | base64 -d 2>/dev/null | \
      jq -r '.credentials.tokenSecretName // ""' 2>/dev/null || echo "")

    if [ -z "$token_name" ]; then
      echo "ERROR: No tokenSecretName found in workspace.json for '${workspace_id}'" >&2
      return 1
    fi

    echo "$token_name"
  else
    echo "ERROR: gh CLI not available. Use MCP tool calls in Claude Code session." >&2
    return 1
  fi
}

# --------------- Main (for testing) ---------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-help}" in
    resolve)
      resolve_workspace "${2:-}"
      ;;
    validate)
      validate_workspace "${2:-}"
      ;;
    repos)
      get_workspace_repos "${2:-}"
      ;;
    token)
      get_workspace_token_name "${2:-}"
      ;;
    help|*)
      echo "Usage: $0 {resolve|validate|repos|token} [args...]"
      echo ""
      echo "Commands:"
      echo "  resolve <context_text>    Identify workspace from context clues"
      echo "  validate <workspace_id>   Check workspace exists on state branch"
      echo "  repos <workspace_id>      Get repos config for workspace"
      echo "  token <workspace_id>      Get token secret name for workspace"
      echo ""
      echo "Known workspaces:"
      echo "  ws-default  — Getronics (BB) — BBVINET_TOKEN"
      echo "  ws-cit      — CIT — CIT_TOKEN"
      echo "  ws-corp-1   — BLOCKED (third-party)"
      echo "  ws-socnew   — BLOCKED (third-party)"
      ;;
  esac
fi
