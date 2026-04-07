#!/usr/bin/env bash
# ============================================================
# CI Diagnose - Autopilot Backup
# Replaces: .github/workflows/ci-diagnose.yml
#
# Diagnoses CI failures in corporate repos by analyzing
# known error patterns and suggesting fixes.
#
# Usage: source this file, then call diagnose_ci()
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/state-manager.sh"
source "${SCRIPT_DIR}/../core/audit-writer.sh"

# Known CI error patterns and their fixes
declare -A KNOWN_ERRORS=(
  ["no-nested-ternary"]="Convert nested ternary to if/else blocks"
  ["object-shorthand"]="Use ES6 object shorthand syntax"
  ["no-unused-vars"]="Remove unused variable or prefix with underscore"
  ["@typescript-eslint/no-explicit-any"]="Replace 'any' with proper type"
  ["jest.mock"]="Check mock setup - may be pre-existing issue"
  ["Cannot find module"]="Check import paths and dependencies"
  ["Type error"]="Fix TypeScript type mismatch"
)

# Diagnose CI failure for a workspace/component
# Usage: diagnose_ci <workspace_id> <component>
#
# MCP TOOLS NEEDED:
#   1. mcp__github__get_file_contents - Read CI logs/workflow runs
#   2. mcp__github__list_commits - Check recent commits
#
# PROCEDURE FOR CLAUDE CODE:
#   1. Read workspace config to get repo and CI workflow name
#   2. Use MCP to list recent workflow runs:
#      mcp__github__list_commits(owner=<corp_owner>, repo=<corp_repo>)
#   3. Check workflow run status and logs
#   4. Match errors against KNOWN_ERRORS patterns
#   5. Generate fix recommendations
diagnose_ci() {
  local workspace_id="${1:?ERROR: workspace_id required}"
  local component="${2:?ERROR: component required (agent|controller)}"

  echo "=== CI Diagnosis for ${workspace_id}/${component} ==="
  echo ""

  # Step 1: Read workspace config
  echo "Step 1: Reading workspace configuration..."
  echo "  MCP CALL: mcp__github__get_file_contents"
  echo "    owner: lucassfreiree"
  echo "    repo: autopilot"
  echo "    path: state/workspaces/${workspace_id}/workspace.json"
  echo "    branch: autopilot-state"
  echo ""

  # Step 2: Get CI workflow name
  local ci_workflow
  ci_workflow=$(jq -r ".workspaces.\"${workspace_id}\".ciWorkflow // \"unknown\"" \
    "${SCRIPT_DIR}/../config.json")
  echo "  CI Workflow: ${ci_workflow}"
  echo ""

  # Step 3: Get repo info
  local repo_key
  if [ "$component" = "agent" ]; then
    repo_key="agentRepo"
  else
    repo_key="controllerRepo"
  fi
  local corp_repo
  corp_repo=$(jq -r ".workspaces.\"${workspace_id}\".${repo_key} // \"unknown\"" \
    "${SCRIPT_DIR}/../config.json")
  echo "  Corporate Repo: ${corp_repo}"
  echo ""

  # Step 4: Analyze known errors
  echo "Step 2: Checking known error patterns..."
  echo ""
  echo "  Known CI Issues for ${workspace_id}:"
  local known_issues
  known_issues=$(jq -r ".ciConfig.\"${workspace_id}\".knownIssues[]?" \
    "${SCRIPT_DIR}/../config.json")

  if [ -n "$known_issues" ]; then
    while IFS= read -r issue; do
      echo "    - ${issue}"
      for pattern in "${!KNOWN_ERRORS[@]}"; do
        if echo "$issue" | grep -qi "$pattern"; then
          echo "      FIX: ${KNOWN_ERRORS[$pattern]}"
        fi
      done
    done <<< "$known_issues"
  else
    echo "    No known issues configured"
  fi
  echo ""

  # Step 5: Generate recommendations
  echo "Step 3: Recommendations"
  echo ""
  echo "  To investigate further via Claude Code MCP tools:"
  echo ""
  echo "  1. Check latest workflow runs:"
  echo "     Use mcp__github__list_commits to see recent pushes"
  echo ""
  echo "  2. Read specific error files:"
  echo "     Use mcp__github__get_file_contents to read problematic files"
  echo ""
  echo "  3. Apply auto-fixes:"
  echo "     Run: source operations/fix-corporate-ci.sh"
  echo "     Then: fix_corporate_ci ${workspace_id} ${component}"
  echo ""

  # Write audit entry
  write_audit "${workspace_id}" "ci-diagnose" "completed" \
    "Diagnosed CI for ${component}" "claude-code-backup"

  echo "=== Diagnosis Complete ==="
}

# Quick CI status summary
# Usage: ci_summary <workspace_id>
ci_summary() {
  local workspace_id="${1:?ERROR: workspace_id required}"

  echo "=== CI Summary for ${workspace_id} ==="
  echo ""
  echo "MCP PROCEDURE:"
  echo "  1. Read workspace config for repo details"
  echo "  2. List recent commits on corporate repo main branch"
  echo "  3. Check commit statuses for CI results"
  echo ""
  echo "Expected CI Duration:"
  echo "  Success: ~14 minutes"
  echo "  Failure: ~4 minutes"
  echo ""
  echo "CI Workflow: $(jq -r ".ciConfig.\"${workspace_id}\".workflowName // \"N/A\"" \
    "${SCRIPT_DIR}/../config.json")"
}

echo "CI Diagnose loaded. Available functions: diagnose_ci, ci_summary"
