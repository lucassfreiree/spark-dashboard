#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# ci-status-check.sh
# Replaces: .github/workflows/ci-status-check.yml
#
# Checks corporate CI pipeline status for a given repo and commit.
# Filters workflow runs by name ("Esteira de Build NPM" by default).
#
# Returns: JSON with conclusion, status, run_id, duration.
# Possible conclusions: success | failure | in_progress | pending | not_found
#
# Supports polling mode: repeatedly checks until a terminal state is reached
# or max polls exhausted.
#
# Usage:
#   ./ci-status-check.sh --repo <owner/repo> [options]
#
# Options:
#   --workspace <ws_id>       Workspace ID (default: ws-default)
#   --repo <owner/repo>       Corporate repo to check (required)
#   --sha <commit_sha>        Specific commit SHA (default: latest on main)
#   --workflow <name>          Workflow name filter (default: "Esteira de Build NPM")
#   --poll                    Enable polling mode
#   --max-polls <n>           Max poll attempts (default: 20)
#   --interval <seconds>      Poll interval in seconds (default: 120)
#   --output-file <path>      Write result JSON to file
#
# MCP tools used:
#   - mcp__github__list_commits(owner, repo, sha="main", per_page=1)
#     Resolve latest commit SHA when --sha not provided.
#   - mcp__github__get_commit(owner, repo, sha)
#     Get commit check-runs and statuses.
#   - GitHub API: repos/{owner}/{repo}/actions/runs?head_sha={sha}
#     List workflow runs for a commit.
#   - GitHub API: repos/{owner}/{repo}/commits/{sha}/check-runs
#     Fallback: check-runs API for commit status.
#
# Output JSON format:
#   {
#     "repo": "owner/repo",
#     "sha": "abc1234...",
#     "workflow": "Esteira de Build NPM",
#     "status": "completed|in_progress|queued|pending|not_found",
#     "conclusion": "success|failure|in_progress|pending|not_found",
#     "runId": "12345",
#     "runUrl": "https://github.com/...",
#     "duration": "14m32s",
#     "startedAt": "...",
#     "completedAt": "...",
#     "checkedAt": "..."
#   }
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source core modules
source "${SCRIPT_DIR}/../core/state-manager.sh"

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
WORKSPACE_ID="${WORKSPACE_ID:-ws-default}"
REPO=""
SHA=""
WORKFLOW_NAME="Esteira de Build NPM"
POLL_MODE=false
MAX_POLLS=20
POLL_INTERVAL=120
OUTPUT_FILE=""

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace)    WORKSPACE_ID="$2"; shift 2 ;;
    --repo)         REPO="$2"; shift 2 ;;
    --sha)          SHA="$2"; shift 2 ;;
    --workflow)     WORKFLOW_NAME="$2"; shift 2 ;;
    --poll)         POLL_MODE=true; shift ;;
    --max-polls)    MAX_POLLS="$2"; shift 2 ;;
    --interval)     POLL_INTERVAL="$2"; shift 2 ;;
    --output-file)  OUTPUT_FILE="$2"; shift 2 ;;
    *) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$REPO" ]]; then
  echo "ERROR: --repo is required (e.g., --repo bbvinet/psc-sre-automacao-agent)" >&2
  exit 1
fi

OWNER=$(echo "$REPO" | cut -d/ -f1)
REPO_NAME=$(echo "$REPO" | cut -d/ -f2)

# ---------------------------------------------------------------------------
# Get latest commit SHA if not provided
# MCP: mcp__github__list_commits(owner, repo, sha="main", per_page=1)
# ---------------------------------------------------------------------------
resolve_sha() {
  if [[ -n "$SHA" ]]; then
    echo "[ci-status] Using provided SHA: ${SHA}" >&2
    return
  fi

  echo "[ci-status] Resolving latest SHA on main..." >&2

  if command -v gh &>/dev/null; then
    SHA=$(gh api "repos/${OWNER}/${REPO_NAME}/commits?sha=main&per_page=1" \
      --jq '.[0].sha // ""' 2>/dev/null || echo "")
  fi

  if [[ -z "$SHA" ]]; then
    echo "ERROR: Could not resolve latest SHA for ${REPO}" >&2
    exit 1
  fi

  echo "[ci-status] Latest SHA: ${SHA}" >&2
}

# ---------------------------------------------------------------------------
# Check workflow runs for the commit
# API: GET /repos/{owner}/{repo}/actions/runs?head_sha={sha}
# Fallback: GET /repos/{owner}/{repo}/commits/{sha}/check-runs
# ---------------------------------------------------------------------------
check_workflow_runs() {
  local result_json
  result_json=$(jq -n \
    --arg repo "$REPO" \
    --arg sha "$SHA" \
    --arg workflow "$WORKFLOW_NAME" \
    --arg checkedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{repo: $repo, sha: $sha, workflow: $workflow, status: "not_found",
      conclusion: "not_found", checkedAt: $checkedAt}')

  if ! command -v gh &>/dev/null; then
    echo "ERROR: gh CLI not available. Use MCP in Claude Code session." >&2
    echo "$result_json"
    return
  fi

  # Method 1: Check workflow runs filtered by head_sha
  local runs_json
  runs_json=$(gh api "repos/${OWNER}/${REPO_NAME}/actions/runs?head_sha=${SHA}&per_page=10" 2>/dev/null || echo "")

  if [[ -n "$runs_json" ]]; then
    local matching_run
    matching_run=$(echo "$runs_json" | jq -r --arg wf "$WORKFLOW_NAME" '
      .workflow_runs // [] |
      map(select(.name == $wf or .display_title == $wf)) |
      sort_by(.created_at) | last // empty
    ' 2>/dev/null || echo "")

    if [[ -n "$matching_run" && "$matching_run" != "null" ]]; then
      local run_id run_status run_conclusion run_url started_at completed_at
      run_id=$(echo "$matching_run" | jq -r '.id // ""')
      run_status=$(echo "$matching_run" | jq -r '.status // "unknown"')
      run_conclusion=$(echo "$matching_run" | jq -r '.conclusion // ""')
      run_url=$(echo "$matching_run" | jq -r '.html_url // ""')
      started_at=$(echo "$matching_run" | jq -r '.run_started_at // ""')
      completed_at=$(echo "$matching_run" | jq -r '.updated_at // ""')

      # Map status to conclusion for non-completed runs
      local effective_conclusion="$run_conclusion"
      if [[ "$run_status" == "in_progress" ]]; then
        effective_conclusion="in_progress"
      elif [[ "$run_status" == "queued" || "$run_status" == "waiting" ]]; then
        effective_conclusion="pending"
      elif [[ -z "$effective_conclusion" || "$effective_conclusion" == "null" ]]; then
        effective_conclusion="in_progress"
      fi

      # Calculate duration
      local duration=""
      if [[ -n "$started_at" && -n "$completed_at" && "$run_status" == "completed" ]]; then
        local start_epoch end_epoch diff_sec
        start_epoch=$(date -d "$started_at" +%s 2>/dev/null || echo "0")
        end_epoch=$(date -d "$completed_at" +%s 2>/dev/null || echo "0")
        diff_sec=$(( end_epoch - start_epoch ))
        duration="$((diff_sec / 60))m$((diff_sec % 60))s"
      fi

      result_json=$(jq -n \
        --arg repo "$REPO" \
        --arg sha "$SHA" \
        --arg workflow "$WORKFLOW_NAME" \
        --arg status "$run_status" \
        --arg conclusion "$effective_conclusion" \
        --arg runId "$run_id" \
        --arg runUrl "$run_url" \
        --arg duration "$duration" \
        --arg startedAt "$started_at" \
        --arg completedAt "$completed_at" \
        --arg checkedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{repo: $repo, sha: $sha, workflow: $workflow, status: $status,
          conclusion: $conclusion, runId: $runId, runUrl: $runUrl,
          duration: $duration, startedAt: $startedAt, completedAt: $completedAt,
          checkedAt: $checkedAt}')

      echo "$result_json"
      return
    fi
  fi

  # Method 2: Fallback to check-runs API
  local checks_json
  checks_json=$(gh api "repos/${OWNER}/${REPO_NAME}/commits/${SHA}/check-runs?per_page=20" 2>/dev/null || echo "")

  if [[ -n "$checks_json" ]]; then
    local matching_check
    matching_check=$(echo "$checks_json" | jq -r --arg wf "$WORKFLOW_NAME" '
      .check_runs // [] |
      map(select(.name | contains($wf))) |
      sort_by(.started_at) | last // empty
    ' 2>/dev/null || echo "")

    if [[ -n "$matching_check" && "$matching_check" != "null" ]]; then
      local check_status check_conclusion check_url started_at completed_at
      check_status=$(echo "$matching_check" | jq -r '.status // "unknown"')
      check_conclusion=$(echo "$matching_check" | jq -r '.conclusion // ""')
      check_url=$(echo "$matching_check" | jq -r '.html_url // ""')
      started_at=$(echo "$matching_check" | jq -r '.started_at // ""')
      completed_at=$(echo "$matching_check" | jq -r '.completed_at // ""')

      local effective_conclusion="$check_conclusion"
      if [[ "$check_status" != "completed" ]]; then
        effective_conclusion="in_progress"
      fi

      result_json=$(jq -n \
        --arg repo "$REPO" \
        --arg sha "$SHA" \
        --arg workflow "$WORKFLOW_NAME" \
        --arg status "$check_status" \
        --arg conclusion "$effective_conclusion" \
        --arg runUrl "$check_url" \
        --arg startedAt "$started_at" \
        --arg completedAt "$completed_at" \
        --arg checkedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{repo: $repo, sha: $sha, workflow: $workflow, status: $status,
          conclusion: $conclusion, runUrl: $runUrl, startedAt: $startedAt,
          completedAt: $completedAt, checkedAt: $checkedAt}')

      echo "$result_json"
      return
    fi
  fi

  # No matching run found
  echo "$result_json"
}

# ---------------------------------------------------------------------------
# Write result to output file and workspace state
# ---------------------------------------------------------------------------
write_output() {
  local result="$1"
  if [[ -n "$OUTPUT_FILE" ]]; then
    echo "$result" | jq . > "$OUTPUT_FILE"
    echo "[ci-status] Result written to ${OUTPUT_FILE}" >&2
  fi

  # Write to workspace state for dashboard consumption
  # MCP: mcp__github__create_or_update_file(
  #   path="state/workspaces/{ws_id}/ci-status-{component}.json",
  #   branch=autopilot-state)
  local component_name
  component_name=$(echo "$REPO_NAME" | grep -oP '(agent|controller)' 2>/dev/null || echo "unknown")

  write_state "$WORKSPACE_ID" "ci-status-${component_name}.json" "$result" \
    "ci-status: ${component_name} check for ${WORKSPACE_ID}" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  echo "[ci-status] Checking CI for ${REPO}" >&2
  echo "[ci-status] Workflow: ${WORKFLOW_NAME}" >&2

  resolve_sha

  if [[ "$POLL_MODE" == "true" ]]; then
    echo "[ci-status] Polling mode: max ${MAX_POLLS} polls, ${POLL_INTERVAL}s interval" >&2

    local poll_count=0
    while [[ $poll_count -lt $MAX_POLLS ]]; do
      poll_count=$((poll_count + 1))
      echo "[ci-status] Poll ${poll_count}/${MAX_POLLS}..." >&2

      local result
      result=$(check_workflow_runs)

      local conclusion
      conclusion=$(echo "$result" | jq -r '.conclusion // "unknown"' 2>/dev/null || echo "unknown")

      echo "[ci-status] Status: ${conclusion}" >&2

      # Terminal states
      if [[ "$conclusion" == "success" || "$conclusion" == "failure" ]]; then
        write_output "$result"
        echo "$result"
        return
      fi

      # Give up if not_found after enough polls
      if [[ "$conclusion" == "not_found" && $poll_count -ge 5 ]]; then
        echo "[ci-status] No matching workflow run after ${poll_count} polls." >&2
        write_output "$result"
        echo "$result"
        return
      fi

      if [[ $poll_count -lt $MAX_POLLS ]]; then
        echo "[ci-status] Waiting ${POLL_INTERVAL}s..." >&2
        sleep "$POLL_INTERVAL"
      fi
    done

    # Max polls reached - return timeout
    echo "[ci-status] Max polls (${MAX_POLLS}) reached." >&2
    local final_result
    final_result=$(check_workflow_runs)
    final_result=$(echo "$final_result" | jq '.conclusion = "timeout"')
    write_output "$final_result"
    echo "$final_result"
  else
    # Single check mode
    local result
    result=$(check_workflow_runs)
    write_output "$result"
    echo "$result"
  fi
}

main "$@"
