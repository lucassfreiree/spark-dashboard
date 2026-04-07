#!/usr/bin/env bash
# ============================================================
# Collect State - Autopilot Backup
# Replaces: scripts/dashboard/collect-state.sh
#
# Collects all state data from the autopilot-state branch
# and formats it for dashboard consumption.
#
# Usage: source this file, then call collect_state()
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/state-manager.sh"

# Collect complete state for a workspace
# Usage: collect_state <workspace_id>
collect_state() {
  local workspace_id="${1:?ERROR: workspace_id required}"

  echo "=== Collecting State for ${workspace_id} ==="
  echo ""

  echo "Files to read from autopilot-state branch:"
  echo ""

  local state_files=(
    "workspace.json"
    "agent-release-state.json"
    "controller-release-state.json"
    "health.json"
    "release-freeze.json"
  )

  for file in "${state_files[@]}"; do
    echo "  mcp__github__get_file_contents:"
    echo "    owner: lucassfreiree"
    echo "    repo: autopilot"
    echo "    path: state/workspaces/${workspace_id}/${file}"
    echo "    branch: autopilot-state"
    echo ""
  done

  echo "Directories to list:"
  echo ""

  local state_dirs=(
    "locks"
    "audit"
    "handoffs"
    "improvements"
    "metrics"
    "approvals"
  )

  for dir in "${state_dirs[@]}"; do
    echo "  mcp__github__get_file_contents:"
    echo "    path: state/workspaces/${workspace_id}/${dir}/"
    echo ""
  done

  echo "=== Collection Complete ==="
}

# Collect state for ALL workspaces
# Usage: collect_all_state
collect_all_state() {
  local config_file="${SCRIPT_DIR}/../config.json"
  local workspaces
  workspaces=$(jq -r '.workspaces | keys[]' "$config_file")

  echo "=== Collecting State for All Workspaces ==="
  echo ""

  for ws_id in $workspaces; do
    collect_state "$ws_id"
    echo ""
  done
}

echo "Collect State loaded. Functions: collect_state, collect_all_state"
