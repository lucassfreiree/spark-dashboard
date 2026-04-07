#!/usr/bin/env bash
# ============================================================
# Release Approval - Autopilot Backup
# Replaces: .github/workflows/release-approval.yml
#
# Manual approval gate for releases. One of the 3 operations
# that requires human intervention.
#
# Usage: source this file, then call approval functions
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/state-manager.sh"
source "${SCRIPT_DIR}/../core/audit-writer.sh"

# Request approval for a release
# Usage: request_approval <workspace_id> <component> <version> <requester>
request_approval() {
  local workspace_id="${1:?ERROR: workspace_id required}"
  local component="${2:?ERROR: component required}"
  local version="${3:?ERROR: version required}"
  local requester="${4:-claude-code-backup}"

  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local approval_id
  approval_id="approval-$(date -u +%Y%m%d%H%M%S)-${component}"

  local approval_json
  approval_json=$(cat <<EOF
{
  "schemaVersion": 1,
  "approvalId": "${approval_id}",
  "workspaceId": "${workspace_id}",
  "component": "${component}",
  "version": "${version}",
  "requestedBy": "${requester}",
  "requestedAt": "${timestamp}",
  "status": "pending",
  "approvedBy": null,
  "approvedAt": null,
  "reason": null
}
EOF
)

  echo "=== Release Approval Request ==="
  echo "  ID: ${approval_id}"
  echo "  Component: ${component}"
  echo "  Version: ${version}"
  echo "  Requested by: ${requester}"
  echo ""
  echo "  MCP CALL: mcp__github__create_or_update_file"
  echo "    owner: lucassfreiree"
  echo "    repo: autopilot"
  echo "    path: state/workspaces/${workspace_id}/approvals/${approval_id}.json"
  echo "    content: <approval_json>"
  echo "    branch: autopilot-state"
  echo ""

  write_audit "${workspace_id}" "release-approval" "requested" \
    "Approval requested for ${component} ${version}" "${requester}"

  echo "Awaiting approval. ID: ${approval_id}"
}

# Approve a release
# Usage: approve_release <workspace_id> <approval_id> <approver> [reason]
approve_release() {
  local workspace_id="${1:?ERROR: workspace_id required}"
  local approval_id="${2:?ERROR: approval_id required}"
  local approver="${3:?ERROR: approver required}"
  local reason="${4:-Approved}"

  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  echo "=== Approve Release: ${approval_id} ==="
  echo ""
  echo "  MCP PROCEDURE:"
  echo "  1. Read approval file from state branch"
  echo "  2. Update: status='approved', approvedBy='${approver}', approvedAt='${timestamp}'"
  echo "  3. Write back via MCP"
  echo ""

  write_audit "${workspace_id}" "release-approval" "approved" \
    "Release ${approval_id} approved by ${approver}: ${reason}" "${approver}"

  echo "Release approved. Proceed with deployment."
}

# Reject a release
# Usage: reject_release <workspace_id> <approval_id> <rejector> <reason>
reject_release() {
  local workspace_id="${1:?ERROR: workspace_id required}"
  local approval_id="${2:?ERROR: approval_id required}"
  local rejector="${3:?ERROR: rejector required}"
  local reason="${4:?ERROR: reason required}"

  echo "=== Reject Release: ${approval_id} ==="
  echo ""
  echo "  MCP PROCEDURE:"
  echo "  1. Read approval file"
  echo "  2. Update: status='rejected', rejectedBy='${rejector}', reason='${reason}'"
  echo "  3. Write back via MCP"
  echo ""

  write_audit "${workspace_id}" "release-approval" "rejected" \
    "Release ${approval_id} rejected by ${rejector}: ${reason}" "${rejector}"

  echo "Release rejected."
}

# Check approval status
# Usage: check_approval <workspace_id> <approval_id>
check_approval() {
  local workspace_id="${1:?ERROR: workspace_id required}"
  local approval_id="${2:?ERROR: approval_id required}"

  echo "=== Check Approval: ${approval_id} ==="
  echo ""
  echo "  MCP CALL: mcp__github__get_file_contents"
  echo "    path: state/workspaces/${workspace_id}/approvals/${approval_id}.json"
  echo "    branch: autopilot-state"
  echo ""
}

echo "Release Approval loaded. Functions: request_approval, approve_release, reject_release, check_approval"
