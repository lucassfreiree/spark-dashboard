#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# health-check.sh
# Replaces: .github/workflows/health-check.yml
#
# Performs comprehensive system health validation for a workspace.
# Checks:
#   1. State branch accessible
#   2. Workspace configs valid
#   3. No expired locks
#   4. Release states consistent (controller + agent)
#   5. Dashboard state.json up to date
#   6. Stuck workflow runs
#   7. Deploy consistency (CAP tag vs release state)
#
# Output: Writes health.json to state/workspaces/{ws_id}/health.json
#         on the autopilot-state branch.
#
# Usage:
#   ./health-check.sh [--workspace <ws_id>]
#
# MCP tools used:
#   - mcp__github__get_file_contents  (read state files from autopilot-state)
#   - mcp__github__create_or_update_file (write health.json result)
#
# Schema: schemas/health-state.schema.json (schemaVersion: 2)
# Health state fields:
#   required: schemaVersion (const 2), workspaceId, checkedAt
#   checks: stateBranch, controllerRelease, agentRelease, stuckRuns,
#           workspace, locks, drift, deployConsistency
#   each check: { status: pass|warn|fail|skip, message, detail }
#   overall: healthy | degraded | critical | unknown
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source core modules
source "${SCRIPT_DIR}/../core/state-manager.sh"

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
SCHEMA_VERSION=2

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
WORKSPACE_ID="${WORKSPACE_ID:-ws-default}"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace) WORKSPACE_ID="$2"; shift 2 ;;
    *) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Helper: build a check result JSON object
# ---------------------------------------------------------------------------
build_check() {
  local status="$1"   # pass | warn | fail | skip
  local message="$2"
  local detail="${3:-}"
  jq -n \
    --arg s "$status" \
    --arg m "$message" \
    --arg d "$detail" \
    '{status: $s, message: $m, detail: $d}'
}

# ---------------------------------------------------------------------------
# Check 1: State branch accessible
# MCP: mcp__github__get_file_contents(owner, repo, path="state/workspaces/{ws_id}/workspace.json", branch=autopilot-state)
# ---------------------------------------------------------------------------
check_state_branch() {
  echo "[health-check] Checking state branch accessibility..." >&2
  local result
  if result=$(read_workspace_config "$WORKSPACE_ID" 2>/dev/null); then
    build_check "pass" "State branch is accessible" "Read workspace.json successfully"
  else
    build_check "fail" "State branch is NOT accessible" "Failed to read workspace.json for ${WORKSPACE_ID}"
  fi
}

# ---------------------------------------------------------------------------
# Check 2: Workspace config valid
# MCP: mcp__github__get_file_contents(path="state/workspaces/{ws_id}/workspace.json")
# ---------------------------------------------------------------------------
check_workspace_config() {
  echo "[health-check] Validating workspace configuration..." >&2
  local ws_json
  ws_json=$(read_workspace_config "$WORKSPACE_ID" 2>/dev/null || echo "")

  if [[ -z "$ws_json" ]]; then
    build_check "fail" "Workspace config missing" "No workspace.json found"
    return
  fi

  local workspace_id component_count
  workspace_id=$(echo "$ws_json" | jq -r '.workspaceId // ""' 2>/dev/null || echo "")
  component_count=$(echo "$ws_json" | jq -r '[.controller, .agent] | map(select(. != null)) | length' 2>/dev/null || echo "0")

  if [[ "$workspace_id" == "$WORKSPACE_ID" && "$component_count" -gt 0 ]]; then
    build_check "pass" "Workspace config is valid" "workspaceId=${workspace_id}, components=${component_count}"
  elif [[ "$workspace_id" != "$WORKSPACE_ID" ]]; then
    build_check "fail" "Workspace ID mismatch" "Expected ${WORKSPACE_ID}, got ${workspace_id}"
  else
    build_check "warn" "Workspace config incomplete" "No components configured"
  fi
}

# ---------------------------------------------------------------------------
# Check 3: No expired locks
# MCP: mcp__github__get_file_contents(path="state/workspaces/{ws_id}/locks/session-lock.json")
# ---------------------------------------------------------------------------
check_locks() {
  echo "[health-check] Checking for expired locks..." >&2
  local lock_json
  lock_json=$(read_state "$WORKSPACE_ID" "locks/session-lock.json" 2>/dev/null || echo "")

  if [[ -z "$lock_json" ]]; then
    build_check "pass" "No active locks" "Lock file does not exist"
    return
  fi

  local locked_at ttl_minutes
  locked_at=$(echo "$lock_json" | jq -r '.lockedAt // ""' 2>/dev/null || echo "")
  ttl_minutes=$(echo "$lock_json" | jq -r '.ttlMinutes // 30' 2>/dev/null || echo "30")

  if [[ -z "$locked_at" ]]; then
    build_check "warn" "Lock exists but no timestamp" "Cannot determine expiry"
    return
  fi

  local now_epoch lock_epoch age_minutes
  now_epoch=$(date +%s)
  lock_epoch=$(date -d "$locked_at" +%s 2>/dev/null || echo "0")
  age_minutes=$(( (now_epoch - lock_epoch) / 60 ))

  if [[ $age_minutes -gt $ttl_minutes ]]; then
    build_check "fail" "Expired lock detected" "Lock age: ${age_minutes}m, TTL: ${ttl_minutes}m, locked at: ${locked_at}"
  else
    build_check "pass" "Active lock within TTL" "Age: ${age_minutes}m / TTL: ${ttl_minutes}m"
  fi
}

# ---------------------------------------------------------------------------
# Check 4: Controller release state consistent
# MCP: mcp__github__get_file_contents(path="state/workspaces/{ws_id}/controller-release-state.json")
# ---------------------------------------------------------------------------
check_controller_release() {
  echo "[health-check] Checking controller release state..." >&2
  local state_json
  state_json=$(read_release_state "$WORKSPACE_ID" "controller" 2>/dev/null || echo "")

  if [[ -z "$state_json" ]]; then
    build_check "skip" "Controller release state not found" "File may not exist yet"
    return
  fi

  local schema_ver status version
  schema_ver=$(echo "$state_json" | jq -r '.schemaVersion // 0' 2>/dev/null || echo "0")
  status=$(echo "$state_json" | jq -r '.status // "unknown"' 2>/dev/null || echo "unknown")
  version=$(echo "$state_json" | jq -r '.lastVersion // ""' 2>/dev/null || echo "")

  if [[ "$schema_ver" -ne "$SCHEMA_VERSION" ]]; then
    build_check "warn" "Controller schema version mismatch" "Expected ${SCHEMA_VERSION}, got ${schema_ver}"
  elif [[ "$status" == "failed" ]]; then
    build_check "warn" "Controller in failed state" "version=${version}, status=${status}"
  elif [[ "$status" == "releasing" ]]; then
    local updated_at
    updated_at=$(echo "$state_json" | jq -r '.updatedAt // ""' 2>/dev/null || echo "")
    if [[ -n "$updated_at" ]]; then
      local now_epoch upd_epoch age_min
      now_epoch=$(date +%s)
      upd_epoch=$(date -d "$updated_at" +%s 2>/dev/null || echo "0")
      age_min=$(( (now_epoch - upd_epoch) / 60 ))
      if [[ $age_min -gt 60 ]]; then
        build_check "fail" "Controller stuck in releasing state" "Releasing for ${age_min} minutes"
        return
      fi
    fi
    build_check "pass" "Controller release in progress" "version=${version}, status=${status}"
  else
    build_check "pass" "Controller release state is consistent" "version=${version}, status=${status}"
  fi
}

# ---------------------------------------------------------------------------
# Check 5: Agent release state consistent
# MCP: mcp__github__get_file_contents(path="state/workspaces/{ws_id}/agent-release-state.json")
# ---------------------------------------------------------------------------
check_agent_release() {
  echo "[health-check] Checking agent release state..." >&2
  local state_json
  state_json=$(read_release_state "$WORKSPACE_ID" "agent" 2>/dev/null || echo "")

  if [[ -z "$state_json" ]]; then
    build_check "skip" "Agent release state not found" "File may not exist yet"
    return
  fi

  local schema_ver status version
  schema_ver=$(echo "$state_json" | jq -r '.schemaVersion // 0' 2>/dev/null || echo "0")
  status=$(echo "$state_json" | jq -r '.status // "unknown"' 2>/dev/null || echo "unknown")
  version=$(echo "$state_json" | jq -r '.lastVersion // ""' 2>/dev/null || echo "")

  if [[ "$schema_ver" -ne "$SCHEMA_VERSION" ]]; then
    build_check "warn" "Agent schema version mismatch" "Expected ${SCHEMA_VERSION}, got ${schema_ver}"
  elif [[ "$status" == "failed" ]]; then
    build_check "warn" "Agent in failed state" "version=${version}, status=${status}"
  elif [[ "$status" == "releasing" ]]; then
    local updated_at
    updated_at=$(echo "$state_json" | jq -r '.updatedAt // ""' 2>/dev/null || echo "")
    if [[ -n "$updated_at" ]]; then
      local now_epoch upd_epoch age_min
      now_epoch=$(date +%s)
      upd_epoch=$(date -d "$updated_at" +%s 2>/dev/null || echo "0")
      age_min=$(( (now_epoch - upd_epoch) / 60 ))
      if [[ $age_min -gt 60 ]]; then
        build_check "fail" "Agent stuck in releasing state" "Releasing for ${age_min} minutes"
        return
      fi
    fi
    build_check "pass" "Agent release in progress" "version=${version}, status=${status}"
  else
    build_check "pass" "Agent release state is consistent" "version=${version}, status=${status}"
  fi
}

# ---------------------------------------------------------------------------
# Check 6: Stuck workflow runs
# MCP: mcp__github__get_file_contents(path="state/workspaces/{ws_id}/ci-monitor-{component}.json")
# ---------------------------------------------------------------------------
check_stuck_runs() {
  echo "[health-check] Checking for stuck workflow runs..." >&2
  local issues=""

  for component in controller agent; do
    local ci_json
    ci_json=$(read_state "$WORKSPACE_ID" "ci-monitor-${component}.json" 2>/dev/null || echo "")
    if [[ -z "$ci_json" ]]; then continue; fi

    local ci_status last_check
    ci_status=$(echo "$ci_json" | jq -r '.ciOutcome // ""' 2>/dev/null || echo "")
    last_check=$(echo "$ci_json" | jq -r '.lastCheckedAt // ""' 2>/dev/null || echo "")

    if [[ "$ci_status" == "in_progress" && -n "$last_check" ]]; then
      local now_epoch check_epoch age_min
      now_epoch=$(date +%s)
      check_epoch=$(date -d "$last_check" +%s 2>/dev/null || echo "0")
      age_min=$(( (now_epoch - check_epoch) / 60 ))
      if [[ $age_min -gt 60 ]]; then
        issues="${issues}${component} CI stuck for ${age_min}m; "
      fi
    fi
  done

  if [[ -n "$issues" ]]; then
    build_check "warn" "Potentially stuck runs detected" "$issues"
  else
    build_check "pass" "No stuck runs detected" ""
  fi
}

# ---------------------------------------------------------------------------
# Check 7: Dashboard state.json freshness (drift check)
# MCP: mcp__github__get_file_contents(path="state/state.json", branch=autopilot-state)
# ---------------------------------------------------------------------------
check_drift() {
  echo "[health-check] Checking dashboard state.json freshness..." >&2
  # Read from the global state.json (not workspace-scoped)
  local state_json
  if command -v gh &>/dev/null; then
    state_json=$(gh api "repos/${STATE_OWNER}/${STATE_REPO}/contents/state/state.json?ref=${STATE_BRANCH}" \
      --jq '.content' 2>/dev/null | base64 -d 2>/dev/null || echo "")
  else
    state_json=""
  fi

  if [[ -z "$state_json" ]]; then
    build_check "skip" "Dashboard state.json not found" "May not be synced yet"
    return
  fi

  local synced_at
  synced_at=$(echo "$state_json" | jq -r '.syncedAt // .updatedAt // ""' 2>/dev/null || echo "")

  if [[ -z "$synced_at" ]]; then
    build_check "warn" "Dashboard state.json has no timestamp" "Cannot determine freshness"
    return
  fi

  local now_epoch sync_epoch age_min
  now_epoch=$(date +%s)
  sync_epoch=$(date -d "$synced_at" +%s 2>/dev/null || echo "0")
  age_min=$(( (now_epoch - sync_epoch) / 60 ))

  if [[ $age_min -gt 30 ]]; then
    build_check "warn" "Dashboard state.json is stale" "Last synced ${age_min} minutes ago (${synced_at})"
  else
    build_check "pass" "Dashboard state.json is fresh" "Last synced ${age_min} minutes ago"
  fi
}

# ---------------------------------------------------------------------------
# Check 8: Deploy consistency (CAP tag matches release state)
# MCP: mcp__github__get_file_contents(path="state/workspaces/{ws_id}/controller-release-state.json")
# ---------------------------------------------------------------------------
check_deploy_consistency() {
  echo "[health-check] Checking deploy consistency..." >&2
  local ctrl_state
  ctrl_state=$(read_release_state "$WORKSPACE_ID" "controller" 2>/dev/null || echo "")

  if [[ -z "$ctrl_state" ]]; then
    build_check "skip" "No controller release state to compare" ""
    return
  fi

  local last_tag promoted
  last_tag=$(echo "$ctrl_state" | jq -r '.lastTag // ""' 2>/dev/null || echo "")
  promoted=$(echo "$ctrl_state" | jq -r '.promoted // false' 2>/dev/null || echo "false")

  if [[ -z "$last_tag" ]]; then
    build_check "skip" "No last tag in release state" ""
  elif [[ "$promoted" == "true" ]]; then
    build_check "pass" "Last release was promoted" "tag=${last_tag}"
  else
    build_check "warn" "Last release not yet promoted to CAP" "tag=${last_tag}, promoted=${promoted}"
  fi
}

# ---------------------------------------------------------------------------
# Main: Run all checks and assemble health.json
# ---------------------------------------------------------------------------
main() {
  echo "============================================"
  echo " Health Check: ${WORKSPACE_ID}"
  echo " Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "============================================"

  local check_state_branch_result check_workspace_result check_locks_result
  local check_ctrl_result check_agent_result check_stuck_result
  local check_drift_result check_deploy_result

  check_state_branch_result=$(check_state_branch)
  check_workspace_result=$(check_workspace_config)
  check_locks_result=$(check_locks)
  check_ctrl_result=$(check_controller_release)
  check_agent_result=$(check_agent_release)
  check_stuck_result=$(check_stuck_runs)
  check_drift_result=$(check_drift)
  check_deploy_result=$(check_deploy_consistency)

  # Assemble checks object
  local all_checks
  all_checks=$(jq -n \
    --argjson stateBranch "$check_state_branch_result" \
    --argjson workspace "$check_workspace_result" \
    --argjson locks "$check_locks_result" \
    --argjson controllerRelease "$check_ctrl_result" \
    --argjson agentRelease "$check_agent_result" \
    --argjson stuckRuns "$check_stuck_result" \
    --argjson drift "$check_drift_result" \
    --argjson deployConsistency "$check_deploy_result" \
    '{
      stateBranch: $stateBranch,
      workspace: $workspace,
      locks: $locks,
      controllerRelease: $controllerRelease,
      agentRelease: $agentRelease,
      stuckRuns: $stuckRuns,
      drift: $drift,
      deployConsistency: $deployConsistency
    }')

  # Determine overall health
  local fail_count warn_count
  fail_count=$(echo "$all_checks" | jq '[to_entries[].value.status] | map(select(. == "fail")) | length' 2>/dev/null || echo "0")
  warn_count=$(echo "$all_checks" | jq '[to_entries[].value.status] | map(select(. == "warn")) | length' 2>/dev/null || echo "0")

  local overall="healthy"
  local summary="All checks passed"
  if [[ $fail_count -gt 0 ]]; then
    overall="critical"
    summary="${fail_count} check(s) failed, ${warn_count} warning(s)"
  elif [[ $warn_count -gt 0 ]]; then
    overall="degraded"
    summary="${warn_count} warning(s) detected"
  fi

  # Build final health.json (matches health-state.schema.json v2)
  local health_json
  health_json=$(jq -n \
    --argjson schemaVersion "$SCHEMA_VERSION" \
    --arg workspaceId "$WORKSPACE_ID" \
    --arg checkedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg overall "$overall" \
    --argjson checks "$all_checks" \
    --arg summary "$summary" \
    '{
      schemaVersion: $schemaVersion,
      workspaceId: $workspaceId,
      checkedAt: $checkedAt,
      overall: $overall,
      checks: $checks,
      summary: $summary
    }')

  echo ""
  echo "[health-check] Result: ${overall} - ${summary}"
  echo "$health_json" | jq .

  # Write result to state branch
  # MCP call: mcp__github__create_or_update_file
  #   owner: lucassfreiree, repo: autopilot
  #   path: state/workspaces/{ws_id}/health.json
  #   branch: autopilot-state
  #   content: <health_json base64 encoded>
  #   message: "health-check: ${overall} for ${WORKSPACE_ID}"
  write_state "$WORKSPACE_ID" "health.json" "$health_json" \
    "health-check: ${overall} for ${WORKSPACE_ID}"

  echo "[health-check] Health result written to state/workspaces/${WORKSPACE_ID}/health.json"

  # Exit code reflects health
  if [[ "$overall" == "critical" ]]; then
    exit 2
  elif [[ "$overall" == "degraded" ]]; then
    exit 1
  fi
  exit 0
}

main "$@"
