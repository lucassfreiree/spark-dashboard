#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# fetch-files.sh
# Replaces: .github/workflows/fetch-files.yml
#
# Fetches files from corporate repos via GitHub API / MCP tools.
# Supports reading single or multiple files in one invocation.
#
# Usage:
#   # Single file
#   ./fetch-files.sh --repo bbvinet/psc-sre-automacao-agent --path package.json
#
#   # Multiple files
#   ./fetch-files.sh --repo bbvinet/psc-sre-automacao-agent \
#     --path package.json \
#     --path src/main.ts \
#     --path tsconfig.json
#
#   # Specific branch
#   ./fetch-files.sh --repo bbvinet/psc-sre-automacao-agent \
#     --branch develop --path package.json
#
#   # Output to directory
#   ./fetch-files.sh --repo bbvinet/psc-sre-automacao-agent \
#     --path package.json --output-dir /tmp/fetched
#
#   # JSON output mode
#   ./fetch-files.sh --repo bbvinet/psc-sre-automacao-agent \
#     --path package.json --path tsconfig.json --json
#
# Options:
#   --workspace <ws_id>     Workspace ID (default: ws-default)
#   --repo <owner/repo>     Repository to fetch from (required)
#   --branch <branch>       Branch to read from (default: main)
#   --path <file_path>      File path to fetch (can be repeated)
#   --output-dir <dir>      Write files to this directory (default: stdout)
#   --json                  Output as JSON array [{path, content}...]
#
# MCP tools used:
#   - mcp__github__get_file_contents(owner, repo, path, branch)
#     For each file path, calls get_file_contents to retrieve content.
#     Returns base64-decoded file content or directory listing for dirs.
#
# Trigger file equivalent: trigger/fetch-files.json
#   {
#     "workspace_id": "ws-default",
#     "repo": "bbvinet/psc-sre-automacao-agent",
#     "branch": "main",
#     "files": ["package.json", "src/main.ts"]
#   }
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source core modules (for config access)
source "${SCRIPT_DIR}/../core/state-manager.sh"

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
WORKSPACE_ID="${WORKSPACE_ID:-ws-default}"
REPO=""
BRANCH="main"
declare -a FILE_PATHS=()
OUTPUT_DIR=""
JSON_OUTPUT=false

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace)   WORKSPACE_ID="$2"; shift 2 ;;
    --repo)        REPO="$2"; shift 2 ;;
    --branch)      BRANCH="$2"; shift 2 ;;
    --path)        FILE_PATHS+=("$2"); shift 2 ;;
    --output-dir)  OUTPUT_DIR="$2"; shift 2 ;;
    --json)        JSON_OUTPUT=true; shift ;;
    *) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
  esac
done

# Validate required arguments
if [[ -z "$REPO" ]]; then
  echo "ERROR: --repo is required (e.g., --repo bbvinet/psc-sre-automacao-agent)" >&2
  exit 1
fi

if [[ ${#FILE_PATHS[@]} -eq 0 ]]; then
  echo "ERROR: At least one --path is required" >&2
  exit 1
fi

OWNER=$(echo "$REPO" | cut -d/ -f1)
REPO_NAME=$(echo "$REPO" | cut -d/ -f2)

# Create output directory if specified
if [[ -n "$OUTPUT_DIR" ]]; then
  mkdir -p "$OUTPUT_DIR"
fi

# ---------------------------------------------------------------------------
# Fetch a single file
# MCP: mcp__github__get_file_contents(
#   owner=<owner>,
#   repo=<repo>,
#   path=<file_path>,
#   branch=<branch>)
#
# Returns decoded file content on stdout.
# For directories, returns listing prefixed with [DIRECTORY].
# ---------------------------------------------------------------------------
fetch_single_file() {
  local file_path="$1"
  local content=""

  echo "[fetch-files] Fetching: ${REPO}/${file_path} (branch: ${BRANCH})..." >&2

  if command -v gh &>/dev/null; then
    # Try as file first
    content=$(gh api "repos/${OWNER}/${REPO_NAME}/contents/${file_path}?ref=${BRANCH}" \
      --jq '.content' 2>/dev/null | base64 -d 2>/dev/null || echo "")

    # If empty, check if it is a directory
    if [[ -z "$content" ]]; then
      local dir_listing
      dir_listing=$(gh api "repos/${OWNER}/${REPO_NAME}/contents/${file_path}?ref=${BRANCH}" \
        --jq 'if type == "array" then [.[].name] | join("\n") else empty end' 2>/dev/null || echo "")

      if [[ -n "$dir_listing" ]]; then
        echo "[fetch-files] ${file_path} is a directory. Contents:" >&2
        echo "$dir_listing" >&2
        content="[DIRECTORY]
${dir_listing}"
      fi
    fi
  else
    echo "ERROR: gh CLI not available. Use MCP tool call in Claude Code session." >&2
    echo "[fetch-files] MCP call needed:" >&2
    echo "  mcp__github__get_file_contents(" >&2
    echo "    owner=\"${OWNER}\"," >&2
    echo "    repo=\"${REPO_NAME}\"," >&2
    echo "    path=\"${file_path}\"," >&2
    echo "    branch=\"${BRANCH}\"" >&2
    echo "  )" >&2
    return 1
  fi

  if [[ -z "$content" ]]; then
    echo "[fetch-files] WARNING: Empty or missing file: ${file_path}" >&2
    return 1
  fi

  echo "[fetch-files] Fetched ${file_path} ($(echo "$content" | wc -c) bytes)" >&2
  echo "$content"
}

# ---------------------------------------------------------------------------
# Main: Fetch all requested files
# ---------------------------------------------------------------------------
main() {
  echo "[fetch-files] Fetching ${#FILE_PATHS[@]} file(s) from ${REPO} (branch: ${BRANCH})" >&2

  local success_count=0
  local fail_count=0
  local json_results="[]"

  for file_path in "${FILE_PATHS[@]}"; do
    local content
    if content=$(fetch_single_file "$file_path"); then
      success_count=$((success_count + 1))

      if [[ -n "$OUTPUT_DIR" ]]; then
        # Write to output directory, preserving path structure
        local output_path="${OUTPUT_DIR}/${file_path}"
        mkdir -p "$(dirname "$output_path")"
        echo "$content" > "$output_path"
        echo "[fetch-files] Written to: ${output_path}" >&2
      elif [[ "$JSON_OUTPUT" == "true" ]]; then
        # Accumulate JSON array
        json_results=$(echo "$json_results" | jq \
          --arg path "$file_path" \
          --arg content "$content" \
          '. + [{path: $path, content: $content}]')
      else
        # Print to stdout with separator
        echo "=== ${file_path} ==="
        echo "$content"
        echo ""
      fi
    else
      fail_count=$((fail_count + 1))
      if [[ "$JSON_OUTPUT" == "true" ]]; then
        json_results=$(echo "$json_results" | jq \
          --arg path "$file_path" \
          '. + [{path: $path, content: null, error: "fetch failed"}]')
      fi
    fi
  done

  # Output JSON if requested
  if [[ "$JSON_OUTPUT" == "true" ]]; then
    echo "$json_results" | jq .
  fi

  echo "[fetch-files] Complete: ${success_count} succeeded, ${fail_count} failed" >&2

  if [[ $fail_count -gt 0 && $success_count -eq 0 ]]; then
    exit 1
  fi
}

main "$@"
