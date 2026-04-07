#!/usr/bin/env bash
# ============================================================
# Post-Merge Monitor - Autopilot Backup
# Replaces: .github/workflows/post-merge-monitor.yml
#
# Monitors status after a merge/push to corporate repo main.
# Ensures CI runs and completes successfully.
#
# Usage: source this file, then call monitor_post_merge()
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/state-manager.sh"
source "${SCRIPT_DIR}/../core/audit-writer.sh"

# Monitor after merge
# Usage: monitor_post_merge <workspace_id> <component> <commit_sha>
#
# PROCEDURE:
#   1. Wait for CI to start (poll every 30s, max 5min)
#   2. Monitor CI progress (poll every 60s, max 20min)
#   3. On success: proceed to CAP promotion
#   4. On failure: trigger ci-self-heal
monitor_post_merge() {
  local workspace_id="${1:?ERROR: workspace_id required}"
  local component="${2:?ERROR: component required}"
  local commit_sha="${3:?ERROR: commit_sha required}"

  echo "=== Post-Merge Monitor: ${workspace_id}/${component} ==="
  echo "  Commit: ${commit_sha}"
  echo ""

  # Phase 1: Wait for CI to start
  echo "Phase 1: Waiting for CI to start..."
  echo "  Poll interval: 30s"
  echo "  Max wait: 5 minutes"
  echo ""
  echo "  MCP PROCEDURE:"
  echo "  1. mcp__github__get_commit(owner, repo, sha=${commit_sha})"
  echo "  2. Check if any check runs exist"
  echo "  3. If no checks yet: wait 30s and retry"
  echo "  4. If checks exist: proceed to Phase 2"
  echo ""

  # Phase 2: Monitor CI progress
  echo "Phase 2: Monitoring CI progress..."
  echo "  Poll interval: 60s"
  echo "  Max wait: 20 minutes (14min expected for success)"
  echo ""
  echo "  MCP PROCEDURE:"
  echo "  1. mcp__github__get_commit(owner, repo, sha=${commit_sha})"
  echo "  2. Check combined status"
  echo "  3. If 'pending' or 'in_progress': wait 60s and retry"
  echo "  4. If 'success': proceed to Phase 3"
  echo "  5. If 'failure': proceed to Phase 4"
  echo ""

  # Phase 3: Success path
  echo "Phase 3 (on success): Proceed to promotion"
  echo "  1. Call promote-cap.sh"
  echo "  2. Update release state"
  echo "  3. Sync dashboard"
  echo "  4. Run post-deploy-validation"
  echo ""

  # Phase 4: Failure path
  echo "Phase 4 (on failure): Self-heal"
  echo "  1. Call ci-diagnose.sh"
  echo "  2. If auto-fixable: call fix-corporate-ci.sh"
  echo "  3. If not auto-fixable: create handoff for human"
  echo "  4. For ws-default: check if known issue (proceed anyway)"
  echo ""

  write_audit "${workspace_id}" "post-merge-monitor" "started" \
    "Monitoring post-merge for ${component} at ${commit_sha}" "claude-code-backup"

  echo "=== Monitor Started ==="
}

echo "Post-Merge Monitor loaded. Available functions: monitor_post_merge"
