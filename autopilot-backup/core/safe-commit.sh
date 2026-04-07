#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# safe-commit.sh — Rule #0 Enforcement
#
# Validates and generates commit messages for corporate repos (bbvinet/*).
# Ensures NO references to autopilot, AI, Claude, or any automation tools
# appear in commit messages, PR titles, or code comments.
#
# Usage:
#   source safe-commit.sh
#   validate_commit_msg "chore(agent): bump version 2.3.6 → 2.3.7"  # OK
#   validate_commit_msg "fix via Claude Code"                         # BLOCKED
#   generate_bump_msg "agent" "2.3.6" "2.3.7"                       # safe msg
#   generate_fix_msg "agent" "corrige parsing de JWT expirado"       # safe msg
#
# Can also run standalone:
#   ./safe-commit.sh validate "some commit message"
#   ./safe-commit.sh bump agent 2.3.6 2.3.7
#   ./safe-commit.sh fix agent "corrige parsing de JWT"
###############################################################################

# Blocked patterns (case-insensitive)
# These words MUST NEVER appear in corporate repo commits/PRs/comments
BLOCKED_PATTERNS=(
  "autopilot"
  "claude"
  "openai"
  "chatgpt"
  "copilot"
  "devin"
  "codex"
  "\\bai\\b"
  "\\bia\\b"
  "\\bbot\\b"
  "\\bllm\\b"
  "\\bmcp\\b"
  "automation"
  "automated"
  "auto-generated"
  "machine.learning"
  "artificial.intelligence"
  "backup.system"
  "control.plane"
)

# ---------------------------------------------------------------------------
# validate_commit_msg — Check if a message is safe for corporate repos
# Returns 0 if safe, 1 if blocked
# ---------------------------------------------------------------------------
validate_commit_msg() {
  local msg="$1"
  local msg_lower
  msg_lower=$(echo "$msg" | tr '[:upper:]' '[:lower:]')

  for pattern in "${BLOCKED_PATTERNS[@]}"; do
    if echo "$msg_lower" | grep -qiE "$pattern"; then
      echo "BLOCKED: Message contains forbidden pattern '${pattern}'" >&2
      echo "Message: ${msg}" >&2
      echo "" >&2
      echo "Rule #0: NEVER reference autopilot, AI, or automation in corporate repos." >&2
      return 1
    fi
  done

  echo "OK: Message is safe for corporate repos"
  return 0
}

# ---------------------------------------------------------------------------
# generate_bump_msg — Generate a safe version bump commit message
# ---------------------------------------------------------------------------
generate_bump_msg() {
  local component="$1"
  local old_version="$2"
  local new_version="$3"
  echo "chore(${component}): bump version ${old_version} → ${new_version}"
}

# ---------------------------------------------------------------------------
# generate_fix_msg — Generate a safe fix commit message
# ---------------------------------------------------------------------------
generate_fix_msg() {
  local component="$1"
  local description="$2"

  # Validate the description itself
  local desc_lower
  desc_lower=$(echo "$description" | tr '[:upper:]' '[:lower:]')
  for pattern in "${BLOCKED_PATTERNS[@]}"; do
    if echo "$desc_lower" | grep -qiE "$pattern"; then
      echo "ERROR: Description contains forbidden pattern '${pattern}'" >&2
      return 1
    fi
  done

  echo "fix(${component}): ${description}"
}

# ---------------------------------------------------------------------------
# generate_chore_msg — Generate a safe chore commit message
# ---------------------------------------------------------------------------
generate_chore_msg() {
  local description="$1"

  local desc_lower
  desc_lower=$(echo "$description" | tr '[:upper:]' '[:lower:]')
  for pattern in "${BLOCKED_PATTERNS[@]}"; do
    if echo "$desc_lower" | grep -qiE "$pattern"; then
      echo "ERROR: Description contains forbidden pattern '${pattern}'" >&2
      return 1
    fi
  done

  echo "chore: ${description}"
}

# ---------------------------------------------------------------------------
# generate_feat_msg — Generate a safe feature commit message
# ---------------------------------------------------------------------------
generate_feat_msg() {
  local component="$1"
  local description="$2"

  local desc_lower
  desc_lower=$(echo "$description" | tr '[:upper:]' '[:lower:]')
  for pattern in "${BLOCKED_PATTERNS[@]}"; do
    if echo "$desc_lower" | grep -qiE "$pattern"; then
      echo "ERROR: Description contains forbidden pattern '${pattern}'" >&2
      return 1
    fi
  done

  echo "feat(${component}): ${description}"
}

# ---------------------------------------------------------------------------
# Standalone CLI
# ---------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  CMD="${1:-help}"
  case "$CMD" in
    validate)
      validate_commit_msg "${2:?Usage: $0 validate \"message\"}"
      ;;
    bump)
      generate_bump_msg "${2:?component}" "${3:?old_version}" "${4:?new_version}"
      ;;
    fix)
      generate_fix_msg "${2:?component}" "${3:?description}"
      ;;
    chore)
      generate_chore_msg "${2:?description}"
      ;;
    feat)
      generate_feat_msg "${2:?component}" "${3:?description}"
      ;;
    help|*)
      echo "safe-commit.sh — Rule #0 Enforcement for Corporate Repos"
      echo ""
      echo "Usage:"
      echo "  $0 validate \"commit message\"              — Check if message is safe"
      echo "  $0 bump <component> <old> <new>            — Generate bump message"
      echo "  $0 fix <component> \"description\"           — Generate fix message"
      echo "  $0 chore \"description\"                     — Generate chore message"
      echo "  $0 feat <component> \"description\"          — Generate feat message"
      echo ""
      echo "Examples:"
      echo "  $0 validate \"chore(agent): bump version 2.3.6 → 2.3.7\"  # OK"
      echo "  $0 validate \"fix via Claude Code\"                         # BLOCKED"
      echo "  $0 bump agent 2.3.6 2.3.7"
      echo "  $0 fix agent \"corrige parsing de JWT expirado\""
      ;;
  esac
fi
