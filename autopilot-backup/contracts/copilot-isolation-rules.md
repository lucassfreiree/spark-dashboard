# Copilot Isolation Rules

> CRITICAL: These rules MUST be followed by ALL Copilot workflows and operations.

## Golden Rule
**Copilot workflows NEVER modify Claude's files. Claude workflows NEVER modify Copilot's files.**

## Copilot's files (Copilot CAN modify):
- `contracts/copilot-session-memory.json`
- `contracts/copilot-agent-contract.json`
- `.github/copilot-instructions.md` (via sync-copilot-prompt.yml only)
- `.github/workflows/copilot-post-deploy-sync.yml`
- `references/controller-cap/values.yaml` (version tag sync only)
- `references/agent-cap/values.yaml` (version tag sync only)

## Claude's files (Copilot MUST NOT modify):
- `contracts/claude-session-memory.json`
- `contracts/claude-agent-contract.json`
- `CLAUDE.md`
- `.claude/settings.json`
- All workflows created by Claude (apply-source-change.yml, ci-*.yml, etc.)

## DELETED WORKFLOWS (Copilot MUST NEVER recreate):
- `autonomous-pr-lane.yml` — DELETED. Was redundant. autonomous-merge-direct.yml handles everything.
- `auto-merge-to-main.yml` — DELETED. Was redundant. auto-merge-sweeper.yml handles everything.
- If these files reappear in the repo, it is a BUG. Delete them immediately.
- The ONLY merge workflows that should exist are:
  - `autonomous-merge-direct.yml` — PR event-based auto-merge
  - `auto-merge-sweeper.yml` — Cron-based backup sweeper (every 2 min)

## Shared files (BOTH can read, only designated owner writes):
- `trigger/source-change.json` — Claude writes, Copilot reads
- `state/workspaces/*/` — Written by workflows, both read

## Copilot's automated responsibilities:
1. Post-deploy sync (`copilot-post-deploy-sync.yml`)
2. Own memory updates (`copilot-session-memory.json`)
3. CAP reference sync (`references/*/values.yaml`)
4. Copilot instructions sync (`sync-copilot-prompt.yml`)

## Validation protocol (MANDATORY before any action):
1. **Before starting any task**: read `copilot-session-memory.json`, verify workspace, check locks
2. **Before committing/pushing**: validate patches compile (`tsc`), pass lint (`eslint`), pass tests (`jest`)
3. **Before merging**: ensure `validate-patches.yml` passed, `run` field incremented, version not duplicate
4. **After deploy**: monitor workflow AND corporate CI pipeline — do not assume success
