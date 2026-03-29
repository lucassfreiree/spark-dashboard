# Spark Dashboard — Copilot Instructions

This is the **Autopilot Dashboard** — a real-time operations monitor for the
`lucassfreiree/autopilot` CI/CD control plane.

## Architecture
- **Framework**: React + TypeScript + Vite + Tailwind + shadcn/ui
- **Data source**: `state.json` synced every 5 min by `spark-sync-state.yml` from autopilot repo
- **No backend**: Pure static app reading state.json
- **Timezone**: Sao Paulo (GMT-3) for all date displays

## Data Flow
```
autopilot repo (spark-sync-state.yml)
  -> reads release state, agent memory, workflows, PRs, corporate versions
  -> builds state.json v3
  -> pushes to this repo (public/state.json)
  -> Spark app fetches /state.json every 30s
```

## state.json Schema (v3)
The app reads these fields from state.json:
- `lastSync` - ISO timestamp of last sync
- `controller` / `agent` - version, status, ciResult, promoted, repo, capRepo, stack
- `pipeline` - status, lastRun, component, version, commitMessage, changesCount
- `agents.claude` - status, task, phase
- `agents.copilot` / `agents.codex` - sessionCount, lastSession, lessonsCount, sessions[]
- `sessionLock` - agentId, expiresAt, operation
- `corporateReal` - controller/agent: sourceVersion, capTag, drift, recentCommits[]
- `workspaces[]` - id, company, status, stack, versions, repos
- `recentWorkflows[]` - name, status, conclusion, url, branch
- `openPRs[]` - number, title, author, branch, draft, labels
- `lessonsLearned` - total, copilotLessons[], codexLessons[]
- `versionRules` - currentController, currentAgent, pattern, lastTriggerRun
- `knownErrors[]` - code, desc, fix
- `pipelineStages[]` - name, desc

## Pages
1. **Dashboard Overview** - versions, pipeline status, health score, active agent
2. **Analytics** - deploy frequency, success rate, trends
3. **Deploy History** - table of recent deploys from audit trail
4. **Agent Activity** - Claude/Copilot/Codex sessions and lessons
5. **Workflows** - recent GitHub Actions runs with status
6. **Pipeline Monitor** - 7-stage apply-source-change visualization

## Key Rules
1. NEVER show mock/fake data - only real state.json
2. Handle missing fields gracefully (state.json may have partial data)
3. All dates displayed in Sao Paulo timezone (GMT-3)
4. Dark mode by default
5. Auto-refresh every 30 seconds
6. Types in `src/types/dashboard.ts` MUST match state.json schema

## Files
- `src/types/dashboard.ts` - TypeScript types matching state.json v3
- `src/hooks/use-dashboard-data.ts` - Fetches state.json, auto-refreshes
- `src/App.tsx` - Main app with sidebar navigation
- `src/components/pages/` - One component per page
- `src/components/ui/` - shadcn/ui components
- `public/state.json` - Real data synced from autopilot

## What NOT to do
- No authentication (public dashboard)
- No backend/API (pure static)
- No hardcoded versions or data
- No mock data for production
- No corporate secrets or tokens
