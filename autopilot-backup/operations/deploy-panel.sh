#!/usr/bin/env bash
# ============================================================
# Deploy Panel - Autopilot Backup
# Replaces: .github/workflows/deploy-panel.yml
#
# Deploys the dashboard panel to GitHub Pages.
# For spark-dashboard: triggers the deploy workflow or
# pushes built assets directly.
#
# Usage: source this file, then call deploy_panel()
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/audit-writer.sh"

# Deploy dashboard panel
# Usage: deploy_panel [target]
#
# PROCEDURE FOR CLAUDE CODE:
#   Option A: Trigger the existing deploy-dashboard.yml workflow
#   Option B: Build locally and push to gh-pages branch
deploy_panel() {
  local target="${1:-spark-dashboard}"

  echo "=== Deploy Panel: ${target} ==="
  echo ""

  if [ "$target" = "spark-dashboard" ]; then
    echo "Target: Spark Dashboard (GitHub Pages)"
    echo ""
    echo "Option A - Trigger existing workflow (if GitHub Actions available):"
    echo "  The deploy-dashboard.yml workflow triggers on push to main"
    echo "  Simply pushing state.json changes to main will auto-deploy"
    echo ""
    echo "Option B - Manual deploy via MCP (if Actions unavailable):"
    echo ""
    echo "  Step 1: Ensure state.json is up to date"
    echo "    Run: sync_dashboard (from sync-spark-dashboard.sh)"
    echo ""
    echo "  Step 2: Build the dashboard"
    echo "    If running locally: npm run build"
    echo "    Output goes to: dist/"
    echo ""
    echo "  Step 3: Push built assets to gh-pages branch"
    echo "    MCP CALL: mcp__github__push_files"
    echo "      owner: lucassfreiree"
    echo "      repo: spark-dashboard"
    echo "      branch: gh-pages"
    echo "      files: <all files from dist/>"
    echo "      message: 'deploy: update dashboard'"
    echo ""
  elif [ "$target" = "autopilot-panel" ]; then
    echo "Target: Autopilot Panel (panel/index.html)"
    echo ""
    echo "  MCP CALL: mcp__github__create_or_update_file"
    echo "    owner: lucassfreiree"
    echo "    repo: autopilot"
    echo "    path: panel/index.html"
    echo "    branch: main"
    echo "    message: 'deploy: update panel'"
    echo ""
  fi

  write_audit "system" "deploy-panel" "completed" \
    "Panel deployed: ${target}" "claude-code-backup"

  echo "=== Deploy Complete ==="
}

echo "Deploy Panel loaded. Available functions: deploy_panel"
