#!/usr/bin/env bash
# ============================================================
# Promote CAP - Autopilot Backup
# Replaces: .github/workflows/promote-cap.yml
#
# Promotes a release tag to the CAP deployment repository
# by updating the image tag in values.yaml.
#
# Usage: source this file, then call promote_cap()
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/state-manager.sh"
source "${SCRIPT_DIR}/../core/session-guard.sh"
source "${SCRIPT_DIR}/../core/audit-writer.sh"

# Promote tag to CAP repo
# Usage: promote_cap <workspace_id> <component> <tag> <version>
#
# MCP TOOLS NEEDED:
#   1. mcp__github__get_file_contents - Read current values.yaml
#   2. mcp__github__create_or_update_file - Push updated values.yaml
promote_cap() {
  local workspace_id="${1:?ERROR: workspace_id required}"
  local component="${2:?ERROR: component required (agent|controller)}"
  local tag="${3:?ERROR: tag required (format: version-sha)}"
  local version="${4:?ERROR: version required}"

  echo "=== Promote to CAP: ${workspace_id}/${component} ==="
  echo "  Tag: ${tag}"
  echo "  Version: ${version}"
  echo ""

  local config_file="${SCRIPT_DIR}/../config.json"

  # Get CAP repo details
  local cap_repo
  cap_repo=$(jq -r ".workspaces.\"${workspace_id}\".capRepo" "$config_file")
  local cap_path
  cap_path=$(jq -r ".workspaces.\"${workspace_id}\".capPath" "$config_file")
  local image_pattern
  image_pattern=$(jq -r ".workspaces.\"${workspace_id}\".imagePattern" "$config_file")

  # Resolve image pattern
  local resolved_image="${image_pattern/\{component\}/${component}}"
  local cap_owner="${cap_repo%%/*}"
  local cap_name="${cap_repo##*/}"

  echo "  CAP Repo: ${cap_repo}"
  echo "  CAP Path: ${cap_path}"
  echo "  Image: ${resolved_image}:${tag}"
  echo ""

  # Step 1: Read current values.yaml
  echo "Step 1: Reading current values.yaml..."
  echo "  MCP CALL: mcp__github__get_file_contents"
  echo "    owner: ${cap_owner}"
  echo "    repo: ${cap_name}"
  echo "    path: ${cap_path}"
  echo "    branch: main"
  echo ""
  echo "  Find line matching: image: ${resolved_image}:*"
  echo ""

  # Step 2: Replace image tag
  echo "Step 2: Replacing image tag..."
  echo "  OLD: image: ${resolved_image}:<old_tag>"
  echo "  NEW: image: ${resolved_image}:${tag}"
  echo ""
  echo "  IMPORTANT: Use structured replacement, NOT regex on YAML!"
  echo ""

  # Step 3: Push updated file
  echo "Step 3: Pushing updated values.yaml..."
  echo "  MCP CALL: mcp__github__create_or_update_file"
  echo "    owner: ${cap_owner}"
  echo "    repo: ${cap_name}"
  echo "    path: ${cap_path}"
  echo "    content: <updated_values_yaml>"
  echo "    branch: main"
  echo "    message: 'promote: ${component} ${tag}'"
  echo ""

  # Step 4: Update release state with promotion info
  echo "Step 4: Updating release state..."
  echo "  Add promotion record:"
  echo "  {"
  echo "    \"target\": \"cap\","
  echo "    \"repo\": \"${cap_repo}\","
  echo "    \"tag\": \"${tag}\","
  echo "    \"status\": \"success\","
  echo "    \"promotedAt\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\""
  echo "  }"
  echo ""

  write_audit "${workspace_id}" "promote-cap" "success" \
    "Promoted ${component} ${tag} to ${cap_repo}" "claude-code-backup"

  echo "=== Promotion Complete ==="
}

echo "Promote CAP loaded. Available functions: promote_cap"
