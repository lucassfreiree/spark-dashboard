---
name: validate-schema
description: Validate that TypeScript types in dashboard.ts match the state.json v3 schema. Use after schema changes in autopilot or before releases.
allowed-tools: Read, Bash, Grep, Glob, Edit
---

# Validate Schema — Type Safety Check

Ensure `src/types/dashboard.ts` stays in sync with the actual `state.json` v3 schema.

## Step 1: Read Current Types

Read `src/types/dashboard.ts` to get all TypeScript interfaces and types.

## Step 2: Read Actual State

Read `public/state.json` and extract its actual structure:
```bash
jq 'paths | map(tostring) | join(".")' public/state.json | head -100
```

## Step 3: Compare Structure

For each top-level key in state.json, verify:
1. A corresponding TypeScript type/interface exists
2. Field names match exactly (case-sensitive)
3. Field types are compatible (string, number, boolean, array, object)
4. Optional fields are marked with `?` in TypeScript
5. No extra fields in types that don't exist in state.json

## Step 4: Type Check

```bash
npx tsc --noEmit 2>&1
```

Report any type errors related to dashboard types.

## Step 5: Report

```markdown
Schema Validation Report
========================

state.json fields: N
TypeScript types: N interfaces

Matches: N/N fields ✓
Mismatches:
- {field}: state.json has {type}, TS expects {type}
- {field}: exists in state.json but missing in TS types
- {field}: exists in TS types but not in state.json

Type check: PASS/FAIL ({N} errors)

Action needed: {none / update types / update state.json}
```

## Auto-Fix

If mismatches are found and the fix is clear (e.g., missing optional field):
1. Add the missing field to the TypeScript interface with `?` (optional)
2. Re-run `npx tsc --noEmit` to verify
3. Report the fix applied
