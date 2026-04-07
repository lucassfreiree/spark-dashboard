---
name: sync-dashboard
description: Sync the latest state.json from the autopilot repo and verify dashboard renders correctly. Use when dashboard data looks stale or after autopilot deploys.
allowed-tools: Read, Bash, Grep, Glob
---

# Sync Dashboard — Pull Latest State from Autopilot

Pull the latest state.json from autopilot and validate the dashboard.

## Step 1: Check Current State Freshness

```bash
jq -r '.lastSync' public/state.json
```

If lastSync is within 5 minutes, state is likely fresh. Report and skip sync unless forced.

## Step 2: Fetch Latest State

The state.json is synced automatically by `spark-sync-state.yml` in the autopilot repo.
To force a manual sync:

1. Check if autopilot repo has newer state:
   - Read `panel/dashboard/state.json` from autopilot repo (main branch)
   - Compare `lastSync` timestamps

2. If autopilot has newer data:
   - Copy the updated state.json to `public/state.json`
   - Validate with `jq '.' public/state.json`

## Step 3: Validate Dashboard Data

After sync, verify critical fields are present and accurate:

| Field | Check |
|-------|-------|
| `lastSync` | Within 15 minutes |
| `controller.version` | Matches format X.Y.Z |
| `agent.version` | Matches format X.Y.Z |
| `pipeline.status` | One of: idle, running, success, failed |
| `recentWorkflows[]` | Array with at least 1 entry |
| `openPRs[]` | Array (can be empty) |

## Step 4: Type Check

```bash
npx tsc --noEmit 2>&1
```

Ensure no type errors after state update.

## Step 5: Build Check

```bash
npm run build 2>&1
```

Ensure dashboard builds successfully with new data.

## Step 6: Report

```
Dashboard Sync Report
=====================
Previous sync: {old_timestamp}
Current sync: {new_timestamp}
Data freshness: {OK/STALE}

Validation:
  ✓ JSON valid
  ✓ Controller: v{version}
  ✓ Agent: v{version}
  ✓ Pipeline: {status}
  ✓ TypeScript: {pass/fail}
  ✓ Build: {pass/fail}

Status: {SYNCED/UP-TO-DATE/FAILED}
```
