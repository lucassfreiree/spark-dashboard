#!/usr/bin/env bash
# ============================================================
# Agent Handoff - Autopilot Backup
# Replaces: .github/workflows/enqueue-agent-handoff.yml
#
# Manages task handoffs between AI agents. When one agent
# cannot complete a task, it creates a handoff for another.
#
# Usage: source this file, then call handoff functions
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/state-manager.sh"
source "${SCRIPT_DIR}/../core/audit-writer.sh"

# Create a handoff from one agent to another
# Usage: create_handoff <workspace_id> <from_agent> <to_agent> <component> <summary> <priority>
#
# MCP TOOLS NEEDED:
#   mcp__github__create_or_update_file - Write handoff to state branch
#
# Handoff stored at: state/workspaces/{ws_id}/handoffs/handoff-{timestamp}.json
# Handoff schema: schemas/handoff.schema.json
create_handoff() {
  local workspace_id="${1:?ERROR: workspace_id required}"
  local from_agent="${2:?ERROR: from_agent required}"
  local to_agent="${3:?ERROR: to_agent required}"
  local component="${4:?ERROR: component required}"
  local summary="${5:?ERROR: summary required}"
  local priority="${6:-medium}"

  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local handoff_id
  handoff_id="handoff-$(date -u +%Y%m%d%H%M%S)"

  local handoff_json
  handoff_json=$(cat <<EOF
{
  "schemaVersion": 1,
  "handoffId": "${handoff_id}",
  "workspaceId": "${workspace_id}",
  "fromAgent": "${from_agent}",
  "toAgent": "${to_agent}",
  "component": "${component}",
  "summary": "${summary}",
  "priority": "${priority}",
  "status": "pending",
  "createdAt": "${timestamp}",
  "context": {
    "reason": "Agent cannot complete task - handoff to specialist",
    "attemptedActions": [],
    "blockers": []
  }
}
EOF
)

  echo "=== Creating Handoff ==="
  echo "  ID: ${handoff_id}"
  echo "  From: ${from_agent} -> To: ${to_agent}"
  echo "  Component: ${component}"
  echo "  Summary: ${summary}"
  echo "  Priority: ${priority}"
  echo ""
  echo "  MCP CALL: mcp__github__create_or_update_file"
  echo "    owner: lucassfreiree"
  echo "    repo: autopilot"
  echo "    path: state/workspaces/${workspace_id}/handoffs/${handoff_id}.json"
  echo "    content: <handoff_json>"
  echo "    branch: autopilot-state"
  echo "    message: 'handoff: ${from_agent} -> ${to_agent} [${component}]'"
  echo ""

  write_audit "${workspace_id}" "agent-handoff" "created" \
    "Handoff ${handoff_id}: ${from_agent} -> ${to_agent} for ${component}" "${from_agent}"

  echo "Handoff ${handoff_id} created successfully."
}

# List pending handoffs for an agent
# Usage: list_handoffs <workspace_id> [agent_name]
list_handoffs() {
  local workspace_id="${1:?ERROR: workspace_id required}"
  local agent_name="${2:-}"

  echo "=== Pending Handoffs for ${workspace_id} ==="
  echo ""
  echo "  MCP CALL: mcp__github__get_file_contents"
  echo "    owner: lucassfreiree"
  echo "    repo: autopilot"
  echo "    path: state/workspaces/${workspace_id}/handoffs/"
  echo "    branch: autopilot-state"
  echo ""
  if [ -n "$agent_name" ]; then
    echo "  Filter: toAgent == '${agent_name}' AND status == 'pending'"
  else
    echo "  Filter: status == 'pending'"
  fi
  echo ""
}

# Accept a handoff (mark as in_progress)
# Usage: accept_handoff <workspace_id> <handoff_id> <agent_name>
accept_handoff() {
  local workspace_id="${1:?ERROR: workspace_id required}"
  local handoff_id="${2:?ERROR: handoff_id required}"
  local agent_name="${3:?ERROR: agent_name required}"

  echo "=== Accepting Handoff: ${handoff_id} ==="
  echo ""
  echo "  MCP PROCEDURE:"
  echo "  1. Read handoff file from state branch"
  echo "  2. Verify toAgent matches ${agent_name}"
  echo "  3. Update status: pending -> in_progress"
  echo "  4. Add acceptedAt timestamp"
  echo "  5. Write back via MCP"
  echo ""

  write_audit "${workspace_id}" "agent-handoff" "accepted" \
    "Handoff ${handoff_id} accepted by ${agent_name}" "${agent_name}"
}

# Complete a handoff
# Usage: complete_handoff <workspace_id> <handoff_id> <agent_name> <result>
complete_handoff() {
  local workspace_id="${1:?ERROR: workspace_id required}"
  local handoff_id="${2:?ERROR: handoff_id required}"
  local agent_name="${3:?ERROR: agent_name required}"
  local result="${4:-completed successfully}"

  echo "=== Completing Handoff: ${handoff_id} ==="
  echo ""
  echo "  MCP PROCEDURE:"
  echo "  1. Read handoff file from state branch"
  echo "  2. Update status: in_progress -> completed"
  echo "  3. Add completedAt timestamp"
  echo "  4. Add result: ${result}"
  echo "  5. Write back via MCP"
  echo ""

  write_audit "${workspace_id}" "agent-handoff" "completed" \
    "Handoff ${handoff_id} completed by ${agent_name}: ${result}" "${agent_name}"
}

echo "Agent Handoff loaded. Functions: create_handoff, list_handoffs, accept_handoff, complete_handoff"
