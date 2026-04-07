#!/usr/bin/env bash
# ============================================================
# Trigger Engine — Trigger Processing Without GitHub Actions
#
# Maps to: The trigger/ directory mechanism in the original
# autopilot system. In the original system, workflows are
# triggered by bumping the "run" field in trigger/*.json files.
# This engine replicates that mechanism for Claude Code sessions
# that operate without GitHub Actions.
#
# Trigger flow:
#   1. create_trigger() — Write trigger JSON to triggers/pending/
#   2. process_trigger() — Execute by mapping to operation script
#   3. complete_trigger() — Move to triggers/completed/
#
# Trigger mapping (trigger name -> operation script):
#   release-agent       -> operations/release-agent.sh
#   release-controller  -> operations/release-controller.sh
#   promote-cap         -> operations/promote-cap.sh
#   ci-diagnose         -> operations/ci-diagnose.sh
#   ci-status           -> operations/ci-status-check.sh
#   fetch-files         -> operations/fetch-files.sh
#   source-change       -> operations/apply-source-change.sh
#   health-check        -> operations/health-check.sh
#   backup-state        -> operations/backup-state.sh
#   fix-ci              -> operations/fix-corporate-ci.sh
#
# Usage:
#   source core/trigger-engine.sh
#   create_trigger "release-agent" "ws-default" '{"component":"agent","version":"2.3.4"}'
#   process_trigger "triggers/pending/20260407-120000-release-agent.json"
# ============================================================
set -euo pipefail

# --------------- Configuration ---------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config.json"
OPERATIONS_DIR="${SCRIPT_DIR}/../operations"
TRIGGERS_DIR="${SCRIPT_DIR}/../triggers"
TRIGGERS_PENDING="${TRIGGERS_DIR}/pending"
TRIGGERS_COMPLETED="${TRIGGERS_DIR}/completed"

# Ensure trigger directories exist
mkdir -p "$TRIGGERS_PENDING" "$TRIGGERS_COMPLETED" 2>/dev/null || true

# --------------- Trigger Mapping ---------------
# Maps trigger names to their corresponding operation scripts.
# Each operation script is a self-contained runbook that can be
# executed independently.

declare -A TRIGGER_MAP
TRIGGER_MAP=(
  ["release-agent"]="operations/release-agent.sh"
  ["release-controller"]="operations/release-controller.sh"
  ["promote-cap"]="operations/promote-cap.sh"
  ["ci-diagnose"]="operations/ci-diagnose.sh"
  ["ci-status"]="operations/ci-status-check.sh"
  ["fetch-files"]="operations/fetch-files.sh"
  ["source-change"]="operations/apply-source-change.sh"
  ["health-check"]="operations/health-check.sh"
  ["backup-state"]="operations/backup-state.sh"
  ["fix-ci"]="operations/fix-corporate-ci.sh"
)

# --------------- Helper Functions ---------------

# Get timestamp for trigger filenames
_trigger_timestamp() {
  date -u +"%Y%m%d-%H%M%S"
}

# Get UTC ISO8601 timestamp
_trigger_utc_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# --------------- Core Trigger Functions ---------------

# create_trigger — Create a trigger JSON file in triggers/pending/
#
# This is the equivalent of editing trigger/*.json and bumping
# the "run" field in the original autopilot system. Instead of
# relying on GitHub Actions to detect the file change, the
# trigger is placed in a pending queue for process_trigger().
#
# Args:
#   $1 - trigger_name (e.g., "release-agent", "source-change")
#   $2 - workspace_id (e.g., "ws-default")
#   $3 - payload_json (trigger-specific parameters as JSON string)
#
# Returns: Path to created trigger file on stdout
create_trigger() {
  local trigger_name="${1:?ERROR: trigger_name is required}"
  local workspace_id="${2:?ERROR: workspace_id is required}"
  local payload_json="${3:-{\}}"

  # Validate trigger name is known
  if [ -z "${TRIGGER_MAP[$trigger_name]+_}" ]; then
    echo "ERROR: Unknown trigger '${trigger_name}'. Known triggers: ${!TRIGGER_MAP[*]}" >&2
    return 1
  fi

  # Validate payload is valid JSON
  if ! echo "$payload_json" | jq empty 2>/dev/null; then
    echo "ERROR: payload_json is not valid JSON" >&2
    return 1
  fi

  local ts
  ts=$(_trigger_timestamp)
  local now
  now=$(_trigger_utc_now)
  local trigger_file="${TRIGGERS_PENDING}/${ts}-${trigger_name}.json"

  # Build trigger JSON
  local trigger_json
  trigger_json=$(jq -n \
    --arg trigger "$trigger_name" \
    --arg workspace_id "$workspace_id" \
    --arg createdAt "$now" \
    --arg status "pending" \
    --argjson payload "$payload_json" \
    '{
      trigger: $trigger,
      workspace_id: $workspace_id,
      createdAt: $createdAt,
      status: $status,
      operationScript: "",
      payload: $payload
    }')

  # Add operation script path
  local op_script="${TRIGGER_MAP[$trigger_name]}"
  trigger_json=$(echo "$trigger_json" | jq --arg s "$op_script" '.operationScript = $s')

  echo "$trigger_json" > "$trigger_file"
  echo "OK: Trigger created at ${trigger_file}" >&2
  echo "$trigger_file"
}

# process_trigger — Execute a trigger by mapping to its operation script
#
# Reads the trigger JSON, identifies the operation script, and
# executes it with the trigger payload. Updates trigger status
# to "processing" before execution and "completed"/"failed" after.
#
# Args:
#   $1 - trigger_file_path (path to the trigger JSON file)
#
# Returns: 0 on success, 1 on failure
process_trigger() {
  local trigger_file="${1:?ERROR: trigger_file_path is required}"

  if [ ! -f "$trigger_file" ]; then
    echo "ERROR: Trigger file not found: ${trigger_file}" >&2
    return 1
  fi

  # Read trigger
  local trigger_json
  trigger_json=$(cat "$trigger_file")

  local trigger_name
  trigger_name=$(echo "$trigger_json" | jq -r '.trigger // ""' 2>/dev/null || echo "")
  local workspace_id
  workspace_id=$(echo "$trigger_json" | jq -r '.workspace_id // ""' 2>/dev/null || echo "")
  local op_script
  op_script=$(echo "$trigger_json" | jq -r '.operationScript // ""' 2>/dev/null || echo "")

  if [ -z "$trigger_name" ] || [ -z "$workspace_id" ]; then
    echo "ERROR: Invalid trigger file — missing trigger name or workspace_id" >&2
    return 1
  fi

  echo "INFO: Processing trigger '${trigger_name}' for workspace '${workspace_id}'" >&2

  # Update status to processing
  local now
  now=$(_trigger_utc_now)
  trigger_json=$(echo "$trigger_json" | jq \
    --arg status "processing" \
    --arg startedAt "$now" \
    '. + {status: $status, startedAt: $startedAt}')
  echo "$trigger_json" > "$trigger_file"

  # Resolve operation script path
  local full_script_path="${SCRIPT_DIR}/../${op_script}"

  if [ ! -f "$full_script_path" ]; then
    echo "WARNING: Operation script not found: ${full_script_path}" >&2
    echo "INFO: In a Claude Code session, manually execute the operation steps for '${trigger_name}'" >&2

    # Mark as failed
    trigger_json=$(echo "$trigger_json" | jq \
      --arg status "failed" \
      --arg error "Operation script not found: ${op_script}" \
      --arg completedAt "$(_trigger_utc_now)" \
      '. + {status: $status, error: $error, completedAt: $completedAt}')
    echo "$trigger_json" > "$trigger_file"
    return 1
  fi

  # Execute the operation script
  local exit_code=0
  bash "$full_script_path" "$workspace_id" "$trigger_file" || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    complete_trigger "$trigger_file" "success"
  else
    complete_trigger "$trigger_file" "failed"
    return 1
  fi
}

# list_pending_triggers — List all pending trigger files
#
# Returns: List of pending trigger file paths, one per line
list_pending_triggers() {
  if [ ! -d "$TRIGGERS_PENDING" ]; then
    echo "INFO: No pending triggers directory" >&2
    return 0
  fi

  local found=0
  for f in "$TRIGGERS_PENDING"/*.json; do
    [ -f "$f" ] || continue
    local status
    status=$(jq -r '.status // "unknown"' "$f" 2>/dev/null || echo "unknown")
    local trigger
    trigger=$(jq -r '.trigger // "unknown"' "$f" 2>/dev/null || echo "unknown")
    local ws
    ws=$(jq -r '.workspace_id // "unknown"' "$f" 2>/dev/null || echo "unknown")

    echo "${f}|${trigger}|${ws}|${status}"
    found=$((found + 1))
  done

  if [ "$found" -eq 0 ]; then
    echo "INFO: No pending triggers" >&2
  fi
}

# complete_trigger — Move a trigger to completed/ with final status
#
# Args:
#   $1 - trigger_file_path
#   $2 - final_status ("success" or "failed")
#
# Returns: 0 on success
complete_trigger() {
  local trigger_file="${1:?ERROR: trigger_file_path is required}"
  local final_status="${2:-success}"

  if [ ! -f "$trigger_file" ]; then
    echo "ERROR: Trigger file not found: ${trigger_file}" >&2
    return 1
  fi

  # Update status and completedAt
  local now
  now=$(_trigger_utc_now)
  local updated
  updated=$(jq \
    --arg status "$final_status" \
    --arg completedAt "$now" \
    '. + {status: $status, completedAt: $completedAt}' "$trigger_file")

  # Move to completed directory
  local filename
  filename=$(basename "$trigger_file")
  local completed_file="${TRIGGERS_COMPLETED}/${filename}"

  echo "$updated" > "$completed_file"
  rm -f "$trigger_file"

  echo "OK: Trigger moved to completed/ with status=${final_status}" >&2
}

# map_trigger_to_operation — Map a trigger name to its operation script path
#
# Args:
#   $1 - trigger_name
#
# Returns: Relative path to operation script on stdout
map_trigger_to_operation() {
  local trigger_name="${1:?ERROR: trigger_name is required}"

  if [ -z "${TRIGGER_MAP[$trigger_name]+_}" ]; then
    echo "ERROR: Unknown trigger '${trigger_name}'. Known triggers:" >&2
    for key in "${!TRIGGER_MAP[@]}"; do
      echo "  ${key} -> ${TRIGGER_MAP[$key]}" >&2
    done
    return 1
  fi

  echo "${TRIGGER_MAP[$trigger_name]}"
}

# --------------- Main (for testing) ---------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-help}" in
    create)
      create_trigger "${2:-}" "${3:-}" "${4:-{\}}"
      ;;
    process)
      process_trigger "${2:-}"
      ;;
    list)
      list_pending_triggers
      ;;
    complete)
      complete_trigger "${2:-}" "${3:-success}"
      ;;
    map)
      map_trigger_to_operation "${2:-}"
      ;;
    help|*)
      echo "Usage: $0 {create|process|list|complete|map} [args...]"
      echo ""
      echo "Commands:"
      echo "  create <trigger_name> <workspace_id> [payload_json]"
      echo "  process <trigger_file_path>"
      echo "  list"
      echo "  complete <trigger_file_path> [status]"
      echo "  map <trigger_name>"
      echo ""
      echo "Known triggers:"
      for key in "${!TRIGGER_MAP[@]}"; do
        printf "  %-22s -> %s\n" "$key" "${TRIGGER_MAP[$key]}"
      done
      ;;
  esac
fi
