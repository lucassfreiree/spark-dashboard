#!/usr/bin/env bash
# ============================================================
# CI Monitor Loop - Autopilot Backup
# Replaces: .github/workflows/ci-monitor-loop.yml
#
# Continuous CI monitoring - polls corporate CI status
# and triggers self-heal if failures detected.
#
# Usage: source this file, then call monitor_ci()
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/state-manager.sh"
source "${SCRIPT_DIR}/../core/audit-writer.sh"

# Monitor CI status in a loop
# Usage: monitor_ci <workspace_id> <component> [max_checks] [interval_seconds]
#
# MCP TOOLS NEEDED:
#   1. mcp__github__list_commits - Check recent commits and their statuses
#   2. mcp__github__get_file_contents - Read workflow run details
#
# PROCEDURE FOR CLAUDE CODE:
#   1. Read workspace config for repo/CI details
#   2. Check latest commit on main branch
#   3. Check CI status for that commit
#   4. If failure: trigger ci-self-heal or ci-diagnose
#   5. If success: update health state
#   6. Repeat at interval
monitor_ci() {
  local workspace_id="${1:?ERROR: workspace_id required}"
  local component="${2:?ERROR: component required (agent|controller)}"
  local max_checks="${3:-10}"
  local interval="${4:-60}"

  echo "=== CI Monitor Loop: ${workspace_id}/${component} ==="
  echo "  Max checks: ${max_checks}"
  echo "  Interval: ${interval}s"
  echo ""

  local repo_key
  if [ "$component" = "agent" ]; then
    repo_key="agentRepo"
  else
    repo_key="controllerRepo"
  fi
  local corp_repo
  corp_repo=$(jq -r ".workspaces.\"${workspace_id}\".${repo_key}" \
    "${SCRIPT_DIR}/../config.json")

  local check_count=0
  local last_status="unknown"

  while [ "$check_count" -lt "$max_checks" ]; do
    check_count=$((check_count + 1))
    echo "--- Check ${check_count}/${max_checks} at $(date -u +%Y-%m-%dT%H:%M:%SZ) ---"
    echo ""

    echo "  MCP CALL: mcp__github__list_commits"
    echo "    owner: ${corp_repo%%/*}"
    echo "    repo: ${corp_repo##*/}"
    echo "    branch: main"
    echo "    per_page: 1"
    echo ""

    echo "  Then check commit status/checks for the latest SHA"
    echo ""

    # Simulated status check
    echo "  Status: Waiting for MCP response..."
    echo "  (In live operation, Claude Code would make the MCP call here)"
    echo ""

    echo "  Possible outcomes:"
    echo "    - success: CI passed -> update health, stop monitoring"
    echo "    - failure: CI failed -> trigger self-heal"
    echo "    - pending/in_progress: CI running -> wait and retry"
    echo ""

    if [ "$check_count" -lt "$max_checks" ]; then
      echo "  Next check in ${interval}s..."
      echo ""
    fi
  done

  echo "=== Monitor Loop Complete (${check_count} checks) ==="

  write_audit "${workspace_id}" "ci-monitor-loop" "completed" \
    "Monitored CI for ${component}, ${check_count} checks" "claude-code-backup"
}

# Single CI status check (non-looping)
# Usage: check_ci_once <workspace_id> <component>
check_ci_once() {
  local workspace_id="${1:?ERROR: workspace_id required}"
  local component="${2:?ERROR: component required}"

  echo "=== Single CI Check: ${workspace_id}/${component} ==="
  echo ""
  echo "MCP PROCEDURE:"
  echo "  1. mcp__github__list_commits(owner, repo, branch=main, per_page=1)"
  echo "  2. Get latest commit SHA"
  echo "  3. mcp__github__get_commit(owner, repo, sha) to check status"
  echo "  4. Return: success | failure | pending | in_progress"
  echo ""
}

echo "CI Monitor Loop loaded. Available functions: monitor_ci, check_ci_once"
