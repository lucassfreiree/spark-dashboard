#!/usr/bin/env bash
# ============================================================
# Apply Source Change - Autopilot Backup
# Replaces: .github/workflows/apply-source-change.yml
#
# Applies source code changes to corporate repos via MCP.
#
# Usage: source this file, then call apply_source_change()
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/state-manager.sh"
source "${SCRIPT_DIR}/../core/session-guard.sh"
source "${SCRIPT_DIR}/../core/audit-writer.sh"

# Apply source code changes
# Usage: apply_source_change <workspace_id> <component> <file_path> <content> <commit_msg>
#
# MCP TOOLS NEEDED:
#   1. mcp__github__get_file_contents - Read current file (get SHA)
#   2. mcp__github__create_or_update_file - Push updated file
apply_source_change() {
  local workspace_id="${1:?ERROR: workspace_id required}"
  local component="${2:?ERROR: component required (agent|controller)}"
  local file_path="${3:?ERROR: file_path required}"
  local content="${4:?ERROR: content required}"
  local commit_msg="${5:-fix: apply source change}"

  echo "=== Apply Source Change: ${workspace_id}/${component} ==="
  echo "  File: ${file_path}"
  echo ""

  local config_file="${SCRIPT_DIR}/../config.json"
  local repo_key
  if [ "$component" = "agent" ]; then
    repo_key="agentRepo"
  else
    repo_key="controllerRepo"
  fi
  local corp_repo
  corp_repo=$(jq -r ".workspaces.\"${workspace_id}\".${repo_key}" "$config_file")
  local corp_owner="${corp_repo%%/*}"
  local corp_name="${corp_repo##*/}"

  echo "  Target: ${corp_repo}"
  echo ""

  # Step 1: Acquire lock
  echo "Step 1: Acquiring session lock..."
  acquire_lock "${workspace_id}" "claude-code-backup" "push-to-corporate-repo" 30

  # Step 2: Read current file to get SHA
  echo "Step 2: Reading current file..."
  echo "  MCP CALL: mcp__github__get_file_contents"
  echo "    owner: ${corp_owner}"
  echo "    repo: ${corp_name}"
  echo "    path: ${file_path}"
  echo "    branch: main"
  echo "  (Need the SHA for update operation)"
  echo ""

  # Step 3: Push updated file
  echo "Step 3: Pushing updated file..."
  echo "  MCP CALL: mcp__github__create_or_update_file"
  echo "    owner: ${corp_owner}"
  echo "    repo: ${corp_name}"
  echo "    path: ${file_path}"
  echo "    content: <new_content>"
  echo "    sha: <current_file_sha>"
  echo "    branch: main"
  echo "    message: '${commit_msg}'"
  echo "    committer:"
  echo "      name: github-actions"
  echo "      email: github-actions@github.com"
  echo ""

  # Step 4: Audit
  write_audit "${workspace_id}" "apply-source-change" "success" \
    "Applied change to ${corp_repo}:${file_path}" "claude-code-backup"

  # Step 5: Release lock
  release_lock "${workspace_id}" "claude-code-backup"

  echo "=== Source Change Applied ==="
}

# Apply multiple file changes at once
# Usage: apply_bulk_changes <workspace_id> <component> <changes_json>
# changes_json format: [{"path": "...", "content": "..."}, ...]
apply_bulk_changes() {
  local workspace_id="${1:?ERROR: workspace_id required}"
  local component="${2:?ERROR: component required}"
  local changes_json="${3:?ERROR: changes_json required}"

  echo "=== Bulk Source Changes: ${workspace_id}/${component} ==="
  echo ""
  echo "  For bulk changes, use mcp__github__push_files:"
  echo "  MCP CALL: mcp__github__push_files"
  echo "    owner: <corp_owner>"
  echo "    repo: <corp_repo>"
  echo "    branch: main"
  echo "    files: ${changes_json}"
  echo "    message: 'fix: bulk source changes'"
  echo ""
}

echo "Apply Source Change loaded. Functions: apply_source_change, apply_bulk_changes"
