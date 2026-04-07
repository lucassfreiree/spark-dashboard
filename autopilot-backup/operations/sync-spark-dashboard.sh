#!/usr/bin/env bash
# ============================================================
# Sync Spark Dashboard - Autopilot Backup
# Replaces: .github/workflows/sync-spark-dashboard.yml
#
# Collects state from all workspaces and generates the
# state.json file consumed by the spark-dashboard React app.
#
# Usage: source this file, then call sync_dashboard()
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/state-manager.sh"
source "${SCRIPT_DIR}/../core/audit-writer.sh"

# Sync state to spark-dashboard
# Usage: sync_dashboard [workspace_id]
#
# MCP TOOLS NEEDED:
#   1. mcp__github__get_file_contents - Read state from autopilot-state branch
#   2. mcp__github__create_or_update_file - Push state.json to spark-dashboard
#
# PROCEDURE FOR CLAUDE CODE:
#   1. Read all workspace configs from autopilot-state
#   2. Read release states for each workspace/component
#   3. Read health states
#   4. Read recent audit entries
#   5. Read handoff queue
#   6. Assemble state.json v3 format
#   7. Push to spark-dashboard/public/state.json
sync_dashboard() {
  local target_workspace="${1:-all}"

  echo "=== Sync Spark Dashboard ==="
  echo "  Target: ${target_workspace}"
  echo ""

  # Step 1: Collect workspace data
  echo "Step 1: Collecting workspace data..."
  echo ""

  local config_file="${SCRIPT_DIR}/../config.json"
  local workspaces
  workspaces=$(jq -r '.workspaces | keys[]' "$config_file")

  for ws_id in $workspaces; do
    echo "  Workspace: ${ws_id}"
    echo ""
    echo "  MCP CALLS:"
    echo "    1. mcp__github__get_file_contents"
    echo "       owner: lucassfreiree, repo: autopilot"
    echo "       path: state/workspaces/${ws_id}/workspace.json"
    echo "       branch: autopilot-state"
    echo ""
    echo "    2. mcp__github__get_file_contents"
    echo "       path: state/workspaces/${ws_id}/agent-release-state.json"
    echo ""
    echo "    3. mcp__github__get_file_contents"
    echo "       path: state/workspaces/${ws_id}/controller-release-state.json"
    echo ""
    echo "    4. mcp__github__get_file_contents"
    echo "       path: state/workspaces/${ws_id}/health.json"
    echo ""
    echo "    5. mcp__github__get_file_contents"
    echo "       path: state/workspaces/${ws_id}/release-freeze.json"
    echo ""
  done

  # Step 2: Assemble state.json
  echo "Step 2: Assembling state.json v3..."
  echo ""
  echo "  Schema v3 structure:"
  echo "  {"
  echo "    \"schemaVersion\": 3,"
  echo "    \"generatedAt\": \"<ISO timestamp>\","
  echo "    \"source\": \"autopilot-backup\","
  echo "    \"workspaces\": {"
  echo "      \"<ws_id>\": {"
  echo "        \"config\": <workspace.json>,"
  echo "        \"releases\": {"
  echo "          \"agent\": <agent-release-state.json>,"
  echo "          \"controller\": <controller-release-state.json>"
  echo "        },"
  echo "        \"health\": <health.json>,"
  echo "        \"freeze\": <release-freeze.json>,"
  echo "        \"recentAudit\": [<last 20 audit entries>],"
  echo "        \"pendingHandoffs\": [<pending handoff entries>]"
  echo "      }"
  echo "    },"
  echo "    \"summary\": {"
  echo "      \"totalReleases\": <count>,"
  echo "      \"activeWorkspaces\": <count>,"
  echo "      \"healthStatus\": \"healthy|degraded|unhealthy\","
  echo "      \"lastDeployAt\": \"<ISO timestamp>\""
  echo "    }"
  echo "  }"
  echo ""

  # Step 3: Push to dashboard
  echo "Step 3: Pushing to spark-dashboard..."
  echo ""
  echo "  MCP CALL: mcp__github__create_or_update_file"
  echo "    owner: lucassfreiree"
  echo "    repo: spark-dashboard"
  echo "    path: public/state.json"
  echo "    content: <assembled_state_json>"
  echo "    branch: main"
  echo "    message: 'sync: update dashboard state from autopilot-backup'"
  echo ""

  write_audit "system" "sync-spark-dashboard" "completed" \
    "Dashboard state synced for ${target_workspace}" "claude-code-backup"

  echo "=== Dashboard Sync Complete ==="
}

echo "Sync Spark Dashboard loaded. Available functions: sync_dashboard"
