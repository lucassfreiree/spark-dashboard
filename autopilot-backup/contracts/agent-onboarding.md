# Autopilot Agent Onboarding Guide

> This guide enables ANY AI agent to operate the Autopilot control plane.
> Read this ENTIRELY before performing any operation.
> Last updated: 2026-03-29

## 1. What is Autopilot

Web-only CI/CD control plane that orchestrates deploys for corporate repos via GitHub Actions.
- **Repo**: `lucassfreiree/autopilot` (personal product)
- **State**: `autopilot-state` branch (runtime state, locks, audit)
- **Dashboard**: https://lucassfreiree.github.io/autopilot/dashboard/
- **Primary agent**: Claude Code (via CLI)
- **You are**: A pluggable agent operating via the universal agent registry

## 2. First Steps (MANDATORY)

### Step 1: Read your config
```
File: contracts/agent-registry.json
→ Find your agent entry in "agents" object
→ Note your branchPrefix, memoryFile, capabilities
```

### Step 2: Read system state
```
File: contracts/claude-session-memory.json
→ currentState: versions, lastTriggerRun
→ versioningRules: version pattern
→ deployFlow: how to deploy
```

### Step 3: Read workspace config
```
Branch: autopilot-state
File: state/workspaces/ws-default/workspace.json
→ repos, tokens, branches, paths
```

### Step 4: Check locks
```
Branch: autopilot-state
File: state/workspaces/ws-default/locks/session-lock.json
→ If agentId != "none" and not expired: STOP, create handoff
```

## 3. Multi-Company Model (CRITICAL)

| Workspace | Company | Status | Token |
|-----------|---------|--------|-------|
| ws-default | Getronics | active | BBVINET_TOKEN |
| ws-cit | CIT | setup | CIT_TOKEN |
| ws-socnew | SocNew | **LOCKED** | — |
| ws-corp-1 | Corp-1 | **LOCKED** | — |

**RULES**:
- NEVER assume a default workspace — identify from context
- NEVER mix data between companies
- ws-socnew and ws-corp-1 are THIRD-PARTY — do NOT operate

## 4. Corporate Repos (Getronics)

| Repo | Role |
|------|------|
| bbvinet/psc-sre-automacao-controller | Controller source (Node 22, TS) |
| bbvinet/psc-sre-automacao-agent | Agent source (Node 22, TS, K8s) |
| bbvinet/psc_releases_cap_sre-aut-controller | Controller K8s deploy |
| bbvinet/psc_releases_cap_sre-aut-agent | Agent K8s deploy |

**Access**: Only via workflows (BBVINET_TOKEN). NEVER push directly.

## 5. How to Make Changes

### To autopilot repo (docs, configs, memory):
```
1. Create branch: <your-prefix>/descriptive-name
2. Make changes
3. Commit + push
4. Create PR targeting main
5. Merge (squash) — auto-merge handles agent branches
```

### To corporate repos (code deploy):
```
1. Create patches in patches/ directory
2. Update trigger/source-change.json (increment run!)
3. Branch + PR + merge to main
4. apply-source-change.yml triggers automatically
5. Pipeline: Setup → Guard → Apply → CI Gate → Promote → State → Audit
```

## 6. Deploy Flow (Step by Step)

### Phase 1: Prepare
- Read trigger/source-change.json for current run number
- Decide new version (after X.Y.9 → X.(Y+1).0, NEVER X.Y.10)
- Create patches in patches/ (replace-file or search-replace)

### Phase 2: Version Bump (4 files)
1. package.json — search-replace version
2. package-lock.json — search-replace version (2 occurrences)
3. src/swagger/swagger.json — replace-file (ASCII only, NO accents!)
4. references/controller-cap/values.yaml — update image tag

### Phase 3: Configure Trigger
```json
{
  "workspace_id": "ws-default",
  "component": "controller",
  "change_type": "multi-file",
  "version": "X.Y.Z",
  "changes": [...],
  "commit_message": "feat: description",
  "run": LAST_RUN + 1
}
```
**CRITICAL: run MUST be incremented or workflow won't trigger**

### Phase 4: Commit + PR + Merge
All files in 1 commit → branch → PR → squash merge → workflow auto-triggers

### Phase 5: Monitor
- apply-source-change runs 7 stages
- ci-monitor-loop polls corporate CI every 2 min
- If CI passes: promote-cap updates CAP tag
- If CI fails: ci-diagnose + fix-corporate-ci auto-fix

## 7. Compliance Pipeline (4 Stages)

```
PR → compliance-gate.yml (14 checks) → apply-source-change (7 stages)
→ post-deploy-validation → deploy-auto-learn
```

### 14 Compliance Rules:
1. version-format (no X.Y.10+)
2. version-4-files (pkg, lock, swagger, cap)
3. swagger-ascii (no accented characters)
4. jwt-scope-singular (scope not scopes)
5. no-validate-in-fetch (breaks mock tests)
6. no-nested-ternary (ESLint rejects)
7. search-replace-newlines (sed can't handle)
8. run-not-incremented (workflow won't fire)
9. blocked-workspace (third-party isolation)
10. security-xss (sanitizeForOutput required)
11. security-ssrf (parseSafeIdentifier at input)
12. security-dos-loop (MAX_RESULTS limit)
13. hardcoded-secret (no secrets in patches)
14. use-before-define (function definition order)

## 8. Key Files Reference

| File | Purpose |
|------|---------|
| contracts/agent-registry.json | Universal agent config |
| contracts/claude-session-memory.json | Full project memory |
| contracts/shared-agent-contract.json | Shared rules for all agents |
| contracts/claude-live-status.json | Current Claude task/phase |
| trigger/source-change.json | Deploy trigger |
| CLAUDE.md | Complete project documentation |
| panel/dashboard/state.json | Dashboard data (auto-synced) |

## 9. Trigger Files

| Trigger | Workflow |
|---------|----------|
| trigger/source-change.json | apply-source-change.yml |
| trigger/fetch-files.json | fetch-files.yml |
| trigger/ci-diagnose.json | ci-diagnose.yml |
| trigger/ci-status.json | ci-status-check.yml |
| trigger/fix-ci.json | fix-corporate-ci.yml |
| trigger/promote-cap.json | promote-cap.yml |

## 10. Known Error Patterns

| Error | Fix |
|-------|-----|
| 403 on push | Branch must start with agent prefix |
| Trigger not firing | Increment run field |
| Duplicate tag | Increment version |
| ESLint no-use-before-define | Define functions before calling |
| ESLint no-nested-ternary | Use if/else |
| Swagger garbled | ASCII only, no accents |
| JWT scope wrong | Use 'scope' singular, never 'scopes' |
| search-replace fails | Use replace-file for multi-line |
| Mock tests broken | Don't add validateTrustedUrl in fetch |
| CI Gate false result | Read ci-logs-*.txt for real result |

## 11. How to Register a New Agent

1. Edit `contracts/agent-registry.json`
2. Copy `agentTemplate` into `agents` object with unique ID
3. Set `branchPrefix` (e.g., `gemini/`, `chatgpt/`, `cursor/`)
4. Add prefix to `branchPrefixes` array
5. Create memory file at path specified in `memoryFile`
6. Commit via PR from your branch prefix
7. Auto-merge will handle the PR

### Example: Register ChatGPT as backup
```json
"chatgpt": {
  "name": "ChatGPT",
  "status": "active",
  "role": "backup",
  "branchPrefix": "chatgpt/",
  "capabilities": ["code-implementation", "documentation"],
  "tools": "GitHub API",
  "memoryFile": "contracts/chatgpt-session-memory.json",
  "canPushToMain": false,
  "requiresPR": true,
  "autoMerge": true
}
```

## 12. Golden Rules

1. NEVER push directly to main (403)
2. ALWAYS use your assigned branch prefix
3. ALWAYS increment run field in triggers
4. NEVER mix workspace data
5. ALWAYS check session lock before state changes
6. NEVER modify another agent's memory files
7. ALWAYS monitor workflow after triggering
8. NEVER assume success — verify via API
9. After X.Y.9 → X.(Y+1).0 — NEVER X.Y.10
10. Corporate CI success ≠ deploy complete (build runs after)

## 13. Auth Architecture (Getronics)

- Controller authenticates via `x-techbb-namespace` + `x-techbb-service-account` headers (internal-origin)
- Or via JWT with `JWT_SECRET` (scope claim: singular `scope`, NEVER `scopes`)
- Trusted namespace: `sgh-oaas-playbook-jobs`
- Controller DNS: `sre-aut-controller.psc.k8shmlbb111b.bb.com.br`

## 14. Dashboard

- URL: https://lucassfreiree.github.io/autopilot/dashboard/
- Data: panel/dashboard/state.json (auto-synced every 5 min)
- Shows: versions, pipeline, agents, workspaces, workflows, PRs, lessons, errors, architecture
- Drift detection: compares autopilot state vs real corporate repo versions
