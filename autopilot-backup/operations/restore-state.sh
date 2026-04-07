#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# restore-state.sh — Replaces: restore-state.yml (GitHub Actions workflow)
#
# Lists available backups from the autopilot-backups branch and restores a
# selected backup to the autopilot-state branch. Validates restored state
# by checking required files and JSON integrity.
#
# MCP Tool Calls:
#   - get_file_contents: List backup directories on autopilot-backups
#   - get_file_contents: Read each file from selected backup
#   - create_or_update_file: Write each file to autopilot-state
#   - get_file_contents: Re-read restored files for validation
#
# Usage:
#   ./restore-state.sh                    # Interactive: list backups, select one
#   ./restore-state.sh list               # List available backups only
#   ./restore-state.sh restore <name>     # Restore a specific backup
#   ./restore-state.sh validate           # Validate current state branch
#
# Environment:
#   GITHUB_TOKEN — GitHub PAT with repo access (required)
###############################################################################

# ── Source core utilities ────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="${SCRIPT_DIR}/../core"

for core_script in "${CORE_DIR}"/*.sh; do
  [ -f "$core_script" ] && source "$core_script" 2>/dev/null || true
done

# ── Constants ────────────────────────────────────────────────────────────────
REPO_OWNER="lucassfreiree"
REPO_NAME="autopilot"
STATE_BRANCH="autopilot-state"
BACKUP_BRANCH="autopilot-backups"

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

# List all backup directories on the backups branch
# Backups are top-level directories named backup-{YYYY-MM-DD-HHmmss}
list_backups() {
  local api_url="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/git/trees/${BACKUP_BRANCH}"

  local response
  response=$(curl -sS -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    "${api_url}")

  # Extract top-level directories matching backup-* pattern
  echo "${response}" | jq -r '.tree[] | select(.type == "tree") | select(.path | startswith("backup-")) | .path' 2>/dev/null | sort -r
}

# Read manifest for a specific backup
# Args: $1 = backup name
read_manifest() {
  local backup_name="$1"
  local api_url="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/${backup_name}/manifest.json?ref=${BACKUP_BRANCH}"

  local response
  response=$(curl -sS -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    "${api_url}")

  echo "${response}" | jq -r '.content // empty' 2>/dev/null | base64 -d 2>/dev/null || echo "{}"
}

# List all files within a specific backup directory
# Args: $1 = backup name
list_backup_files() {
  local backup_name="$1"
  local api_url="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/git/trees/${BACKUP_BRANCH}?recursive=1"

  local response
  response=$(curl -sS -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    "${api_url}")

  # Filter files under the backup directory, exclude manifest
  echo "${response}" | jq -r --arg prefix "${backup_name}/" \
    '.tree[] | select(.type == "blob") | select(.path | startswith($prefix)) | select(.path | endswith("manifest.json") | not) | .path' 2>/dev/null
}

# Read a file from the backup branch
# Args: $1 = full path on backup branch
read_backup_file() {
  local file_path="$1"
  local api_url="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/${file_path}?ref=${BACKUP_BRANCH}"

  curl -sS -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    "${api_url}"
}

# Write a file to the state branch
# Args: $1 = target path on state branch, $2 = base64 content, $3 = commit message
write_state_file() {
  local target_path="$1"
  local content_b64="$2"
  local commit_message="$3"

  local api_url="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/${target_path}"

  # Check if file already exists on state branch (need SHA for update)
  local existing_sha=""
  existing_sha=$(curl -sS -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    "${api_url}?ref=${STATE_BRANCH}" 2>/dev/null | jq -r '.sha // empty' 2>/dev/null || echo "")

  local payload
  if [ -n "${existing_sha}" ]; then
    payload=$(jq -n \
      --arg message "${commit_message}" \
      --arg content "${content_b64}" \
      --arg branch "${STATE_BRANCH}" \
      --arg sha "${existing_sha}" \
      '{ message: $message, content: $content, branch: $branch, sha: $sha }')
  else
    payload=$(jq -n \
      --arg message "${commit_message}" \
      --arg content "${content_b64}" \
      --arg branch "${STATE_BRANCH}" \
      '{ message: $message, content: $content, branch: $branch }')
  fi

  curl -sS -X PUT \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    -d "${payload}" \
    "${api_url}" | jq -r '.content.path // "FAILED"' 2>/dev/null
}

# Validate restored state by checking critical files exist and contain valid JSON
validate_state() {
  log_info "Validating restored state on '${STATE_BRANCH}'..."

  local api_url="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/git/trees/${STATE_BRANCH}?recursive=1"
  local tree
  tree=$(curl -sS -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    "${api_url}")

  local all_files
  all_files=$(echo "${tree}" | jq -r '.tree[] | select(.type == "blob") | .path' 2>/dev/null)

  local errors=0

  # Check that at least one workspace exists
  local workspace_count
  workspace_count=$(echo "${all_files}" | grep -c "state/workspaces/.*/workspace.json" 2>/dev/null || echo "0")

  if [ "${workspace_count}" -eq 0 ]; then
    log_error "No workspace.json files found on state branch"
    errors=$((errors + 1))
  else
    log_success "Found ${workspace_count} workspace(s)"
  fi

  # Validate each workspace has required files
  local workspaces
  workspaces=$(echo "${all_files}" | grep -oP 'state/workspaces/\K[^/]+' 2>/dev/null | sort -u || echo "")

  while IFS= read -r ws_id; do
    [ -z "${ws_id}" ] && continue
    local ws_prefix="state/workspaces/${ws_id}"

    # Required files per workspace
    local required_files=("workspace.json" "health.json" "release-freeze.json")
    for req_file in "${required_files[@]}"; do
      if echo "${all_files}" | grep -q "^${ws_prefix}/${req_file}$"; then
        log_success "  ${ws_id}: ${req_file} present"
      else
        log_warn "  ${ws_id}: ${req_file} MISSING"
      fi
    done

    # Validate workspace.json is valid JSON
    local ws_content
    ws_content=$(curl -sS -H "Authorization: token ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github.v3+json" \
      "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/${ws_prefix}/workspace.json?ref=${STATE_BRANCH}" \
      | jq -r '.content // empty' 2>/dev/null | base64 -d 2>/dev/null || echo "")

    if echo "${ws_content}" | jq . >/dev/null 2>&1; then
      log_success "  ${ws_id}: workspace.json is valid JSON"
    else
      log_error "  ${ws_id}: workspace.json is INVALID JSON"
      errors=$((errors + 1))
    fi
  done <<< "${workspaces}"

  if [ "${errors}" -gt 0 ]; then
    log_error "Validation completed with ${errors} error(s)"
    return 1
  else
    log_success "Validation passed — state is consistent"
    return 0
  fi
}

# Restore a specific backup to the state branch
# Args: $1 = backup name
do_restore() {
  local backup_name="$1"

  log_info "=== Restoring backup: ${backup_name} ==="

  # Read and display manifest
  local manifest
  manifest=$(read_manifest "${backup_name}")
  log_info "Manifest: $(echo "${manifest}" | jq -c '.' 2>/dev/null || echo 'N/A')"

  # List files in the backup
  local files
  files=$(list_backup_files "${backup_name}")

  if [ -z "${files}" ]; then
    log_error "No files found in backup '${backup_name}'"
    exit 1
  fi

  local file_count=0
  local failed_count=0

  while IFS= read -r backup_path; do
    [ -z "${backup_path}" ] && continue

    # Strip the backup prefix to get the original state path
    local state_path="${backup_path#${backup_name}/}"

    log_info "Restoring: ${state_path}"

    # Read file from backup branch
    local file_data
    file_data=$(read_backup_file "${backup_path}")

    local content_b64
    content_b64=$(echo "${file_data}" | jq -r '.content // empty' 2>/dev/null | tr -d '\n')

    if [ -z "${content_b64}" ]; then
      log_error "Failed to read backup file: ${backup_path}"
      failed_count=$((failed_count + 1))
      continue
    fi

    # Write to state branch at the original path
    local result
    result=$(write_state_file "${state_path}" "${content_b64}" \
      "restore: from ${backup_name} — ${state_path}")

    if [ "${result}" = "FAILED" ]; then
      log_error "Failed to restore: ${state_path}"
      failed_count=$((failed_count + 1))
    else
      file_count=$((file_count + 1))
    fi
  done <<< "${files}"

  echo ""
  log_success "=== Restore Complete ==="
  log_success "Backup:         ${backup_name}"
  log_success "Files restored: ${file_count}"
  if [ "${failed_count}" -gt 0 ]; then
    log_error "Files failed:   ${failed_count}"
  fi

  # Validate the restored state
  echo ""
  validate_state
}

# Display available backups with metadata
do_list() {
  log_info "=== Available Backups on '${BACKUP_BRANCH}' ==="

  local backups
  backups=$(list_backups)

  if [ -z "${backups}" ]; then
    log_warn "No backups found on '${BACKUP_BRANCH}' branch"
    exit 0
  fi

  echo ""
  printf "%-35s %-25s %-10s %-8s\n" "BACKUP NAME" "CREATED AT" "STATUS" "FILES"
  printf "%-35s %-25s %-10s %-8s\n" "---" "---" "---" "---"

  while IFS= read -r backup_name; do
    [ -z "${backup_name}" ] && continue

    local manifest
    manifest=$(read_manifest "${backup_name}")

    local created_at
    created_at=$(echo "${manifest}" | jq -r '.createdAt // "unknown"' 2>/dev/null)
    local status
    status=$(echo "${manifest}" | jq -r '.status // "unknown"' 2>/dev/null)
    local file_count
    file_count=$(echo "${manifest}" | jq -r '.fileCount // "?"' 2>/dev/null)

    printf "%-35s %-25s %-10s %-8s\n" "${backup_name}" "${created_at}" "${status}" "${file_count}"
  done <<< "${backups}"
  echo ""
}

# ── Main ─────────────────────────────────────────────────────────────────────
main() {
  check_prerequisites

  local action="${1:-interactive}"
  shift || true

  case "${action}" in
    list)
      do_list
      ;;
    restore)
      local backup_name="${1:-}"
      if [ -z "${backup_name}" ]; then
        log_error "Usage: $0 restore <backup-name>"
        log_error "Run '$0 list' to see available backups"
        exit 1
      fi
      do_restore "${backup_name}"
      ;;
    validate)
      validate_state
      ;;
    interactive)
      do_list
      echo "To restore a backup, run:"
      echo "  $0 restore <backup-name>"
      ;;
    *)
      echo "Usage: $0 {list|restore <name>|validate}"
      exit 1
      ;;
  esac
}

main "$@"
