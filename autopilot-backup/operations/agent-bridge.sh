#!/usr/bin/env bash
# ============================================================
# Agent Bridge - Autopilot Backup
# Replaces: .github/workflows/agent-bridge.yml
#
# Enables communication between AI agents (Claude, Codex,
# ChatGPT, Copilot, Devin) via shared state files.
#
# Usage: source this file, then call bridge functions
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/state-manager.sh"
source "${SCRIPT_DIR}/../core/audit-writer.sh"

# Send message between agents
# Usage: send_agent_message <workspace_id> <from_agent> <to_agent> <message> <priority>
#
# MCP TOOLS NEEDED:
#   mcp__github__create_or_update_file - Write message to state branch
#
# Messages stored at: state/workspaces/{ws_id}/handoffs/
send_agent_message() {
  local workspace_id="${1:?ERROR: workspace_id required}"
  local from_agent="${2:?ERROR: from_agent required}"
  local to_agent="${3:?ERROR: to_agent required}"
  local message="${4:?ERROR: message required}"
  local priority="${5:-normal}"

  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local msg_id
  msg_id="msg-$(date -u +%Y%m%d%H%M%S)-${from_agent}-${to_agent}"

  local msg_json
  msg_json=$(cat <<EOF
{
  "schemaVersion": 1,
  "messageId": "${msg_id}",
  "from": "${from_agent}",
  "to": "${to_agent}",
  "message": "${message}",
  "priority": "${priority}",
  "createdAt": "${timestamp}",
  "status": "pending",
  "workspace": "${workspace_id}"
}
EOF
)

  echo "=== Agent Bridge: ${from_agent} -> ${to_agent} ==="
  echo ""
  echo "  Message ID: ${msg_id}"
  echo "  Priority: ${priority}"
  echo "  Content: ${message}"
  echo ""
  echo "  MCP CALL: mcp__github__create_or_update_file"
  echo "    owner: lucassfreiree"
  echo "    repo: autopilot"
  echo "    path: state/workspaces/${workspace_id}/handoffs/${msg_id}.json"
  echo "    content: ${msg_json}"
  echo "    branch: autopilot-state"
  echo "    message: 'bridge: ${from_agent} -> ${to_agent}'"
  echo ""

  write_audit "${workspace_id}" "agent-bridge" "sent" \
    "Message from ${from_agent} to ${to_agent}: ${message}" "${from_agent}"
}

# Read pending messages for an agent
# Usage: read_agent_messages <workspace_id> <agent_name>
read_agent_messages() {
  local workspace_id="${1:?ERROR: workspace_id required}"
  local agent_name="${2:?ERROR: agent_name required}"

  echo "=== Pending Messages for ${agent_name} in ${workspace_id} ==="
  echo ""
  echo "  MCP CALL: mcp__github__get_file_contents"
  echo "    owner: lucassfreiree"
  echo "    repo: autopilot"
  echo "    path: state/workspaces/${workspace_id}/handoffs/"
  echo "    branch: autopilot-state"
  echo ""
  echo "  Then filter messages where 'to' == '${agent_name}' and status == 'pending'"
  echo ""
}

# Mark message as completed
# Usage: complete_agent_message <workspace_id> <message_id>
complete_agent_message() {
  local workspace_id="${1:?ERROR: workspace_id required}"
  local message_id="${2:?ERROR: message_id required}"

  echo "=== Completing Message: ${message_id} ==="
  echo ""
  echo "  MCP PROCEDURE:"
  echo "  1. Read current message file"
  echo "  2. Update status to 'completed'"
  echo "  3. Add completedAt timestamp"
  echo "  4. Write back via MCP"
  echo ""
}

echo "Agent Bridge loaded. Functions: send_agent_message, read_agent_messages, complete_agent_message"
