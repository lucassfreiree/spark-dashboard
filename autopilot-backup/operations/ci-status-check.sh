#!/usr/bin/env bash
# ============================================================
# CI Status Check - Autopilot Backup
# Replaces: .github/workflows/ci-status-check.yml
#
# Checks the status of corporate CI pipelines.
#
# Usage: source this file, then call check_ci_status()
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/state-manager.sh"
source "${SCRIPT_DIR}/../core/audit-writer.sh"

# Check CI status for a workspace/component
# Usage: check_ci_status <workspace_id> <component>
#
# MCP TOOLS NEEDED:
#   1. mcp__github__list_commits - Get latest commit on main
#   2. mcp__github__get_commit - Check commit statuses/checks
check_ci_status() {
  local workspace_id="${1:?ERROR: workspace_id required}"
  local component="${2:?ERROR: component required (agent|controller)}"

  local config_file="${SCRIPT_DIR}/../config.json"
  local repo_key
  if [ "$component" = "agent" ]; then
    repo_key="agentRepo"
  else
    repo_key="controllerRepo"
  fi
  local corp_repo
  corp_repo=$(jq -r ".workspaces.\"${workspace_id}\".${repo_key}" "$config_file")
  local ci_workflow
  ci_workflow=$(jq -r ".ciConfig.\"${workspace_id}\".workflowName // \"unknown\"" "$config_file")
  local corp_owner="${corp_repo%%/*}"
  local corp_name="${corp_repo##*/}"

  echo "=== CI Status Check: ${workspace_id}/${component} ==="
  echo "  Repo: ${corp_repo}"
  echo "  CI Workflow: ${ci_workflow}"
  echo ""

  # Step 1: Get latest commit
  echo "Step 1: Get latest commit on main..."
  echo "  MCP CALL: mcp__github__list_commits"
  echo "    owner: ${corp_owner}"
  echo "    repo: ${corp_name}"
  echo "    sha: main"
  echo "    per_page: 1"
  echo ""
  echo "  Extract: SHA, message, author, date"
  echo ""

  # Step 2: Check commit status
  echo "Step 2: Check CI status for commit..."
  echo "  MCP CALL: mcp__github__get_commit"
  echo "    owner: ${corp_owner}"
  echo "    repo: ${corp_name}"
  echo "    sha: <latest_commit_sha>"
  echo ""
  echo "  Check combined status:"
  echo "    success - CI passed"
  echo "    failure - CI failed"
  echo "    pending - CI running or queued"
  echo ""

  # Step 3: Expected timing
  echo "Step 3: Expected CI timing..."
  echo "  Success: ~$(jq -r ".ciConfig.\"${workspace_id}\".expectedDuration // \"14min\"" "$config_file")"
  echo "  Failure: ~$(jq -r ".ciConfig.\"${workspace_id}\".failureDuration // \"4min\"" "$config_file")"
  echo ""

  # Step 4: Return status
  echo "Possible return values:"
  echo "  SUCCESS  - CI completed successfully"
  echo "  FAILURE  - CI failed (check diagnose for details)"
  echo "  PENDING  - CI queued, not started yet"
  echo "  RUNNING  - CI currently executing"
  echo "  UNKNOWN  - Could not determine status"
  echo ""

  write_audit "${workspace_id}" "ci-status-check" "completed" \
    "CI status checked for ${component}" "claude-code-backup"
}

# Wait for CI to complete
# Usage: wait_for_ci <workspace_id> <component> [timeout_minutes]
wait_for_ci() {
  local workspace_id="${1:?ERROR: workspace_id required}"
  local component="${2:?ERROR: component required}"
  local timeout="${3:-20}"

  echo "=== Waiting for CI: ${workspace_id}/${component} ==="
  echo "  Timeout: ${timeout} minutes"
  echo ""
  echo "  PROCEDURE: Poll check_ci_status every 60 seconds"
  echo "  Stop when: status == SUCCESS or FAILURE"
  echo "  Or when: timeout reached"
  echo ""
  echo "  For ws-default known behavior:"
  echo "    CI may fail due to pre-existing issues"
  echo "    Policy: proceed with deploy if known failures"
  echo ""
}

echo "CI Status Check loaded. Functions: check_ci_status, wait_for_ci"
