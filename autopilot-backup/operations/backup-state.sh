#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# backup-state.sh — Replaces: backup-state.yml (GitHub Actions workflow)
#
# Creates a timestamped snapshot of the entire autopilot-state branch content
# on the autopilot-backups branch. Each backup is stored under a directory
# named backup-{YYYY-MM-DD-HHmmss}/ to enable point-in-time restore.
#
# MCP Tool Calls:
#   - get_file_contents: Read state branch tree listing
#   - get_file_contents: Read each file from autopilot-state
#   - create_or_update_file: Write each file to autopilot-backups under
#                            backup-{timestamp}/ prefix
#
# Usage:
#   ./backup-state.sh
#
# Environment:
#   GITHUB_TOKEN — GitHub PAT with repo access (required)
###############################################################################

# ── Source core utilities ────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="${SCRIPT_DIR}/../core"

# Source core scripts if they exist (logging, GitHub API helpers, etc.)
for core_script in "${CORE_DIR}"/*.sh; do
  [ -f "$core_script" ] && source "$core_script" 2>/dev/null || true
done

# ── Constants ────────────────────────────────────────────────────────────────
REPO_OWNER="lucassfreiree"
REPO_NAME="autopilot"
STATE_BRANCH="autopilot-state"
BACKUP_BRANCH="autopilot-backups"
STATE_ROOT="state/workspaces"

# ── Functions ────────────────────────────────────────────────────────────────

log_info() {
  echo "[INFO] $(date -u +"%Y-%m-%dT%H:%M:%SZ") $*"
}

log_error() {
  echo "[ERROR] $(date -u +"%Y-%m-%dT%H:%M:%SZ") $*" >&2
}

log_success() {
  echo "[OK] $(date -u +"%Y-%m-%dT%H:%M:%SZ") $*"
}

# Generate a timestamp-based backup directory name
generate_backup_name() {
  echo "backup-$(date -u +"%Y-%m-%d-%H%M%S")"
}

# Verify required environment variables
check_prerequisites() {
  if [ -z "${GITHUB_TOKEN:-}" ]; then
    log_error "GITHUB_TOKEN is not set. Cannot access GitHub API."
    exit 1
  fi
}

# List all files on the state branch recursively using GitHub API
# Uses: GET /repos/{owner}/{repo}/git/trees/{branch}?recursive=1
list_state_files() {
  local api_url="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/git/trees/${STATE_BRANCH}?recursive=1"

  log_info "Listing all files on branch '${STATE_BRANCH}'..."

  local response
  response=$(curl -sS -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    "${api_url}")

  # Extract file paths (blobs only, not trees)
  echo "${response}" | jq -r '.tree[] | select(.type == "blob") | .path' 2>/dev/null
}

# Read a single file from the state branch via GitHub API
# Uses MCP equivalent: get_file_contents
# Args: $1 = file path on state branch
read_state_file() {
  local file_path="$1"
  local api_url="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/${file_path}?ref=${STATE_BRANCH}"

  curl -sS -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    "${api_url}"
}

# Write a file to the backup branch via GitHub API
# Uses MCP equivalent: create_or_update_file
# Args: $1 = target path, $2 = base64 content, $3 = commit message
write_backup_file() {
  local target_path="$1"
  local content_b64="$2"
  local commit_message="$3"

  local api_url="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/${target_path}"

  # Check if file already exists on backup branch (to get SHA for update)
  local existing_sha=""
  existing_sha=$(curl -sS -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    "${api_url}?ref=${BACKUP_BRANCH}" 2>/dev/null | jq -r '.sha // empty' 2>/dev/null || echo "")

  local payload
  if [ -n "${existing_sha}" ]; then
    payload=$(jq -n \
      --arg message "${commit_message}" \
      --arg content "${content_b64}" \
      --arg branch "${BACKUP_BRANCH}" \
      --arg sha "${existing_sha}" \
      '{ message: $message, content: $content, branch: $branch, sha: $sha }')
  else
    payload=$(jq -n \
      --arg message "${commit_message}" \
      --arg content "${content_b64}" \
      --arg branch "${BACKUP_BRANCH}" \
      '{ message: $message, content: $content, branch: $branch }')
  fi

  curl -sS -X PUT \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    -d "${payload}" \
    "${api_url}" | jq -r '.content.path // "FAILED"' 2>/dev/null
}

# Create a backup manifest file with metadata
# Args: $1 = backup name, $2 = file count, $3 = start time
create_manifest() {
  local backup_name="$1"
  local file_count="$2"
  local start_time="$3"
  local end_time
  end_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local manifest
  manifest=$(jq -n \
    --arg name "${backup_name}" \
    --arg source "${STATE_BRANCH}" \
    --arg created "${end_time}" \
    --arg started "${start_time}" \
    --argjson count "${file_count}" \
    --arg repo "${REPO_OWNER}/${REPO_NAME}" \
    '{
      backupName: $name,
      sourceBranch: $source,
      createdAt: $created,
      startedAt: $started,
      fileCount: $count,
      repository: $repo,
      status: "complete"
    }')

  local manifest_b64
  manifest_b64=$(echo "${manifest}" | base64 -w 0)

  write_backup_file "${backup_name}/manifest.json" "${manifest_b64}" \
    "backup: add manifest for ${backup_name}"
}

# ── Main ─────────────────────────────────────────────────────────────────────
main() {
  local start_time
  start_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  log_info "=== Autopilot State Backup ==="
  log_info "Source: ${STATE_BRANCH} | Target: ${BACKUP_BRANCH}"

  check_prerequisites

  # Generate backup directory name
  local backup_name
  backup_name=$(generate_backup_name)
  log_info "Backup name: ${backup_name}"

  # List all files on the state branch
  local files
  files=$(list_state_files)

  if [ -z "${files}" ]; then
    log_error "No files found on '${STATE_BRANCH}' branch. Nothing to back up."
    exit 1
  fi

  local file_count=0
  local failed_count=0

  # Iterate over each file and copy it to the backup branch
  while IFS= read -r file_path; do
    [ -z "${file_path}" ] && continue

    log_info "Backing up: ${file_path}"

    # Read file content from state branch (returns base64 via GitHub API)
    local file_data
    file_data=$(read_state_file "${file_path}")

    local content_b64
    content_b64=$(echo "${file_data}" | jq -r '.content // empty' 2>/dev/null | tr -d '\n')

    if [ -z "${content_b64}" ]; then
      log_error "Failed to read: ${file_path} (empty content)"
      failed_count=$((failed_count + 1))
      continue
    fi

    # Write to backup branch under backup-{timestamp}/ prefix
    local target_path="${backup_name}/${file_path}"
    local result
    result=$(write_backup_file "${target_path}" "${content_b64}" \
      "backup: ${backup_name} - ${file_path}")

    if [ "${result}" = "FAILED" ]; then
      log_error "Failed to write: ${target_path}"
      failed_count=$((failed_count + 1))
    else
      file_count=$((file_count + 1))
    fi
  done <<< "${files}"

  # Create backup manifest
  log_info "Creating backup manifest..."
  create_manifest "${backup_name}" "${file_count}" "${start_time}"

  # Summary
  echo ""
  log_success "=== Backup Complete ==="
  log_success "Backup name:   ${backup_name}"
  log_success "Files backed:  ${file_count}"
  if [ "${failed_count}" -gt 0 ]; then
    log_error "Files failed:  ${failed_count}"
  fi
  log_success "Branch:        ${BACKUP_BRANCH}"
  log_success "Timestamp:     ${start_time}"
}

main "$@"
