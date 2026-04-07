#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# release-approval.sh — Replaces: release-approval.yml (GitHub Actions workflow)
#
# Manual approval gate for releases. In the original system, this is a
# workflow_dispatch workflow that creates, checks, approves, or rejects
# release approval requests. Approvals are stored as individual JSON files
# under each workspace's approvals/ directory.
#
# State path: state/workspaces/{ws_id}/approvals/
# Schema: schemas/approval.schema.json
#
# Required fields (from schema):
#   - approvalId, workspaceId, component, version
#   - approvedAt, approvedBy, status
#
# Approval statuses: approved, rejected, expired
# Components: controller, agent, both
#
# Operations:
#   request  — Create a new approval request (status: pending)
#   check    — Check the status of an approval request
#   approve  — Approve a pending request with reason
#   reject   — Reject a pending request with reason
#   list     — List all approvals for a workspace
#   cleanup  — Remove expired approvals
#
# MCP Tool Calls:
#   - mcp__github__get_file_contents: Read approval files from
#       state/workspaces/{ws_id}/approvals/ on autopilot-state
#   - mcp__github__create_or_update_file: Write approval files
#   - mcp__github__delete_file: Remove expired approval files
#
# Usage:
#   ./release-approval.sh request --workspace ws-default --component controller --version 3.8.3
#   ./release-approval.sh check   --workspace ws-default --id appr-20260407-143022
#   ./release-approval.sh approve --workspace ws-default --id appr-20260407-143022 --by lucas --reason "Tested OK"
#   ./release-approval.sh reject  --workspace ws-default --id appr-20260407-143022 --by lucas --reason "Tests failing"
#   ./release-approval.sh list    --workspace ws-default
#   ./release-approval.sh cleanup --workspace ws-default
#
# Environment:
#   GITHUB_TOKEN — GitHub PAT with repo access (required)
###############################################################################

# ── Source core utilities ────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="${SCRIPT_DIR}/../core"
CONFIG_FILE="${SCRIPT_DIR}/../config.json"

for core_script in "${CORE_DIR}"/*.sh; do
  [ -f "$core_script" ] && source "$core_script" 2>/dev/null || true
done

# ── Constants ────────────────────────────────────────────────────────────────
REPO_OWNER="lucassfreiree"
REPO_NAME="autopilot"
STATE_BRANCH="autopilot-state"
STATE_BASE_PATH="state/workspaces"
DEFAULT_APPROVAL_TTL_HOURS=24

if [ -f "$CONFIG_FILE" ]; then
  REPO_OWNER=$(jq -r '.autopilotRepo.owner // "lucassfreiree"' "$CONFIG_FILE" 2>/dev/null || echo "lucassfreiree")
  REPO_NAME=$(jq -r '.autopilotRepo.repo // "autopilot"' "$CONFIG_FILE" 2>/dev/null || echo "autopilot")
fi

# ── Arguments ────────────────────────────────────────────────────────────────
ACTION=""
WORKSPACE_ID=""
APPROVAL_ID=""
COMPONENT=""
VERSION=""
APPROVED_BY="claude-code-backup"
REASON=""
RUN_ID=""
TTL_HOURS="$DEFAULT_APPROVAL_TTL_HOURS"

# Parse action (positional)
if [[ $# -gt 0 ]]; then
  ACTION="$1"
  shift
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace)   WORKSPACE_ID="$2"; shift 2 ;;
    --id)          APPROVAL_ID="$2"; shift 2 ;;
    --component)   COMPONENT="$2"; shift 2 ;;
    --version)     VERSION="$2"; shift 2 ;;
    --by)          APPROVED_BY="$2"; shift 2 ;;
    --reason)      REASON="$2"; shift 2 ;;
    --run-id)      RUN_ID="$2"; shift 2 ;;
    --ttl)         TTL_HOURS="$2"; shift 2 ;;
    *)             echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [ -z "$ACTION" ]; then
  echo "Usage: $0 {request|check|approve|reject|list|cleanup} --workspace <ws_id> [options]"
  echo ""
  echo "Actions:"
  echo "  request --workspace <ws_id> --component <controller|agent|both> --version <ver> [--ttl <hours>]"
  echo "  check   --workspace <ws_id> --id <approval_id>"
  echo "  approve --workspace <ws_id> --id <approval_id> --by <who> [--reason <text>]"
  echo "  reject  --workspace <ws_id> --id <approval_id> --by <who> --reason <text>"
  echo "  list    --workspace <ws_id>"
  echo "  cleanup --workspace <ws_id>"
  exit 1
fi

if [ -z "$WORKSPACE_ID" ]; then
  echo "ERROR: --workspace is required"
  exit 1
fi

APPROVALS_PATH="${STATE_BASE_PATH}/${WORKSPACE_ID}/approvals"

# ── Functions ────────────────────────────────────────────────────────────────

log_info()    { echo "[INFO] $(date -u +"%Y-%m-%dT%H:%M:%SZ") $*"; }
log_error()   { echo "[ERROR] $(date -u +"%Y-%m-%dT%H:%M:%SZ") $*" >&2; }
log_success() { echo "[OK] $(date -u +"%Y-%m-%dT%H:%M:%SZ") $*"; }
log_warn()    { echo "[WARN] $(date -u +"%Y-%m-%dT%H:%M:%SZ") $*"; }

check_prerequisites() {
  if [ -z "${GITHUB_TOKEN:-}" ]; then
    log_error "GITHUB_TOKEN is not set."
    exit 1
  fi
}

# Generate a unique approval ID based on timestamp
generate_approval_id() {
  echo "appr-$(date -u +"%Y%m%d-%H%M%S")"
}

# Read a file from the state branch (decoded content)
# Args: $1 = file path
# MCP equivalent: mcp__github__get_file_contents(
#   owner="lucassfreiree", repo="autopilot",
#   path=<file_path>, branch="autopilot-state"
# )
read_state_content() {
  local file_path="$1"
  local response
  response=$(curl -sS -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/${file_path}?ref=${STATE_BRANCH}" 2>/dev/null)

  echo "$response" | jq -r '.content // empty' 2>/dev/null | base64 -d 2>/dev/null || echo ""
}

# Get the SHA of a file on the state branch
# Args: $1 = file path
get_file_sha() {
  local file_path="$1"
  curl -sS -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/${file_path}?ref=${STATE_BRANCH}" \
    | jq -r '.sha // empty' 2>/dev/null || echo ""
}

# Write a file to the state branch
# Args: $1 = file path, $2 = content string, $3 = commit message
# MCP equivalent: mcp__github__create_or_update_file(
#   owner="lucassfreiree", repo="autopilot",
#   path=<file_path>, content=<base64>,
#   message=<msg>, branch="autopilot-state",
#   sha=<current SHA if updating>
# )
write_state_file() {
  local file_path="$1"
  local content="$2"
  local commit_message="$3"

  # Validate JSON before writing
  if ! echo "$content" | jq empty 2>/dev/null; then
    log_error "Content is not valid JSON"
    return 1
  fi

  local content_b64
  content_b64=$(echo -n "$content" | base64 -w 0)

  local api_url="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/${file_path}"

  local existing_sha=""
  existing_sha=$(curl -sS -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    "${api_url}?ref=${STATE_BRANCH}" 2>/dev/null | jq -r '.sha // empty' 2>/dev/null || echo "")

  local payload
  if [ -n "$existing_sha" ]; then
    payload=$(jq -n \
      --arg message "$commit_message" \
      --arg content "$content_b64" \
      --arg branch "$STATE_BRANCH" \
      --arg sha "$existing_sha" \
      '{ message: $message, content: $content, branch: $branch, sha: $sha }')
  else
    payload=$(jq -n \
      --arg message "$commit_message" \
      --arg content "$content_b64" \
      --arg branch "$STATE_BRANCH" \
      '{ message: $message, content: $content, branch: $branch }')
  fi

  local result
  result=$(curl -sS -X PUT \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    -d "$payload" \
    "$api_url" | jq -r '.content.path // "FAILED"' 2>/dev/null)

  if [ "$result" = "FAILED" ]; then
    log_error "Failed to write ${file_path}"
    return 1
  fi
  return 0
}

# Delete a file from the state branch
# Args: $1 = file path, $2 = file SHA, $3 = commit message
# MCP equivalent: mcp__github__delete_file(
#   owner="lucassfreiree", repo="autopilot",
#   path=<file_path>, message=<msg>,
#   branch="autopilot-state", sha=<file SHA>
# )
delete_state_file() {
  local file_path="$1"
  local file_sha="$2"
  local commit_message="$3"

  local payload
  payload=$(jq -n \
    --arg message "$commit_message" \
    --arg sha "$file_sha" \
    --arg branch "$STATE_BRANCH" \
    '{ message: $message, sha: $sha, branch: $branch }')

  local result
  result=$(curl -sS -X DELETE \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    -d "$payload" \
    "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/${file_path}" \
    | jq -r '.commit.sha // "FAILED"' 2>/dev/null)

  [ "$result" != "FAILED" ]
}

# List all approval files in the approvals directory
# Returns: file names (one per line), excluding .gitkeep
# MCP equivalent: mcp__github__get_file_contents(
#   path="state/workspaces/{ws_id}/approvals/", branch="autopilot-state"
# )
list_approval_files() {
  curl -sS -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/${APPROVALS_PATH}?ref=${STATE_BRANCH}" \
    | jq -r '.[] | select(.type == "file") | select(.name | endswith(".json")) | select(.name != ".gitkeep") | .name' 2>/dev/null || echo ""
}

# Validate component value against schema enum
validate_component() {
  local comp="$1"
  case "$comp" in
    controller|agent|both) return 0 ;;
    *)
      log_error "Invalid component '${comp}'. Must be: controller, agent, or both"
      return 1
      ;;
  esac
}

# ── Actions ──────────────────────────────────────────────────────────────────

# Create a new approval request
# Creates: approvals/{approval_id}.json with status "pending"
# Note: "pending" is a transient pre-decision state not in the schema enum
do_request() {
  if [ -z "$COMPONENT" ]; then
    log_error "--component is required for request action"
    exit 1
  fi
  validate_component "$COMPONENT" || exit 1

  if [ -z "$VERSION" ]; then
    log_error "--version is required for request action"
    exit 1
  fi

  local approval_id
  approval_id=$(generate_approval_id)

  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Calculate expiration time
  local expires_at
  expires_at=$(date -u -d "+${TTL_HOURS} hours" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")

  log_info "Creating approval request..."
  log_info "  ID:        ${approval_id}"
  log_info "  Component: ${COMPONENT}"
  log_info "  Version:   ${VERSION}"
  log_info "  TTL:       ${TTL_HOURS} hours"

  # Build approval JSON (based on approval.schema.json)
  local approval_json
  approval_json=$(jq -n \
    --arg approvalId "$approval_id" \
    --arg workspaceId "$WORKSPACE_ID" \
    --arg component "$COMPONENT" \
    --arg version "$VERSION" \
    --arg approvedAt "$now" \
    --arg approvedBy "pending" \
    --arg status "pending" \
    --arg runId "${RUN_ID:-}" \
    --arg expiresAt "${expires_at:-}" \
    '{
      approvalId: $approvalId,
      workspaceId: $workspaceId,
      component: $component,
      version: $version,
      approvedAt: $approvedAt,
      approvedBy: $approvedBy,
      status: $status,
      runId: (if $runId == "" then null else $runId end),
      expiresAt: (if $expiresAt == "" then null else $expiresAt end),
      requestedAt: $approvedAt,
      reason: null
    }')

  local file_path="${APPROVALS_PATH}/${approval_id}.json"

  if write_state_file "$file_path" "$approval_json" \
    "approval: request ${approval_id} for ${COMPONENT} ${VERSION} in ${WORKSPACE_ID}"; then
    log_success "Approval request created: ${approval_id}"
    echo "$approval_json" | jq .
    echo ""
    echo "To approve: $0 approve --workspace ${WORKSPACE_ID} --id ${approval_id} --by <who> --reason <text>"
    echo "To reject:  $0 reject  --workspace ${WORKSPACE_ID} --id ${approval_id} --by <who> --reason <text>"
  else
    log_error "Failed to create approval request"
    exit 1
  fi
}

# Check the status of a specific approval
# Exit codes: 0=approved, 1=rejected/expired, 2=pending
do_check() {
  if [ -z "$APPROVAL_ID" ]; then
    log_error "--id is required for check action"
    exit 1
  fi

  local file_path="${APPROVALS_PATH}/${APPROVAL_ID}.json"
  local content
  content=$(read_state_content "$file_path")

  if [ -z "$content" ]; then
    log_error "Approval '${APPROVAL_ID}' not found"
    exit 1
  fi

  local status
  status=$(echo "$content" | jq -r '.status // "unknown"' 2>/dev/null)

  # Check if a pending approval has expired based on expiresAt
  if [ "$status" = "pending" ]; then
    local expires_at
    expires_at=$(echo "$content" | jq -r '.expiresAt // ""' 2>/dev/null)

    if [ -n "$expires_at" ] && [ "$expires_at" != "null" ]; then
      local now_epoch exp_epoch
      now_epoch=$(date +%s)
      exp_epoch=$(date -d "$expires_at" +%s 2>/dev/null || echo "0")

      if [ "$exp_epoch" -gt 0 ] && [ "$now_epoch" -gt "$exp_epoch" ]; then
        log_warn "Approval '${APPROVAL_ID}' has EXPIRED"
        status="expired"
        content=$(echo "$content" | jq '.status = "expired"')
      fi
    fi
  fi

  echo "$content" | jq .

  # Exit code based on status
  case "$status" in
    approved) exit 0 ;;
    pending)  exit 2 ;;
    rejected) exit 1 ;;
    expired)  exit 1 ;;
    *)        exit 1 ;;
  esac
}

# Approve a pending request
do_approve() {
  if [ -z "$APPROVAL_ID" ]; then
    log_error "--id is required for approve action"
    exit 1
  fi

  local file_path="${APPROVALS_PATH}/${APPROVAL_ID}.json"
  local current
  current=$(read_state_content "$file_path")

  if [ -z "$current" ]; then
    log_error "Approval '${APPROVAL_ID}' not found"
    exit 1
  fi

  local current_status
  current_status=$(echo "$current" | jq -r '.status // ""' 2>/dev/null)

  if [ "$current_status" != "pending" ]; then
    log_error "Approval '${APPROVAL_ID}' is not pending (current status: ${current_status})"
    exit 1
  fi

  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Update the approval record with approved status
  local updated
  updated=$(echo "$current" | jq \
    --arg status "approved" \
    --arg approvedAt "$now" \
    --arg approvedBy "$APPROVED_BY" \
    --arg reason "${REASON:-Approved}" \
    '.status = $status | .approvedAt = $approvedAt | .approvedBy = $approvedBy | .reason = $reason')

  if write_state_file "$file_path" "$updated" \
    "approval: APPROVED ${APPROVAL_ID} by ${APPROVED_BY}"; then
    log_success "Approval '${APPROVAL_ID}' APPROVED by ${APPROVED_BY}"
    echo "$updated" | jq .
  else
    log_error "Failed to approve"
    exit 1
  fi
}

# Reject a pending request (--reason is mandatory)
do_reject() {
  if [ -z "$APPROVAL_ID" ]; then
    log_error "--id is required for reject action"
    exit 1
  fi

  if [ -z "$REASON" ]; then
    log_error "--reason is required for reject action"
    exit 1
  fi

  local file_path="${APPROVALS_PATH}/${APPROVAL_ID}.json"
  local current
  current=$(read_state_content "$file_path")

  if [ -z "$current" ]; then
    log_error "Approval '${APPROVAL_ID}' not found"
    exit 1
  fi

  local current_status
  current_status=$(echo "$current" | jq -r '.status // ""' 2>/dev/null)

  if [ "$current_status" != "pending" ]; then
    log_error "Approval '${APPROVAL_ID}' is not pending (current status: ${current_status})"
    exit 1
  fi

  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Update the approval record with rejected status
  local updated
  updated=$(echo "$current" | jq \
    --arg status "rejected" \
    --arg approvedAt "$now" \
    --arg approvedBy "$APPROVED_BY" \
    --arg reason "$REASON" \
    '.status = $status | .approvedAt = $approvedAt | .approvedBy = $approvedBy | .reason = $reason')

  if write_state_file "$file_path" "$updated" \
    "approval: REJECTED ${APPROVAL_ID} by ${APPROVED_BY} — ${REASON}"; then
    log_success "Approval '${APPROVAL_ID}' REJECTED by ${APPROVED_BY}"
    echo "$updated" | jq .
  else
    log_error "Failed to reject"
    exit 1
  fi
}

# List all approvals for a workspace in table format
do_list() {
  log_info "=== Approvals for ${WORKSPACE_ID} ==="
  echo ""

  local files
  files=$(list_approval_files)

  if [ -z "$files" ]; then
    log_info "No approval records found"
    exit 0
  fi

  printf "%-25s %-12s %-12s %-10s %-20s %-15s\n" \
    "APPROVAL ID" "COMPONENT" "VERSION" "STATUS" "REQUESTED AT" "APPROVED BY"
  printf "%-25s %-12s %-12s %-10s %-20s %-15s\n" \
    "---" "---" "---" "---" "---" "---"

  while IFS= read -r filename; do
    [ -z "$filename" ] && continue

    local file_path="${APPROVALS_PATH}/${filename}"
    local content
    content=$(read_state_content "$file_path")

    if [ -z "$content" ]; then
      continue
    fi

    local id comp ver status requested_at approved_by
    id=$(echo "$content" | jq -r '.approvalId // "?"' 2>/dev/null)
    comp=$(echo "$content" | jq -r '.component // "?"' 2>/dev/null)
    ver=$(echo "$content" | jq -r '.version // "?"' 2>/dev/null)
    status=$(echo "$content" | jq -r '.status // "?"' 2>/dev/null)
    requested_at=$(echo "$content" | jq -r '.requestedAt // .approvedAt // "?"' 2>/dev/null)
    approved_by=$(echo "$content" | jq -r '.approvedBy // "?"' 2>/dev/null)

    # Detect expired pending approvals
    if [ "$status" = "pending" ]; then
      local expires_at
      expires_at=$(echo "$content" | jq -r '.expiresAt // ""' 2>/dev/null)
      if [ -n "$expires_at" ] && [ "$expires_at" != "null" ]; then
        local now_epoch exp_epoch
        now_epoch=$(date +%s)
        exp_epoch=$(date -d "$expires_at" +%s 2>/dev/null || echo "0")
        if [ "$exp_epoch" -gt 0 ] && [ "$now_epoch" -gt "$exp_epoch" ]; then
          status="expired"
        fi
      fi
    fi

    printf "%-25s %-12s %-12s %-10s %-20s %-15s\n" \
      "$id" "$comp" "$ver" "$status" "$requested_at" "$approved_by"
  done <<< "$files"

  echo ""
}

# Clean up expired and old resolved approvals
# Removes: expired pending requests, resolved approvals older than 7 days
do_cleanup() {
  log_info "Cleaning up expired approvals for ${WORKSPACE_ID}..."

  local files
  files=$(list_approval_files)

  if [ -z "$files" ]; then
    log_info "No approval files found"
    exit 0
  fi

  local cleaned=0
  local total=0

  while IFS= read -r filename; do
    [ -z "$filename" ] && continue
    total=$((total + 1))

    local file_path="${APPROVALS_PATH}/${filename}"
    local content
    content=$(read_state_content "$file_path")

    if [ -z "$content" ]; then
      continue
    fi

    local status expires_at
    status=$(echo "$content" | jq -r '.status // ""' 2>/dev/null)
    expires_at=$(echo "$content" | jq -r '.expiresAt // ""' 2>/dev/null)

    local should_clean=false

    # Clean up expired pending requests
    if [ "$status" = "pending" ] && [ -n "$expires_at" ] && [ "$expires_at" != "null" ]; then
      local now_epoch exp_epoch
      now_epoch=$(date +%s)
      exp_epoch=$(date -d "$expires_at" +%s 2>/dev/null || echo "0")
      if [ "$exp_epoch" -gt 0 ] && [ "$now_epoch" -gt "$exp_epoch" ]; then
        should_clean=true
      fi
    fi

    # Clean up resolved approvals older than 7 days
    if [ "$status" = "approved" ] || [ "$status" = "rejected" ] || [ "$status" = "expired" ]; then
      local approved_at
      approved_at=$(echo "$content" | jq -r '.approvedAt // ""' 2>/dev/null)
      if [ -n "$approved_at" ]; then
        local now_epoch appr_epoch age_days
        now_epoch=$(date +%s)
        appr_epoch=$(date -d "$approved_at" +%s 2>/dev/null || echo "0")
        age_days=$(( (now_epoch - appr_epoch) / 86400 ))
        if [ "$age_days" -gt 7 ]; then
          should_clean=true
        fi
      fi
    fi

    if [ "$should_clean" = "true" ]; then
      local file_sha
      file_sha=$(get_file_sha "$file_path")

      if [ -n "$file_sha" ]; then
        local approval_id
        approval_id=$(echo "$content" | jq -r '.approvalId // "unknown"' 2>/dev/null)

        if delete_state_file "$file_path" "$file_sha" \
          "approval-cleanup: remove ${approval_id} (status: ${status})"; then
          log_success "Cleaned: ${approval_id} (status: ${status})"
          cleaned=$((cleaned + 1))
        else
          log_error "Failed to clean: ${filename}"
        fi
      fi
    fi
  done <<< "$files"

  echo ""
  log_success "Cleanup complete: ${cleaned}/${total} approvals removed"
}

# ── Main ─────────────────────────────────────────────────────────────────────
main() {
  check_prerequisites

  case "$ACTION" in
    request)  do_request ;;
    check)    do_check ;;
    approve)  do_approve ;;
    reject)   do_reject ;;
    list)     do_list ;;
    cleanup)  do_cleanup ;;
    *)
      echo "ERROR: Unknown action '${ACTION}'"
      echo "Valid actions: request, check, approve, reject, list, cleanup"
      exit 1
      ;;
  esac
}

main
