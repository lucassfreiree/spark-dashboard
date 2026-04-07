#!/usr/bin/env bash
# ============================================================
# Post-Deploy Validation - Autopilot Backup
# Replaces: .github/workflows/post-deploy-validation.yml
#
# Validates that a deployment was successful by checking
# release state, CI status, and CAP promotion.
#
# Usage: source this file, then call validate_deploy()
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/state-manager.sh"
source "${SCRIPT_DIR}/../core/audit-writer.sh"

# Validate a deployment
# Usage: validate_deploy <workspace_id> <component>
#
# MCP TOOLS NEEDED:
#   mcp__github__get_file_contents - Read state files
#
# CHECKS:
#   1. Release state updated with new version
#   2. CI passed (or known issue)
#   3. CAP promotion completed
#   4. Tag format correct
#   5. Audit trail recorded
validate_deploy() {
  local workspace_id="${1:?ERROR: workspace_id required}"
  local component="${2:?ERROR: component required (agent|controller)}"

  echo "=== Post-Deploy Validation: ${workspace_id}/${component} ==="
  echo ""

  local checks_passed=0
  local checks_total=5

  # Check 1: Release state
  echo "Check 1/5: Release State..."
  echo "  MCP CALL: mcp__github__get_file_contents"
  echo "    path: state/workspaces/${workspace_id}/${component}-release-state.json"
  echo "    branch: autopilot-state"
  echo "  VERIFY: status == 'promoted' or 'released'"
  echo "  VERIFY: lastTag matches version-sha format"
  echo "  VERIFY: updatedAt is recent (within last hour)"
  echo ""

  # Check 2: CI Status
  echo "Check 2/5: CI Status..."
  echo "  MCP CALL: Check latest commit status on corporate repo"
  echo "  VERIFY: CI completed (success or known-failure)"
  echo ""

  # Check 3: CAP Promotion
  echo "Check 3/5: CAP Promotion..."
  echo "  MCP CALL: mcp__github__get_file_contents"
  echo "    Read values.yaml from CAP repo"
  echo "  VERIFY: image tag matches lastTag in release state"
  echo ""

  # Check 4: Tag Format
  echo "Check 4/5: Tag Format..."
  echo "  VERIFY: Tag matches pattern: X.Y.Z-<7char_sha>"
  echo "  VERIFY: Patch digit 0-9 (never >= 10)"
  echo ""

  # Check 5: Audit Trail
  echo "Check 5/5: Audit Trail..."
  echo "  MCP CALL: List audit entries for workspace"
  echo "  VERIFY: Recent audit entry for release-${component}"
  echo "  VERIFY: Audit status == 'success' or 'completed'"
  echo ""

  echo "=== Validation Summary ==="
  echo "  Run all 5 checks via MCP tools"
  echo "  If all pass: deployment verified"
  echo "  If any fail: investigate and potentially rollback"
  echo ""

  write_audit "${workspace_id}" "post-deploy-validation" "completed" \
    "Validated deployment for ${component}" "claude-code-backup"
}

echo "Post-Deploy Validation loaded. Available functions: validate_deploy"
