#!/usr/bin/env bash
# ============================================================
# Schema Validator — JSON Validation Using jq
#
# Maps to: The validation logic used throughout the autopilot
# system in workflows like compliance-gate.yml, seed-workspace.yml,
# and continuous-improvement.yml. Ensures all state objects conform
# to their JSON schemas before being written.
#
# Schemas are located at:
#   /home/user/spark-dashboard/autopilot-backup/schemas/
#
# Available schemas:
#   workspace.schema.json      — Workspace configuration
#   release-state.schema.json  — Release state (agent/controller)
#   lock.schema.json           — Session and operation locks
#   audit.schema.json          — Audit trail entries
#   health-state.schema.json   — Health check results
#   metrics.schema.json        — Daily metrics snapshots
#   handoff.schema.json        — Agent handoff queue items
#   improvement.schema.json    — Improvement records
#
# Usage:
#   source core/schema-validator.sh
#   validate_json '{"key":"value"}'
#   validate_required_fields '{"a":1}' "a" "b"
#   validate_workspace_config '{"schemaVersion":3,...}'
# ============================================================
set -euo pipefail

# --------------- Configuration ---------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMAS_DIR="${SCRIPT_DIR}/../schemas"

# --------------- Core Validation Functions ---------------

# validate_json — Validate that a string is valid JSON
#
# Args:
#   $1 - json_string (the JSON to validate)
#
# Returns: 0 if valid JSON, 1 if invalid
validate_json() {
  local json_string="${1:?ERROR: json_string is required}"

  if echo "$json_string" | jq empty 2>/dev/null; then
    return 0
  else
    echo "ERROR: Invalid JSON" >&2
    return 1
  fi
}

# validate_required_fields — Check that all required fields exist and are non-null
#
# Uses jq to verify each field exists and is not null in the JSON.
#
# Args:
#   $1 - json_string (the JSON to check)
#   $2+ - field names to check (variable number of arguments)
#
# Returns: 0 if all fields present, 1 if any missing
validate_required_fields() {
  local json_string="${1:?ERROR: json_string is required}"
  shift

  if [ $# -eq 0 ]; then
    echo "ERROR: At least one field name is required" >&2
    return 1
  fi

  # Validate JSON first
  if ! validate_json "$json_string"; then
    return 1
  fi

  local missing_fields=()
  for field in "$@"; do
    local value
    value=$(echo "$json_string" | jq -r --arg f "$field" '.[$f] // "___NULL___"' 2>/dev/null || echo "___NULL___")

    if [ "$value" = "___NULL___" ] || [ "$value" = "null" ]; then
      missing_fields+=("$field")
    fi
  done

  if [ ${#missing_fields[@]} -gt 0 ]; then
    echo "ERROR: Missing required fields: ${missing_fields[*]}" >&2
    return 1
  fi

  return 0
}

# validate_schema — Validate a JSON object against a schema file
#
# Since jq does not natively support JSON Schema validation,
# this function performs structural checks based on the schema:
#   - Validates required fields exist
#   - Validates enum values where specified
#   - Validates type constraints (string, number, boolean, array, object)
#   - Validates const values
#   - Validates string patterns (basic regex)
#
# Args:
#   $1 - json_string (the JSON to validate)
#   $2 - schema_file (path to schema file, relative to schemas/ or absolute)
#
# Returns: 0 if valid, 1 if invalid. Error details on stderr.
validate_schema() {
  local json_string="${1:?ERROR: json_string is required}"
  local schema_file="${2:?ERROR: schema_file is required}"

  # Resolve schema file path
  if [ ! -f "$schema_file" ]; then
    schema_file="${SCHEMAS_DIR}/${schema_file}"
  fi

  if [ ! -f "$schema_file" ]; then
    echo "ERROR: Schema file not found: ${schema_file}" >&2
    return 1
  fi

  # Validate input is valid JSON
  if ! validate_json "$json_string"; then
    return 1
  fi

  local schema
  schema=$(cat "$schema_file")
  local errors=0

  # Check required fields
  local required_fields
  required_fields=$(echo "$schema" | jq -r '.required[]? // empty' 2>/dev/null || echo "")

  if [ -n "$required_fields" ]; then
    while IFS= read -r field; do
      [ -z "$field" ] && continue
      local value
      value=$(echo "$json_string" | jq -r --arg f "$field" '.[$f] // "___MISSING___"' 2>/dev/null || echo "___MISSING___")
      if [ "$value" = "___MISSING___" ]; then
        echo "ERROR: Required field '${field}' is missing" >&2
        errors=$((errors + 1))
      fi
    done <<< "$required_fields"
  fi

  # Check enum constraints for each property
  local properties
  properties=$(echo "$schema" | jq -r '.properties | keys[]? // empty' 2>/dev/null || echo "")

  if [ -n "$properties" ]; then
    while IFS= read -r prop; do
      [ -z "$prop" ] && continue

      # Check if field exists in the input
      local has_field
      has_field=$(echo "$json_string" | jq --arg f "$prop" 'has($f)' 2>/dev/null || echo "false")
      [ "$has_field" = "false" ] && continue

      local value
      value=$(echo "$json_string" | jq -r --arg f "$prop" '.[$f] // ""' 2>/dev/null || echo "")

      # Check const constraint
      local const_val
      const_val=$(echo "$schema" | jq -r --arg f "$prop" '.properties[$f].const // "___NOCONST___"' 2>/dev/null || echo "___NOCONST___")
      if [ "$const_val" != "___NOCONST___" ]; then
        if [ "$value" != "$const_val" ]; then
          echo "ERROR: Field '${prop}' must be '${const_val}', got '${value}'" >&2
          errors=$((errors + 1))
        fi
      fi

      # Check enum constraint
      local enum_values
      enum_values=$(echo "$schema" | jq -r --arg f "$prop" '.properties[$f].enum // null' 2>/dev/null || echo "null")
      if [ "$enum_values" != "null" ]; then
        local is_valid
        is_valid=$(echo "$enum_values" | jq --arg v "$value" 'any(. == $v)' 2>/dev/null || echo "false")
        if [ "$is_valid" = "false" ]; then
          echo "ERROR: Field '${prop}' value '${value}' not in enum: ${enum_values}" >&2
          errors=$((errors + 1))
        fi
      fi

      # Check type constraint
      local expected_type
      expected_type=$(echo "$schema" | jq -r --arg f "$prop" '.properties[$f].type // ""' 2>/dev/null || echo "")
      if [ -n "$expected_type" ]; then
        local actual_type
        actual_type=$(echo "$json_string" | jq -r --arg f "$prop" '.[$f] | type' 2>/dev/null || echo "")
        case "$expected_type" in
          string)
            [ "$actual_type" != "string" ] && {
              echo "ERROR: Field '${prop}' expected type string, got ${actual_type}" >&2
              errors=$((errors + 1))
            }
            ;;
          number|integer)
            [ "$actual_type" != "number" ] && {
              echo "ERROR: Field '${prop}' expected type ${expected_type}, got ${actual_type}" >&2
              errors=$((errors + 1))
            }
            ;;
          boolean)
            [ "$actual_type" != "boolean" ] && {
              echo "ERROR: Field '${prop}' expected type boolean, got ${actual_type}" >&2
              errors=$((errors + 1))
            }
            ;;
          array)
            [ "$actual_type" != "array" ] && {
              echo "ERROR: Field '${prop}' expected type array, got ${actual_type}" >&2
              errors=$((errors + 1))
            }
            ;;
          object)
            [ "$actual_type" != "object" ] && {
              echo "ERROR: Field '${prop}' expected type object, got ${actual_type}" >&2
              errors=$((errors + 1))
            }
            ;;
        esac
      fi

      # Check string pattern constraint
      local pattern
      pattern=$(echo "$schema" | jq -r --arg f "$prop" '.properties[$f].pattern // ""' 2>/dev/null || echo "")
      if [ -n "$pattern" ] && [ "$expected_type" = "string" ]; then
        if ! echo "$value" | grep -qE "$pattern" 2>/dev/null; then
          echo "ERROR: Field '${prop}' value '${value}' does not match pattern '${pattern}'" >&2
          errors=$((errors + 1))
        fi
      fi

    done <<< "$properties"
  fi

  if [ "$errors" -gt 0 ]; then
    echo "ERROR: Schema validation failed with ${errors} error(s)" >&2
    return 1
  fi

  return 0
}

# validate_workspace_config — Specific validation for workspace.json
#
# Checks:
#   - Valid JSON
#   - Required fields: schemaVersion, workspaceId, createdAt
#   - schemaVersion must be 3
#   - workspaceId matches pattern ^[a-z0-9][a-z0-9-]{1,48}[a-z0-9]$
#   - If repos[] exists, each entry must have id and sourceRepo
#   - credentials.tokenSecretName should exist
#
# Args:
#   $1 - json_string (workspace.json content)
#
# Returns: 0 if valid, 1 if invalid
validate_workspace_config() {
  local json_string="${1:?ERROR: json_string is required}"

  echo "INFO: Validating workspace config..." >&2

  # Use schema validation
  if ! validate_schema "$json_string" "workspace.schema.json"; then
    return 1
  fi

  # Additional semantic checks

  # Check workspaceId format
  local ws_id
  ws_id=$(echo "$json_string" | jq -r '.workspaceId // ""' 2>/dev/null || echo "")
  if [ -n "$ws_id" ] && ! echo "$ws_id" | grep -qE '^[a-z0-9][a-z0-9-]{1,48}[a-z0-9]$'; then
    echo "ERROR: workspaceId '${ws_id}' does not match required pattern" >&2
    return 1
  fi

  # Check repos entries if present
  local repos_count
  repos_count=$(echo "$json_string" | jq '.repos | length // 0' 2>/dev/null || echo "0")
  if [ "$repos_count" -gt 0 ]; then
    local invalid_repos
    invalid_repos=$(echo "$json_string" | jq '[.repos[] | select(.id == null or .sourceRepo == null)] | length' 2>/dev/null || echo "0")
    if [ "$invalid_repos" -gt 0 ]; then
      echo "ERROR: ${invalid_repos} repo entries missing required 'id' or 'sourceRepo' fields" >&2
      return 1
    fi
  fi

  # Warn if no credentials
  local token_name
  token_name=$(echo "$json_string" | jq -r '.credentials.tokenSecretName // ""' 2>/dev/null || echo "")
  if [ -z "$token_name" ]; then
    echo "WARNING: No credentials.tokenSecretName defined in workspace config" >&2
  fi

  echo "OK: Workspace config is valid" >&2
  return 0
}

# validate_release_state — Specific validation for release-state.json
#
# Checks:
#   - Valid JSON
#   - Schema validation against release-state.schema.json
#   - version format X.Y.Z where patch <= 9
#   - status is a known value
#
# Args:
#   $1 - json_string (release-state.json content)
#
# Returns: 0 if valid, 1 if invalid
validate_release_state() {
  local json_string="${1:?ERROR: json_string is required}"

  echo "INFO: Validating release state..." >&2

  # Schema validation
  if ! validate_schema "$json_string" "release-state.schema.json"; then
    return 1
  fi

  # Check version format (X.Y.Z, patch <= 9)
  local version
  version=$(echo "$json_string" | jq -r '.version // ""' 2>/dev/null || echo "")
  if [ -n "$version" ]; then
    if ! echo "$version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
      echo "ERROR: Invalid version format: '${version}'. Expected X.Y.Z" >&2
      return 1
    fi

    local patch
    patch=$(echo "$version" | cut -d'.' -f3)
    if [ "$patch" -gt 9 ]; then
      echo "ERROR: Patch version ${patch} exceeds maximum (9). Version: ${version}" >&2
      return 1
    fi
  fi

  echo "OK: Release state is valid" >&2
  return 0
}

# --------------- Main (for testing) ---------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-help}" in
    json)
      if validate_json "${2:-}"; then
        echo "VALID JSON"
      else
        echo "INVALID JSON"
        exit 1
      fi
      ;;
    fields)
      json="${2:-}"
      shift 2 2>/dev/null || true
      if validate_required_fields "$json" "$@"; then
        echo "ALL FIELDS PRESENT"
      else
        exit 1
      fi
      ;;
    schema)
      if validate_schema "${2:-}" "${3:-}"; then
        echo "SCHEMA VALID"
      else
        exit 1
      fi
      ;;
    workspace)
      if validate_workspace_config "${2:-}"; then
        echo "WORKSPACE CONFIG VALID"
      else
        exit 1
      fi
      ;;
    release)
      if validate_release_state "${2:-}"; then
        echo "RELEASE STATE VALID"
      else
        exit 1
      fi
      ;;
    help|*)
      echo "Usage: $0 {json|fields|schema|workspace|release} [args...]"
      echo ""
      echo "Commands:"
      echo "  json <json_string>                         Validate JSON syntax"
      echo "  fields <json_string> <field1> [field2...]  Check required fields"
      echo "  schema <json_string> <schema_file>         Validate against schema"
      echo "  workspace <json_string>                    Validate workspace.json"
      echo "  release <json_string>                      Validate release-state.json"
      echo ""
      echo "Available schemas in ${SCHEMAS_DIR}/:"
      if [ -d "$SCHEMAS_DIR" ]; then
        ls "$SCHEMAS_DIR"/*.schema.json 2>/dev/null | xargs -I{} basename {} || echo "  (none)"
      fi
      ;;
  esac
fi
