#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# bootstrap.sh — Replaces: bootstrap.yml (GitHub Actions workflow)
#
# Full bootstrap of the autopilot state infrastructure. Creates the
# autopilot-state and autopilot-backups branches if they don't exist,
# initializes the root state directory structure, and seeds the first
# workspace (ws-default).
#
# This is the equivalent of running bootstrap.yml which sets up the entire
# state management infrastructure from scratch. Should only be run once
# during initial setup, or to recover from a complete state loss.
#
# MCP Tool Calls:
#   - mcp__github__list_branches: Check if branches exist
#   - mcp__github__create_branch: Create state/backups branches
#   - mcp__github__create_or_update_file: Initialize root state files
#   - (delegates to seed-workspace.sh for ws-default creation)
#
# Usage:
#   ./bootstrap.sh                         # Full bootstrap
#   ./bootstrap.sh --skip-seed             # Bootstrap branches only, no workspace
#   ./bootstrap.sh --workspace <ws_id>     # Bootstrap + seed a specific workspace
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
BACKUP_BRANCH="autopilot-backups"
DEFAULT_BASE_BRANCH="main"

# Load from config if available
if [ -f "$CONFIG_FILE" ]; then
  REPO_OWNER=$(jq -r '.autopilotRepo.owner // "lucassfreiree"' "$CONFIG_FILE" 2>/dev/null || echo "lucassfreiree")
  REPO_NAME=$(jq -r '.autopilotRepo.repo // "autopilot"' "$CONFIG_FILE" 2>/dev/null || echo "autopilot")
fi

# ── Arguments ────────────────────────────────────────────────────────────────
SKIP_SEED=false
SEED_WORKSPACE="ws-default"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-seed)    SKIP_SEED=true; shift ;;
    --workspace)    SEED_WORKSPACE="$2"; shift 2 ;;
    *)              echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ── Functions ────────────────────────────────────────────────────────────────

log_info()    { echo "[INFO] $(date -u +"%Y-%m-%dT%H:%M:%SZ") $*"; }
log_error()   { echo "[ERROR] $(date -u +"%Y-%m-%dT%H:%M:%SZ") $*" >&2; }
log_success() { echo "[OK] $(date -u +"%Y-%m-%dT%H:%M:%SZ") $*"; }
log_warn()    { echo "[WARN] $(date -u +"%Y-%m-%dT%H:%M:%SZ") $*"; }

check_prerequisites() {
  if [ -z "${GITHUB_TOKEN:-}" ]; then
    log_error "GITHUB_TOKEN is not set. Cannot access GitHub API."
    exit 1
  fi

  if ! command -v jq &>/dev/null; then
    log_error "jq is required but not installed."
    exit 1
  fi
}

# Check if a branch exists in the repository
# Args: $1 = branch name
# Returns: 0 if exists, 1 if not
branch_exists() {
  local branch_name="$1"

  # MCP equivalent: mcp__github__list_branches
  #   owner: lucassfreiree
  #   repo: autopilot
  # Then check if branch_name is in the list

  local status_code
  status_code=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/branches/${branch_name}")

  [ "$status_code" = "200" ]
}

# Get the SHA of the latest commit on a branch
# Args: $1 = branch name
get_branch_sha() {
  local branch_name="$1"

  curl -sS -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/git/ref/heads/${branch_name}" \
    | jq -r '.object.sha // empty' 2>/dev/null
}

# Create a new branch from a base branch
# Args: $1 = new branch name, $2 = base branch name
# MCP equivalent: mcp__github__create_branch
#   owner: lucassfreiree
#   repo: autopilot
#   branch: $1
#   from_branch: $2
create_branch() {
  local new_branch="$1"
  local base_branch="$2"

  log_info "Creating branch '${new_branch}' from '${base_branch}'..."

  local base_sha
  base_sha=$(get_branch_sha "$base_branch")

  if [ -z "$base_sha" ]; then
    log_error "Could not get SHA for base branch '${base_branch}'"
    return 1
  fi

  local payload
  payload=$(jq -n \
    --arg ref "refs/heads/${new_branch}" \
    --arg sha "$base_sha" \
    '{ ref: $ref, sha: $sha }')

  local response
  response=$(curl -sS -X POST \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    -d "$payload" \
    "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/git/refs")

  local created_ref
  created_ref=$(echo "$response" | jq -r '.ref // empty' 2>/dev/null)

  if [ -n "$created_ref" ]; then
    log_success "Branch '${new_branch}' created (ref: ${created_ref})"
    return 0
  else
    local error_msg
    error_msg=$(echo "$response" | jq -r '.message // "Unknown error"' 2>/dev/null)
    log_error "Failed to create branch '${new_branch}': ${error_msg}"
    return 1
  fi
}

# Write a file to a branch via GitHub API
# Args: $1 = file path, $2 = content (plain text), $3 = branch, $4 = commit message
# MCP equivalent: mcp__github__create_or_update_file
write_file_to_branch() {
  local file_path="$1"
  local content="$2"
  local branch="$3"
  local commit_message="$4"

  local content_b64
  content_b64=$(echo "$content" | base64 -w 0)

  local api_url="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/${file_path}"

  # Check if file already exists (need SHA for update)
  local existing_sha=""
  existing_sha=$(curl -sS -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    "${api_url}?ref=${branch}" 2>/dev/null | jq -r '.sha // empty' 2>/dev/null || echo "")

  local payload
  if [ -n "$existing_sha" ]; then
    payload=$(jq -n \
      --arg message "$commit_message" \
      --arg content "$content_b64" \
      --arg branch "$branch" \
      --arg sha "$existing_sha" \
      '{ message: $message, content: $content, branch: $branch, sha: $sha }')
  else
    payload=$(jq -n \
      --arg message "$commit_message" \
      --arg content "$content_b64" \
      --arg branch "$branch" \
      '{ message: $message, content: $content, branch: $branch }')
  fi

  local result
  result=$(curl -sS -X PUT \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    -d "$payload" \
    "$api_url" | jq -r '.content.path // "FAILED"' 2>/dev/null)

  if [ "$result" = "FAILED" ]; then
    log_error "Failed to write ${file_path} to ${branch}"
    return 1
  fi
  log_success "Written: ${file_path} -> ${branch}"
}

# Initialize the root state structure on the state branch
# Creates: state/README.md, state/workspaces/.gitkeep
init_state_structure() {
  log_info "Initializing root state structure on '${STATE_BRANCH}'..."

  # Create state/README.md
  local readme_content
  readme_content=$(cat <<'HEREDOC'
# Autopilot State Branch

This branch contains runtime state for the autopilot CI/CD control plane.

## Structure

```
state/
  workspaces/
    {workspace_id}/
      workspace.json              # Workspace configuration
      health.json                 # Health check results
      release-freeze.json         # Release freeze state
      controller-release-state.json
      agent-release-state.json
      locks/                      # Session and operation locks
        session-lock.json
      audit/                      # Immutable audit trail
      handoffs/                   # Agent handoff queue
      improvements/               # Improvement records
      metrics/                    # Daily metrics snapshots
      approvals/                  # Release approval records
```

## Rules

- Never modify this branch directly — use workflows or MCP tools
- All mutations must write an audit entry
- Locks must be acquired before writing release state
- State is the source of truth, not agent memory
HEREDOC
)

  write_file_to_branch "state/README.md" "$readme_content" "$STATE_BRANCH" \
    "bootstrap: initialize state structure"

  # Create a .gitkeep in the workspaces directory to ensure it exists
  write_file_to_branch "state/workspaces/.gitkeep" "" "$STATE_BRANCH" \
    "bootstrap: create workspaces directory"

  log_success "Root state structure initialized"
}

# Initialize the backup branch with a README
init_backup_structure() {
  log_info "Initializing backup structure on '${BACKUP_BRANCH}'..."

  local readme_content
  readme_content=$(cat <<'HEREDOC'
# Autopilot Backups Branch

This branch contains timestamped snapshots of the autopilot-state branch.

## Structure

```
backup-{YYYY-MM-DD-HHmmss}/
  manifest.json               # Backup metadata (timestamp, file count, status)
  state/                      # Complete copy of state/ at snapshot time
    workspaces/
      ...
```

## Restore

To restore a backup, use:
```bash
./operations/restore-state.sh list              # List available backups
./operations/restore-state.sh restore <name>    # Restore a specific backup
```
HEREDOC
)

  write_file_to_branch "README.md" "$readme_content" "$BACKUP_BRANCH" \
    "bootstrap: initialize backup branch"

  log_success "Backup structure initialized"
}

# ── Main ─────────────────────────────────────────────────────────────────────
main() {
  log_info "=== Autopilot Bootstrap ==="
  log_info "Repository: ${REPO_OWNER}/${REPO_NAME}"
  log_info "State branch: ${STATE_BRANCH}"
  log_info "Backup branch: ${BACKUP_BRANCH}"
  echo ""

  check_prerequisites

  # Step 1: Create autopilot-state branch if it doesn't exist
  if branch_exists "$STATE_BRANCH"; then
    log_success "State branch '${STATE_BRANCH}' already exists"
  else
    log_info "State branch '${STATE_BRANCH}' does not exist, creating..."
    create_branch "$STATE_BRANCH" "$DEFAULT_BASE_BRANCH" || {
      log_error "Failed to create state branch. Aborting."
      exit 1
    }
  fi

  # Step 2: Create autopilot-backups branch if it doesn't exist
  if branch_exists "$BACKUP_BRANCH"; then
    log_success "Backup branch '${BACKUP_BRANCH}' already exists"
  else
    log_info "Backup branch '${BACKUP_BRANCH}' does not exist, creating..."
    create_branch "$BACKUP_BRANCH" "$DEFAULT_BASE_BRANCH" || {
      log_error "Failed to create backup branch. Aborting."
      exit 1
    }
  fi

  # Step 3: Initialize root state structure
  init_state_structure

  # Step 4: Initialize backup branch structure
  init_backup_structure

  # Step 5: Seed the first workspace (unless --skip-seed)
  if [ "$SKIP_SEED" = "true" ]; then
    log_info "Skipping workspace seed (--skip-seed flag)"
  else
    log_info "Seeding workspace '${SEED_WORKSPACE}'..."
    local seed_script="${SCRIPT_DIR}/seed-workspace.sh"
    if [ -x "$seed_script" ]; then
      "$seed_script" --workspace "$SEED_WORKSPACE"
    else
      log_warn "seed-workspace.sh not found or not executable at ${seed_script}"
      log_warn "Run manually: ./operations/seed-workspace.sh --workspace ${SEED_WORKSPACE}"
    fi
  fi

  echo ""
  log_success "=== Bootstrap Complete ==="
  log_success "State branch:  ${STATE_BRANCH}"
  log_success "Backup branch: ${BACKUP_BRANCH}"
  log_success "Seed workspace: ${SEED_WORKSPACE}"
}

main "$@"
