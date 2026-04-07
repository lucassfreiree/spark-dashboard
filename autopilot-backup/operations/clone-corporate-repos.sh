#!/usr/bin/env bash
# ============================================================
# Clone Corporate Repos - Autopilot Backup
# Replaces: .github/workflows/clone-corporate-repos.yml
#
# Reads/clones corporate repo contents via MCP tools.
# Since we can't git clone in this environment, we use
# MCP get_file_contents to browse and read repo contents.
#
# Usage: source this file, then call browse_corporate_repo()
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/state-manager.sh"

# Browse corporate repo structure
# Usage: browse_corporate_repo <workspace_id> <component> [path]
#
# MCP TOOLS NEEDED:
#   mcp__github__get_file_contents - List and read files
browse_corporate_repo() {
  local workspace_id="${1:?ERROR: workspace_id required}"
  local component="${2:?ERROR: component required (agent|controller)}"
  local path="${3:-}"

  local repo_key
  if [ "$component" = "agent" ]; then
    repo_key="agentRepo"
  else
    repo_key="controllerRepo"
  fi
  local corp_repo
  corp_repo=$(jq -r ".workspaces.\"${workspace_id}\".${repo_key}" \
    "${SCRIPT_DIR}/../config.json")
  local corp_owner="${corp_repo%%/*}"
  local corp_name="${corp_repo##*/}"

  echo "=== Browse Corporate Repo: ${corp_repo} ==="
  echo "  Path: ${path:-/}"
  echo ""
  echo "  MCP CALL: mcp__github__get_file_contents"
  echo "    owner: ${corp_owner}"
  echo "    repo: ${corp_name}"
  echo "    path: ${path}"
  echo "    branch: main"
  echo ""
  echo "  This will return:"
  echo "    - For directories: list of files/subdirectories"
  echo "    - For files: file content"
  echo ""
}

# Read specific file from corporate repo
# Usage: read_corporate_file <workspace_id> <component> <file_path>
read_corporate_file() {
  local workspace_id="${1:?ERROR: workspace_id required}"
  local component="${2:?ERROR: component required}"
  local file_path="${3:?ERROR: file_path required}"

  local repo_key
  if [ "$component" = "agent" ]; then
    repo_key="agentRepo"
  else
    repo_key="controllerRepo"
  fi
  local corp_repo
  corp_repo=$(jq -r ".workspaces.\"${workspace_id}\".${repo_key}" \
    "${SCRIPT_DIR}/../config.json")

  echo "  MCP CALL: mcp__github__get_file_contents"
  echo "    owner: ${corp_repo%%/*}"
  echo "    repo: ${corp_repo##*/}"
  echo "    path: ${file_path}"
  echo "    branch: main"
}

echo "Clone Corporate Repos loaded. Functions: browse_corporate_repo, read_corporate_file"
