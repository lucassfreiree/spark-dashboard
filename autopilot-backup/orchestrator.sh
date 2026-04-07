#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# orchestrator.sh — Master Entry Point for Autopilot Backup System
#
# Single entry point for all common operations. Routes commands to the
# appropriate scripts, enforces Rule #0 (stealth), and manages session locks.
#
# Usage:
#   ./orchestrator.sh release agent [ws-default]     — Full release pipeline
#   ./orchestrator.sh release controller [ws-default] — Full release pipeline
#   ./orchestrator.sh status [ws-default]             — Show current state
#   ./orchestrator.sh ci-check <component> [ws-default] — Check CI status
#   ./orchestrator.sh health                          — System health check
#   ./orchestrator.sh validate-token                  — Test token access
#   ./orchestrator.sh version-bump <current> [patch]  — Calculate next version
#   ./orchestrator.sh safe-msg validate "message"     — Check commit message
#   ./orchestrator.sh safe-msg bump <comp> <old> <new> — Generate bump msg
#
# Environment:
#   BBVINET_TOKEN or ~/.autopilot-token — Required for corporate repo access
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CORE_DIR="${SCRIPT_DIR}/core"
OPS_DIR="${SCRIPT_DIR}/operations"
AUTH_DIR="${SCRIPT_DIR}/auth"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ---------------------------------------------------------------------------
# Token resolution
# ---------------------------------------------------------------------------
resolve_token() {
  if [[ -n "${BBVINET_TOKEN:-}" ]]; then
    echo "$BBVINET_TOKEN"
  elif [[ -f "$HOME/.autopilot-token" ]]; then
    cat "$HOME/.autopilot-token"
  elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
    echo "$GITHUB_TOKEN"
  else
    echo ""
  fi
}

require_token() {
  local token
  token=$(resolve_token)
  if [[ -z "$token" ]]; then
    echo -e "${RED}ERROR: No token available.${NC}" >&2
    echo "Provide via: export BBVINET_TOKEN=\"ghp_...\"" >&2
    echo "Or run: bash ${AUTH_DIR}/github-auth.sh setup-pat" >&2
    exit 1
  fi
  export BBVINET_TOKEN="$token"
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

cmd_release() {
  local component="${1:?Usage: $0 release <agent|controller> [workspace]}"
  local workspace="${2:-ws-default}"

  require_token

  echo -e "${BLUE}=== Release Pipeline: ${component} (${workspace}) ===${NC}"
  echo ""

  case "$component" in
    agent)
      if [[ -x "${OPS_DIR}/release-agent.sh" ]]; then
        "${OPS_DIR}/release-agent.sh" --workspace "$workspace"
      else
        echo -e "${RED}ERROR: release-agent.sh not found${NC}" >&2
        exit 1
      fi
      ;;
    controller)
      if [[ -x "${OPS_DIR}/release-controller.sh" ]]; then
        "${OPS_DIR}/release-controller.sh" --workspace "$workspace"
      else
        echo -e "${RED}ERROR: release-controller.sh not found${NC}" >&2
        exit 1
      fi
      ;;
    *)
      echo -e "${RED}ERROR: Unknown component '${component}'. Use: agent, controller${NC}" >&2
      exit 1
      ;;
  esac
}

cmd_status() {
  local workspace="${1:-ws-default}"

  echo -e "${BLUE}=== Status: ${workspace} ===${NC}"
  echo ""

  # Read config.json for workspace info
  local config_file="${SCRIPT_DIR}/config.json"
  if [[ -f "$config_file" ]]; then
    local ws_display
    ws_display=$(jq -r ".workspaces.\"${workspace}\".displayName // \"unknown\"" "$config_file")
    echo -e "Workspace: ${GREEN}${workspace}${NC} (${ws_display})"
  fi

  echo ""
  echo "Note: Full status requires MCP access to autopilot-state branch."
  echo "Use the following MCP calls to read current state:"
  echo ""
  echo "  Agent release state:"
  echo "    mcp__github__get_file_contents("
  echo "      owner: \"lucassfreiree\", repo: \"autopilot\","
  echo "      path: \"state/workspaces/${workspace}/agent-release-state.json\","
  echo "      ref: \"refs/heads/autopilot-state\")"
  echo ""
  echo "  Controller release state:"
  echo "    mcp__github__get_file_contents("
  echo "      owner: \"lucassfreiree\", repo: \"autopilot\","
  echo "      path: \"state/workspaces/${workspace}/controller-release-state.json\","
  echo "      ref: \"refs/heads/autopilot-state\")"
  echo ""
  echo "  Session lock:"
  echo "    mcp__github__get_file_contents("
  echo "      owner: \"lucassfreiree\", repo: \"autopilot\","
  echo "      path: \"state/workspaces/${workspace}/locks/session-lock.json\","
  echo "      ref: \"refs/heads/autopilot-state\")"

  # If token available, show corporate repo versions
  local token
  token=$(resolve_token)
  if [[ -n "$token" ]]; then
    echo ""
    echo -e "${BLUE}--- Corporate Repo Versions ---${NC}"

    local config_file="${SCRIPT_DIR}/config.json"
    local agent_repo controller_repo
    agent_repo=$(jq -r ".workspaces.\"${workspace}\".agentRepo // \"\"" "$config_file" 2>/dev/null || echo "")
    controller_repo=$(jq -r ".workspaces.\"${workspace}\".controllerRepo // \"\"" "$config_file" 2>/dev/null || echo "")

    if [[ -n "$agent_repo" ]]; then
      local agent_ver
      agent_ver=$(curl -s -H "Authorization: token $token" \
        "https://api.github.com/repos/${agent_repo}/contents/package.json" 2>/dev/null | \
        jq -r '.content' 2>/dev/null | base64 -d 2>/dev/null | jq -r '.version' 2>/dev/null || echo "?")
      echo -e "  Agent (${agent_repo}): ${GREEN}${agent_ver}${NC}"
    fi

    if [[ -n "$controller_repo" ]]; then
      local ctrl_ver
      ctrl_ver=$(curl -s -H "Authorization: token $token" \
        "https://api.github.com/repos/${controller_repo}/contents/package.json" 2>/dev/null | \
        jq -r '.content' 2>/dev/null | base64 -d 2>/dev/null | jq -r '.version' 2>/dev/null || echo "?")
      echo -e "  Controller (${controller_repo}): ${GREEN}${ctrl_ver}${NC}"
    fi
  fi
}

cmd_ci_check() {
  local component="${1:?Usage: $0 ci-check <agent|controller> [workspace]}"
  local workspace="${2:-ws-default}"

  require_token

  local config_file="${SCRIPT_DIR}/config.json"
  local repo
  case "$component" in
    agent)
      repo=$(jq -r ".workspaces.\"${workspace}\".agentRepo // \"\"" "$config_file")
      ;;
    controller)
      repo=$(jq -r ".workspaces.\"${workspace}\".controllerRepo // \"\"" "$config_file")
      ;;
    *)
      echo -e "${RED}ERROR: Unknown component '${component}'${NC}" >&2
      exit 1
      ;;
  esac

  if [[ -z "$repo" ]]; then
    echo -e "${RED}ERROR: No repo configured for ${component} in ${workspace}${NC}" >&2
    exit 1
  fi

  echo -e "${BLUE}=== CI Status: ${component} (${repo}) ===${NC}"

  # Get latest commit
  local sha
  sha=$(curl -s -H "Authorization: token $BBVINET_TOKEN" \
    "https://api.github.com/repos/${repo}/commits?per_page=1" | \
    jq -r '.[0].sha // ""' 2>/dev/null || echo "")

  if [[ -z "$sha" ]]; then
    echo -e "${RED}ERROR: Could not get latest commit${NC}" >&2
    exit 1
  fi

  echo "Latest commit: ${sha:0:7}"
  echo ""

  # Get check runs
  local checks
  checks=$(curl -s -H "Authorization: token $BBVINET_TOKEN" \
    "https://api.github.com/repos/${repo}/commits/${sha}/check-runs")

  local total completed success failed
  total=$(echo "$checks" | jq '.total_count // 0')
  completed=$(echo "$checks" | jq '[.check_runs[] | select(.status=="completed")] | length')
  success=$(echo "$checks" | jq '[.check_runs[] | select(.conclusion=="success")] | length')
  failed=$(echo "$checks" | jq '[.check_runs[] | select(.conclusion=="failure")] | length')

  echo "Total: ${total}, Completed: ${completed}, Success: ${success}, Failed: ${failed}"
  echo ""

  # Detail each check
  echo "$checks" | jq -r '.check_runs[] | "  \(.status | if . == "completed" then (if .conclusion == "success" then "✓" else "✗" end) else "⏳" end) \(.name) — \(.status) \(.conclusion // "")"' 2>/dev/null || true
}

cmd_health() {
  echo -e "${BLUE}=== System Health Check ===${NC}"
  echo ""

  # Check config.json
  local config_file="${SCRIPT_DIR}/config.json"
  if [[ -f "$config_file" ]] && jq . "$config_file" >/dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} config.json valid"
  else
    echo -e "  ${RED}✗${NC} config.json invalid or missing"
  fi

  # Check core scripts
  local core_scripts=(state-manager session-guard audit-writer version-bump workspace-resolver trigger-engine schema-validator safe-commit)
  for script in "${core_scripts[@]}"; do
    if [[ -f "${CORE_DIR}/${script}.sh" ]]; then
      echo -e "  ${GREEN}✓${NC} core/${script}.sh exists"
    else
      echo -e "  ${RED}✗${NC} core/${script}.sh missing"
    fi
  done

  # Check token
  local token
  token=$(resolve_token)
  if [[ -n "$token" ]]; then
    local user
    user=$(curl -s -H "Authorization: token $token" "https://api.github.com/user" 2>/dev/null | \
      jq -r '.login // "INVALID"' 2>/dev/null || echo "INVALID")
    if [[ "$user" != "INVALID" && "$user" != "null" ]]; then
      echo -e "  ${GREEN}✓${NC} Token valid (user: ${user})"
    else
      echo -e "  ${RED}✗${NC} Token invalid or expired"
    fi
  else
    echo -e "  ${YELLOW}⚠${NC} No token configured"
  fi

  # Check schemas
  local schema_dir="${SCRIPT_DIR}/schemas"
  local schema_count=0
  if [[ -d "$schema_dir" ]]; then
    schema_count=$(ls "$schema_dir"/*.json 2>/dev/null | wc -l || echo 0)
  fi
  echo -e "  ${GREEN}✓${NC} Schemas: ${schema_count} files"

  # Check operations
  local ops_count=0
  if [[ -d "$OPS_DIR" ]]; then
    ops_count=$(ls "$OPS_DIR"/*.sh 2>/dev/null | wc -l || echo 0)
  fi
  echo -e "  ${GREEN}✓${NC} Operations: ${ops_count} scripts"

  echo ""
  echo -e "${GREEN}Health check complete.${NC}"
}

cmd_validate_token() {
  local token
  token=$(resolve_token)
  if [[ -z "$token" ]]; then
    echo -e "${RED}No token found.${NC}"
    echo "Set via: export BBVINET_TOKEN=\"ghp_...\" or ~/.autopilot-token"
    exit 1
  fi

  bash "${AUTH_DIR}/github-auth.sh" status
  echo ""
  bash "${AUTH_DIR}/github-auth.sh" test
}

cmd_version_bump() {
  local current="${1:?Usage: $0 version-bump <current_version> [patch|minor|major]}"
  local bump_type="${2:-patch}"

  if [[ -x "${CORE_DIR}/version-bump.sh" ]]; then
    "${CORE_DIR}/version-bump.sh" "$bump_type" "$current"
  else
    echo -e "${RED}ERROR: version-bump.sh not found${NC}" >&2
    exit 1
  fi
}

cmd_safe_msg() {
  if [[ -x "${CORE_DIR}/safe-commit.sh" ]]; then
    "${CORE_DIR}/safe-commit.sh" "$@"
  else
    source "${CORE_DIR}/safe-commit.sh"
    case "${1:-}" in
      validate) validate_commit_msg "${2:-}" ;;
      bump) generate_bump_msg "${2:-}" "${3:-}" "${4:-}" ;;
      fix) generate_fix_msg "${2:-}" "${3:-}" ;;
      *) echo "Usage: $0 safe-msg <validate|bump|fix> ..." ;;
    esac
  fi
}

# ---------------------------------------------------------------------------
# Main router
# ---------------------------------------------------------------------------
show_help() {
  echo "orchestrator.sh — Autopilot Backup System"
  echo ""
  echo "Usage:"
  echo "  $0 release <agent|controller> [workspace]  — Full release pipeline"
  echo "  $0 status [workspace]                       — Show current state"
  echo "  $0 ci-check <agent|controller> [workspace]  — Check CI status"
  echo "  $0 health                                   — System health check"
  echo "  $0 validate-token                           — Test token access"
  echo "  $0 version-bump <version> [patch|minor|major] — Calc next version"
  echo "  $0 safe-msg validate \"message\"              — Check commit message"
  echo "  $0 safe-msg bump <comp> <old> <new>         — Generate bump msg"
  echo ""
  echo "Environment:"
  echo "  BBVINET_TOKEN — PAT for corporate repo access"
  echo "  ~/.autopilot-token — Alternative token file"
}

CMD="${1:-help}"
shift || true

case "$CMD" in
  release)        cmd_release "$@" ;;
  status)         cmd_status "$@" ;;
  ci-check)       cmd_ci_check "$@" ;;
  health)         cmd_health ;;
  validate-token) cmd_validate_token ;;
  version-bump)   cmd_version_bump "$@" ;;
  safe-msg)       cmd_safe_msg "$@" ;;
  help|--help|-h) show_help ;;
  *)
    echo -e "${RED}Unknown command: ${CMD}${NC}" >&2
    echo ""
    show_help
    exit 1
    ;;
esac
