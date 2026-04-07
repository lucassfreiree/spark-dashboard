#!/usr/bin/env bash
# ============================================================
# Fetch Files - Autopilot Backup
# Replaces: .github/workflows/fetch-files.yml
#
# Fetches files from corporate repos for analysis.
#
# Usage: source this file, then call fetch_file()
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Fetch a single file from corporate repo
# Usage: fetch_file <workspace_id> <component> <file_path>
fetch_file() {
  local workspace_id="${1:?ERROR: workspace_id required}"
  local component="${2:?ERROR: component required (agent|controller)}"
  local file_path="${3:?ERROR: file_path required}"

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

  echo "=== Fetch File: ${corp_repo}/${file_path} ==="
  echo ""
  echo "  MCP CALL: mcp__github__get_file_contents"
  echo "    owner: ${corp_owner}"
  echo "    repo: ${corp_name}"
  echo "    path: ${file_path}"
  echo "    branch: main"
  echo ""
}

# Fetch multiple files
# Usage: fetch_files <workspace_id> <component> <file1> [file2] [file3] ...
fetch_files() {
  local workspace_id="${1:?ERROR: workspace_id required}"
  local component="${2:?ERROR: component required}"
  shift 2

  for file_path in "$@"; do
    fetch_file "${workspace_id}" "${component}" "${file_path}"
  done
}

# Fetch directory listing
# Usage: fetch_directory <workspace_id> <component> <dir_path>
fetch_directory() {
  local workspace_id="${1:?ERROR: workspace_id required}"
  local component="${2:?ERROR: component required}"
  local dir_path="${3:-.}"

  local config_file="${SCRIPT_DIR}/../config.json"
  local repo_key
  if [ "$component" = "agent" ]; then
    repo_key="agentRepo"
  else
    repo_key="controllerRepo"
  fi
  local corp_repo
  corp_repo=$(jq -r ".workspaces.\"${workspace_id}\".${repo_key}" "$config_file")

  echo "=== Fetch Directory: ${corp_repo}/${dir_path} ==="
  echo ""
  echo "  MCP CALL: mcp__github__get_file_contents"
  echo "    owner: ${corp_repo%%/*}"
  echo "    repo: ${corp_repo##*/}"
  echo "    path: ${dir_path}"
  echo "    branch: main"
  echo "  (Returns directory listing for directories)"
  echo ""
}

# Fetch key project files (package.json, tsconfig, etc.)
# Usage: fetch_project_files <workspace_id> <component>
fetch_project_files() {
  local workspace_id="${1:?ERROR: workspace_id required}"
  local component="${2:?ERROR: component required}"

  echo "=== Fetching Key Project Files ==="
  fetch_files "${workspace_id}" "${component}" \
    "package.json" \
    "tsconfig.json" \
    "nest-cli.json" \
    ".eslintrc.js" \
    "src/main.ts"
}

echo "Fetch Files loaded. Functions: fetch_file, fetch_files, fetch_directory, fetch_project_files"
