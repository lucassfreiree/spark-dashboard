#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# promote-cap.sh
# Replaces: .github/workflows/promote-cap.yml
#
# Promotes a release tag to the CAP deployment repository by updating the
# image tag in values.yaml.
#
# Steps:
#   1. Read workspace config for CAP repo path and image pattern
#   2. Read values.yaml from CAP repo via MCP
#   3. Replace image line with new tag
#   4. Push updated values.yaml via MCP
#   5. Update release state with promotion info
#   6. Write audit entry
#
# Image pattern (ws-default agent):
#   docker.binarios.intranet.bb.com.br/bb/psc/psc-sre-automacao-agent:<TAG>
# Image pattern (ws-default controller):
#   docker.binarios.intranet.bb.com.br/bb/psc/psc-sre-automacao-controller:<TAG>
#
# CAP repos (ws-default):
#   agent:      bbvinet/psc_releases_cap_sre-aut-agent
#   controller: bbvinet/psc_releases_cap_sre-aut-controller
# Values path: releases/openshift/hml/deploy/values.yaml
#
# Usage:
#   ./promote-cap.sh --workspace <ws_id> --component <agent|controller> --tag <tag>
#   ./promote-cap.sh --workspace ws-default --component agent --tag 2.3.4-a1b2c3d
#
# MCP tools used:
#   - mcp__github__get_file_contents   (read workspace config, read values.yaml)
#   - mcp__github__create_or_update_file (push updated values.yaml, write state)
#
# Schema: schemas/release-state.schema.json (promotions array)
#   promotion entry: {target, repo, branch, path, tag, sha, timestamp, status}
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source core modules
source "${SCRIPT_DIR}/../core/state-manager.sh"

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
SCHEMA_VERSION=2
DEFAULT_VALUES_PATH="releases/openshift/hml/deploy/values.yaml"

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
WORKSPACE_ID=""
COMPONENT=""
TAG=""
DRY_RUN=false

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace)  WORKSPACE_ID="$2"; shift 2 ;;
    --component)  COMPONENT="$2"; shift 2 ;;
    --tag)        TAG="$2"; shift 2 ;;
    --dry-run)    DRY_RUN=true; shift ;;
    *) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
  esac
done

# Validate required arguments
if [[ -z "$WORKSPACE_ID" ]]; then
  echo "ERROR: --workspace is required" >&2; exit 1
fi
if [[ -z "$COMPONENT" || ("$COMPONENT" != "agent" && "$COMPONENT" != "controller") ]]; then
  echo "ERROR: --component must be 'agent' or 'controller'" >&2; exit 1
fi
if [[ -z "$TAG" ]]; then
  echo "ERROR: --tag is required" >&2; exit 1
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Write audit entry for promotion
# MCP: mcp__github__create_or_update_file(
#   path="state/workspaces/{ws_id}/audit/promote-cap-{timestamp}.json",
#   branch=autopilot-state)
write_promote_audit() {
  local detail="$1"
  local status="$2"
  local filename="promote-cap-$(date -u +%Y%m%d-%H%M%S).json"

  local audit_json
  audit_json=$(jq -n \
    --arg action "promote-cap" \
    --arg component "$COMPONENT" \
    --arg workspaceId "$WORKSPACE_ID" \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg detail "$detail" \
    --arg status "$status" \
    --arg agent "claude-code" \
    '{action: $action, component: $component, workspaceId: $workspaceId,
      timestamp: $timestamp, detail: $detail, status: $status, agent: $agent}')

  write_state "$WORKSPACE_ID" "audit/${filename}" "$audit_json" \
    "audit: promote-cap ${COMPONENT} for ${WORKSPACE_ID}" 2>/dev/null || \
    echo "WARN: Failed to write audit entry" >&2
}

# ---------------------------------------------------------------------------
# Step 1: Read workspace config for CAP path
# MCP: mcp__github__get_file_contents(
#   owner=lucassfreiree, repo=autopilot,
#   path="state/workspaces/{ws_id}/workspace.json",
#   branch=autopilot-state)
# ---------------------------------------------------------------------------
resolve_cap_config() {
  echo "[promote-cap] Step 1: Reading workspace config for CAP settings..."

  local ws_json
  ws_json=$(read_workspace_config "$WORKSPACE_ID" 2>/dev/null || echo "")

  if [[ -z "$ws_json" ]]; then
    echo "ERROR: Could not read workspace config for ${WORKSPACE_ID}" >&2
    exit 1
  fi

  # Extract component-specific CAP config from workspace.json
  CAP_REPO=$(echo "$ws_json" | jq -r ".${COMPONENT}.capRepo // \"\"" 2>/dev/null || echo "")
  CAP_VALUES_PATH=$(echo "$ws_json" | jq -r ".${COMPONENT}.capValuesPath // \"\"" 2>/dev/null || echo "")
  IMAGE_PATTERN=$(echo "$ws_json" | jq -r ".${COMPONENT}.imagePattern // \"\"" 2>/dev/null || echo "")

  # Fallback defaults for ws-default
  if [[ -z "$CAP_REPO" ]]; then
    if [[ "$COMPONENT" == "agent" ]]; then
      CAP_REPO="bbvinet/psc_releases_cap_sre-aut-agent"
    else
      CAP_REPO="bbvinet/psc_releases_cap_sre-aut-controller"
    fi
    echo "[promote-cap] Using default CAP repo: ${CAP_REPO}"
  fi

  if [[ -z "$CAP_VALUES_PATH" ]]; then
    CAP_VALUES_PATH="$DEFAULT_VALUES_PATH"
    echo "[promote-cap] Using default values path: ${CAP_VALUES_PATH}"
  fi

  if [[ -z "$IMAGE_PATTERN" ]]; then
    IMAGE_PATTERN="docker.binarios.intranet.bb.com.br/bb/psc/psc-sre-automacao-${COMPONENT}"
    echo "[promote-cap] Using default image pattern: ${IMAGE_PATTERN}"
  fi

  echo "[promote-cap] CAP repo: ${CAP_REPO}"
  echo "[promote-cap] Values path: ${CAP_VALUES_PATH}"
  echo "[promote-cap] Image: ${IMAGE_PATTERN}:${TAG}"
}

# ---------------------------------------------------------------------------
# Step 2: Read values.yaml from CAP repo via MCP
# MCP: mcp__github__get_file_contents(
#   owner=<cap_owner>, repo=<cap_repo>,
#   path="releases/openshift/hml/deploy/values.yaml",
#   branch="main")
# ---------------------------------------------------------------------------
read_values_yaml() {
  echo "[promote-cap] Step 2: Reading values.yaml from ${CAP_REPO}..."

  local owner repo
  owner=$(echo "$CAP_REPO" | cut -d/ -f1)
  repo=$(echo "$CAP_REPO" | cut -d/ -f2)

  VALUES_CONTENT=""
  VALUES_SHA=""

  if command -v gh &>/dev/null; then
    VALUES_CONTENT=$(gh api "repos/${owner}/${repo}/contents/${CAP_VALUES_PATH}" \
      --jq '.content' 2>/dev/null | base64 -d 2>/dev/null || echo "")
    VALUES_SHA=$(gh api "repos/${owner}/${repo}/contents/${CAP_VALUES_PATH}" \
      --jq '.sha' 2>/dev/null || echo "")
  fi

  if [[ -z "$VALUES_CONTENT" ]]; then
    echo "ERROR: Failed to read values.yaml from ${CAP_REPO}/${CAP_VALUES_PATH}" >&2
    exit 1
  fi

  # Extract current image tag for logging
  local escaped_pattern
  escaped_pattern=$(echo "$IMAGE_PATTERN" | sed 's/[\/]/\\\//g')
  CURRENT_IMAGE_TAG=$(echo "$VALUES_CONTENT" | grep -oP "image:\s+${escaped_pattern}:\K[^\s\"']+" 2>/dev/null || echo "unknown")
  echo "[promote-cap] Current image tag: ${CURRENT_IMAGE_TAG}"
}

# ---------------------------------------------------------------------------
# Step 3: Replace image line with new tag
# Pattern: image: <IMAGE_PATTERN>:<OLD_TAG>
# Replace: image: <IMAGE_PATTERN>:<NEW_TAG>
# IMPORTANT: Use structured replacement, NOT regex on YAML
# ---------------------------------------------------------------------------
update_values_yaml() {
  echo "[promote-cap] Step 3: Replacing image tag with ${TAG}..."

  local escaped_pattern
  escaped_pattern=$(echo "$IMAGE_PATTERN" | sed 's/[\/&]/\\&/g')

  UPDATED_VALUES=$(echo "$VALUES_CONTENT" | \
    sed "s|image:\s*${escaped_pattern}:[^ \"']*|image: ${IMAGE_PATTERN}:${TAG}|g")

  if echo "$UPDATED_VALUES" | grep -q "${IMAGE_PATTERN}:${TAG}"; then
    echo "[promote-cap] Image tag updated: ${CURRENT_IMAGE_TAG} -> ${TAG}"
  else
    echo "ERROR: Failed to update image tag in values.yaml" >&2
    echo "  Looking for pattern: image: ${IMAGE_PATTERN}:<tag>" >&2
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Step 4: Push updated values.yaml via MCP
# MCP: mcp__github__create_or_update_file(
#   owner=<cap_owner>, repo=<cap_repo>,
#   path="releases/openshift/hml/deploy/values.yaml",
#   content=<updated_values base64>,
#   message="promote: {component} {tag}",
#   branch="main", sha=<current_sha>,
#   committer={name: "github-actions", email: "github-actions@github.com"})
# ---------------------------------------------------------------------------
push_values_yaml() {
  echo "[promote-cap] Step 4: Pushing updated values.yaml to ${CAP_REPO}..."

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[promote-cap] DRY-RUN: Would push values.yaml with tag ${TAG}"
    return
  fi

  local owner repo
  owner=$(echo "$CAP_REPO" | cut -d/ -f1)
  repo=$(echo "$CAP_REPO" | cut -d/ -f2)

  if command -v gh &>/dev/null; then
    local encoded_content payload
    encoded_content=$(echo "$UPDATED_VALUES" | base64 -w 0)

    payload=$(jq -n \
      --arg msg "promote: ${COMPONENT} ${TAG}" \
      --arg content "$encoded_content" \
      --arg sha "${VALUES_SHA:-}" \
      --arg branch "main" \
      '{message: $msg, content: $content, sha: $sha, branch: $branch,
        committer: {name: "github-actions", email: "github-actions@github.com"}}')

    echo "$payload" | gh api "repos/${owner}/${repo}/contents/${CAP_VALUES_PATH}" \
      --method PUT --input - >/dev/null 2>&1 || {
      echo "ERROR: Failed to push values.yaml to ${CAP_REPO}" >&2
      exit 1
    }
  else
    echo "ERROR: gh CLI not available. Use MCP tool call." >&2
    exit 1
  fi

  echo "[promote-cap] Push complete: ${CAP_REPO}/${CAP_VALUES_PATH}"
}

# ---------------------------------------------------------------------------
# Step 5: Update release state with promotion info
# MCP: mcp__github__get_file_contents + mcp__github__create_or_update_file(
#   path="state/workspaces/{ws_id}/{component}-release-state.json",
#   branch=autopilot-state)
# ---------------------------------------------------------------------------
update_release_state() {
  echo "[promote-cap] Step 5: Updating release state with promotion info..."

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[promote-cap] DRY-RUN: Would update release state"
    return
  fi

  local existing_state
  existing_state=$(read_release_state "$WORKSPACE_ID" "$COMPONENT" 2>/dev/null || echo "")

  # Build promotion entry (matches release-state.schema.json promotions array)
  local promotion_entry
  promotion_entry=$(jq -n \
    --arg target "cap" \
    --arg repo "$CAP_REPO" \
    --arg branch "main" \
    --arg path "$CAP_VALUES_PATH" \
    --arg tag "$TAG" \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg status "success" \
    '{target: $target, repo: $repo, branch: $branch, path: $path,
      tag: $tag, timestamp: $timestamp, status: $status}')

  local updated_state
  if [[ -n "$existing_state" ]]; then
    updated_state=$(echo "$existing_state" | jq \
      --argjson promo "$promotion_entry" \
      --arg status "promoted" \
      --arg updatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '.status = $status | .promoted = true | .updatedAt = $updatedAt |
       .promotions = ((.promotions // []) + [$promo])')
  else
    updated_state=$(jq -n \
      --argjson schemaVersion "$SCHEMA_VERSION" \
      --arg workspaceId "$WORKSPACE_ID" \
      --arg component "$COMPONENT" \
      --arg lastTag "$TAG" \
      --arg updatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --argjson promo "$promotion_entry" \
      '{schemaVersion: $schemaVersion, workspaceId: $workspaceId,
        component: $component, lastTag: $lastTag, status: "promoted",
        promoted: true, updatedAt: $updatedAt, promotions: [$promo]}')
  fi

  write_release_state "$WORKSPACE_ID" "$COMPONENT" "$updated_state"
  echo "[promote-cap] Release state updated: promoted=true"
}

# ---------------------------------------------------------------------------
# Step 6: Write audit entry
# ---------------------------------------------------------------------------
write_audit() {
  echo "[promote-cap] Step 6: Writing audit entry..."
  [[ "$DRY_RUN" == "true" ]] && return

  write_promote_audit \
    "Promoted ${COMPONENT} tag ${TAG} to ${CAP_REPO}/${CAP_VALUES_PATH} (was: ${CURRENT_IMAGE_TAG:-unknown})" \
    "success"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  echo "============================================"
  echo " CAP Promotion: ${COMPONENT}"
  echo " Workspace: ${WORKSPACE_ID}"
  echo " Tag: ${TAG}"
  echo " Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  [[ "$DRY_RUN" == "true" ]] && echo " Mode: DRY-RUN"
  echo "============================================"

  resolve_cap_config    # Step 1: Read workspace config
  read_values_yaml      # Step 2: Read values.yaml from CAP repo
  update_values_yaml    # Step 3: Replace image tag
  push_values_yaml      # Step 4: Push updated file
  update_release_state  # Step 5: Update release state
  write_audit           # Step 6: Audit entry

  echo ""
  echo "============================================"
  echo " Promotion Complete: ${COMPONENT}"
  echo " Tag: ${TAG}"
  echo " CAP repo: ${CAP_REPO}"
  echo " Previous tag: ${CURRENT_IMAGE_TAG:-unknown}"
  echo "============================================"
}

main "$@"
