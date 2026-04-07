#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# apply-source-change.sh
# Replaces: .github/workflows/apply-source-change.yml
#
# Applies source code changes to corporate repos via GitHub API / MCP tools.
# Takes file changes as input (path + content pairs) and pushes them.
#
# Commit identity: github-actions / github-actions@github.com
#
# Usage:
#   # Single file change (target_path:local_source_path)
#   ./apply-source-change.sh --repo bbvinet/psc-sre-automacao-agent \
#     --file "package.json:patches/package.json" \
#     --message "chore: bump version to 2.3.4"
#
#   # Multiple file changes
#   ./apply-source-change.sh --repo bbvinet/psc-sre-automacao-agent \
#     --file "package.json:patches/package.json" \
#     --file "src/swagger/swagger.json:patches/swagger.json" \
#     --message "feat: add new endpoint" \
#     --version "2.3.4"
#
#   # With inline content (base64-encoded)
#   ./apply-source-change.sh --repo bbvinet/psc-sre-automacao-agent \
#     --inline "package.json:eyJ2ZXJzaW9uIjoiMS4wLjAifQ==" \
#     --message "chore: update"
#
# Options:
#   --workspace <ws_id>       Workspace ID (default: ws-default)
#   --repo <owner/repo>       Target corporate repo (required)
#   --branch <branch>         Target branch (default: main)
#   --file <target:source>    File change: target_path:local_source_path (repeatable)
#   --inline <path:b64>       Inline content: target_path:base64_content (repeatable)
#   --message <msg>           Commit message (required)
#   --version <version>       Version being deployed (for audit)
#   --component <name>        Component name: agent|controller (for audit)
#   --dry-run                 Show what would be done without pushing
#
# MCP tools used:
#   - mcp__github__get_file_contents   (read current file SHA for updates)
#   - mcp__github__create_or_update_file (push each file change)
#   - mcp__github__push_files          (batch push multiple files in one commit)
#
# Workflow equivalent stages:
#   Stage 2 (Apply & Push) of apply-source-change.yml
#   - Reads current file SHAs from target repo
#   - Pushes updated content with commit message
#   - Identity: github-actions / github-actions@github.com
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source core modules
source "${SCRIPT_DIR}/../core/state-manager.sh"

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
WORKSPACE_ID="${WORKSPACE_ID:-ws-default}"
REPO=""
BRANCH="main"
COMMIT_MESSAGE=""
VERSION=""
COMPONENT=""
DRY_RUN=false

# File changes: arrays of target_path and source (local file or base64)
declare -a CHANGE_TARGETS=()
declare -a CHANGE_SOURCES=()
declare -a CHANGE_TYPES=()   # "file" or "inline"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace)  WORKSPACE_ID="$2"; shift 2 ;;
    --repo)       REPO="$2"; shift 2 ;;
    --branch)     BRANCH="$2"; shift 2 ;;
    --file)
      local_pair="$2"
      CHANGE_TARGETS+=("${local_pair%%:*}")
      CHANGE_SOURCES+=("${local_pair#*:}")
      CHANGE_TYPES+=("file")
      shift 2
      ;;
    --inline)
      local_pair="$2"
      CHANGE_TARGETS+=("${local_pair%%:*}")
      CHANGE_SOURCES+=("${local_pair#*:}")
      CHANGE_TYPES+=("inline")
      shift 2
      ;;
    --message)    COMMIT_MESSAGE="$2"; shift 2 ;;
    --version)    VERSION="$2"; shift 2 ;;
    --component)  COMPONENT="$2"; shift 2 ;;
    --dry-run)    DRY_RUN=true; shift ;;
    *) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
  esac
done

# Validate
if [[ -z "$REPO" ]]; then
  echo "ERROR: --repo is required" >&2
  exit 1
fi
if [[ ${#CHANGE_TARGETS[@]} -eq 0 ]]; then
  echo "ERROR: At least one --file or --inline change is required" >&2
  exit 1
fi
if [[ -z "$COMMIT_MESSAGE" ]]; then
  echo "ERROR: --message is required" >&2
  exit 1
fi

OWNER=$(echo "$REPO" | cut -d/ -f1)
REPO_NAME=$(echo "$REPO" | cut -d/ -f2)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Write audit entry
# MCP: mcp__github__create_or_update_file(
#   path="state/workspaces/{ws_id}/audit/apply-source-change-{timestamp}.json")
write_audit_entry() {
  local action="$1"
  local detail="$2"
  local status="$3"
  local filename="apply-source-change-$(date -u +%Y%m%d-%H%M%S).json"

  local audit_json
  audit_json=$(jq -n \
    --arg action "$action" \
    --arg component "${COMPONENT:-unknown}" \
    --arg workspaceId "$WORKSPACE_ID" \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg detail "$detail" \
    --arg status "$status" \
    --arg agent "claude-code" \
    --arg repo "$REPO" \
    --arg version "${VERSION:-}" \
    --arg commitMessage "$COMMIT_MESSAGE" \
    '{action: $action, component: $component, workspaceId: $workspaceId,
      timestamp: $timestamp, detail: $detail, status: $status, agent: $agent,
      repo: $repo, version: $version, commitMessage: $commitMessage}')

  write_state "$WORKSPACE_ID" "audit/${filename}" "$audit_json" \
    "audit: ${action} for ${WORKSPACE_ID}" 2>/dev/null || \
    echo "WARN: Failed to write audit entry" >&2
}

# Get the content for a change (read from file or decode base64)
get_change_content() {
  local index="$1"
  local source="${CHANGE_SOURCES[$index]}"
  local type="${CHANGE_TYPES[$index]}"

  if [[ "$type" == "inline" ]]; then
    echo "$source" | base64 -d 2>/dev/null || {
      echo "ERROR: Failed to decode inline content for ${CHANGE_TARGETS[$index]}" >&2
      return 1
    }
  elif [[ "$type" == "file" ]]; then
    if [[ -f "$source" ]]; then
      cat "$source"
    else
      echo "ERROR: Source file not found: ${source}" >&2
      return 1
    fi
  fi
}

# ---------------------------------------------------------------------------
# Push changes using individual file updates
# MCP: For each file:
#   1. mcp__github__get_file_contents(owner, repo, path, branch) -> get SHA
#   2. mcp__github__create_or_update_file(owner, repo, path, content,
#      message, branch, sha,
#      committer={name:"github-actions", email:"github-actions@github.com"})
# ---------------------------------------------------------------------------
push_changes_individual() {
  echo "[apply-source] Pushing ${#CHANGE_TARGETS[@]} file(s) individually..."

  local success_count=0
  local fail_count=0

  for i in "${!CHANGE_TARGETS[@]}"; do
    local target="${CHANGE_TARGETS[$i]}"
    local content

    echo "[apply-source] Processing: ${target}..." >&2

    content=$(get_change_content "$i") || {
      fail_count=$((fail_count + 1))
      continue
    }

    if [[ "$DRY_RUN" == "true" ]]; then
      echo "[apply-source] DRY-RUN: Would push ${target} ($(echo "$content" | wc -c) bytes)" >&2
      success_count=$((success_count + 1))
      continue
    fi

    if command -v gh &>/dev/null; then
      # Step 1: Get current file SHA (for updates)
      # MCP: mcp__github__get_file_contents(owner, repo, path, branch)
      local current_sha
      current_sha=$(gh api "repos/${OWNER}/${REPO_NAME}/contents/${target}?ref=${BRANCH}" \
        --jq '.sha' 2>/dev/null || echo "")

      # Step 2: Push the file
      # MCP: mcp__github__create_or_update_file(
      #   owner, repo, path, content, message, branch, sha,
      #   committer={name: "github-actions", email: "github-actions@github.com"})
      local encoded_content payload
      encoded_content=$(echo "$content" | base64 -w 0)

      if [[ -n "$current_sha" ]]; then
        payload=$(jq -n \
          --arg msg "$COMMIT_MESSAGE" \
          --arg content "$encoded_content" \
          --arg branch "$BRANCH" \
          --arg sha "$current_sha" \
          '{message: $msg, content: $content, branch: $branch, sha: $sha,
            committer: {name: "github-actions", email: "github-actions@github.com"}}')
      else
        # New file (no existing SHA)
        payload=$(jq -n \
          --arg msg "$COMMIT_MESSAGE" \
          --arg content "$encoded_content" \
          --arg branch "$BRANCH" \
          '{message: $msg, content: $content, branch: $branch,
            committer: {name: "github-actions", email: "github-actions@github.com"}}')
      fi

      echo "$payload" | gh api "repos/${OWNER}/${REPO_NAME}/contents/${target}" \
        --method PUT --input - >/dev/null 2>&1 || {
        echo "ERROR: Failed to push ${target}" >&2
        fail_count=$((fail_count + 1))
        continue
      }

      success_count=$((success_count + 1))
      echo "[apply-source] Pushed: ${target}" >&2
    else
      echo "ERROR: gh CLI not available. MCP call needed:" >&2
      echo "  mcp__github__create_or_update_file(" >&2
      echo "    owner=\"${OWNER}\", repo=\"${REPO_NAME}\"," >&2
      echo "    path=\"${target}\", branch=\"${BRANCH}\"," >&2
      echo "    content=<base64>, message=\"${COMMIT_MESSAGE}\"" >&2
      echo "  )" >&2
      fail_count=$((fail_count + 1))
    fi
  done

  echo "[apply-source] Result: ${success_count} pushed, ${fail_count} failed" >&2

  if [[ $fail_count -gt 0 && $success_count -eq 0 ]]; then
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Push changes using batch push (preferred for multiple files)
# MCP: mcp__github__push_files(
#   owner, repo, branch,
#   files=[{path, content}...],
#   message,
#   committer={name:"github-actions", email:"github-actions@github.com"})
# ---------------------------------------------------------------------------
push_changes_batch() {
  echo "[apply-source] Pushing ${#CHANGE_TARGETS[@]} file(s) as batch commit..."

  if ! command -v gh &>/dev/null; then
    echo "[apply-source] gh CLI not available, falling back to individual pushes" >&2
    push_changes_individual
    return
  fi

  # Build files array for MCP push_files
  # MCP call: mcp__github__push_files(
  #   owner: ${OWNER},
  #   repo: ${REPO_NAME},
  #   branch: ${BRANCH},
  #   files: [{ path: "...", content: "..." }, ...],
  #   message: "${COMMIT_MESSAGE}")
  local files_json="[]"

  for i in "${!CHANGE_TARGETS[@]}"; do
    local target="${CHANGE_TARGETS[$i]}"
    local content

    content=$(get_change_content "$i") || {
      echo "ERROR: Skipping ${target}: could not read content" >&2
      continue
    }

    files_json=$(echo "$files_json" | jq \
      --arg path "$target" \
      --arg content "$content" \
      '. + [{path: $path, content: $content}]')
  done

  local file_count
  file_count=$(echo "$files_json" | jq 'length')

  if [[ "$file_count" -eq 0 ]]; then
    echo "ERROR: No valid files to push" >&2
    return 1
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[apply-source] DRY-RUN: Would batch push ${file_count} file(s):" >&2
    echo "$files_json" | jq '.[].path' >&2
    return
  fi

  echo "[apply-source] MCP batch push: ${file_count} file(s)" >&2
  echo "[apply-source] Note: In Claude Code session, use mcp__github__push_files." >&2
  echo "[apply-source] Falling back to individual pushes via gh API..." >&2

  # gh CLI does not directly support push_files, so fall back
  push_changes_individual
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  echo "============================================"
  echo " Apply Source Change"
  echo " Repo: ${REPO} (branch: ${BRANCH})"
  echo " Files: ${#CHANGE_TARGETS[@]}"
  echo " Message: ${COMMIT_MESSAGE}"
  [[ -n "$VERSION" ]] && echo " Version: ${VERSION}"
  [[ -n "$COMPONENT" ]] && echo " Component: ${COMPONENT}"
  [[ "$DRY_RUN" == "true" ]] && echo " Mode: DRY-RUN"
  echo " Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "============================================"

  # List changes
  echo ""
  echo "Changes to apply:"
  for i in "${!CHANGE_TARGETS[@]}"; do
    echo "  [${CHANGE_TYPES[$i]}] ${CHANGE_TARGETS[$i]} <- ${CHANGE_SOURCES[$i]}"
  done
  echo ""

  # Push changes (use batch for multiple files, individual for single)
  local push_result=0
  if [[ ${#CHANGE_TARGETS[@]} -gt 1 ]]; then
    push_changes_batch || push_result=1
  else
    push_changes_individual || push_result=1
  fi

  # Write audit entry
  if [[ "$DRY_RUN" != "true" ]]; then
    local file_list
    file_list=$(printf "%s, " "${CHANGE_TARGETS[@]}")
    file_list="${file_list%, }"

    if [[ $push_result -eq 0 ]]; then
      write_audit_entry "apply-source-change" \
        "Pushed ${#CHANGE_TARGETS[@]} file(s) to ${REPO}: ${file_list}" \
        "success"
    else
      write_audit_entry "apply-source-change" \
        "Failed to push files to ${REPO}: ${file_list}" \
        "failure"
    fi
  fi

  echo ""
  if [[ $push_result -eq 0 ]]; then
    echo "============================================"
    echo " Apply Source Change: SUCCESS"
    echo "============================================"
  else
    echo "============================================"
    echo " Apply Source Change: FAILED"
    echo "============================================"
    exit 1
  fi
}

main "$@"
