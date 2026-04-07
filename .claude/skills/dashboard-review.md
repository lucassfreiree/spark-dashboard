---
name: dashboard-review
description: Review dashboard code quality, performance, and accessibility. Use before releases or after significant UI changes.
allowed-tools: Read, Bash, Grep, Glob
---

# Dashboard Review — Quality & Performance Audit

Comprehensive review of the Spark Dashboard codebase.

## Check 1: Bundle Size

```bash
npm run build 2>&1
# Check dist/ size
du -sh dist/
find dist/ -name '*.js' -exec du -sh {} \;
find dist/ -name '*.css' -exec du -sh {} \;
```

Target: total bundle under 500KB.

## Check 2: TypeScript Strict Compliance

```bash
npx tsc --noEmit --strict 2>&1
```

Zero errors required. Flag any `@ts-ignore`, `as any`, or `// @ts-expect-error`.

```bash
grep -rn '@ts-ignore\|as any\|@ts-expect-error' src/ || echo "Clean: no type bypasses"
```

## Check 3: Mock Data Detection

```bash
grep -rn 'mock\|Mock\|MOCK\|fake\|placeholder.*data' src/ --include='*.ts' --include='*.tsx' | grep -v 'mockData.ts' | grep -v 'node_modules'
```

Production code must NEVER reference mock data (except the mock file itself for dev).

## Check 4: Timezone Compliance

Verify all date rendering uses the Sao Paulo timezone converter:

```bash
grep -rn 'new Date\|Date.now\|toLocaleDateString\|toLocaleTimeString' src/ --include='*.ts' --include='*.tsx' | grep -v 'timezone-converter'
```

Any direct Date usage without timezone conversion is a bug.

## Check 5: Accessibility

```bash
# Check for missing alt attributes on images
grep -rn '<img' src/ --include='*.tsx' | grep -v 'alt='
# Check for missing aria labels on interactive elements
grep -rn '<button\|<a ' src/ --include='*.tsx' | grep -v 'aria-'
```

## Check 6: Component Reuse

Identify potential duplicate code:

```bash
# Find similar component patterns
grep -rn 'className="flex' src/components/pages/ --include='*.tsx' -l
```

## Output Format

```markdown
Dashboard Review — {date}

| Category | Score | Issues |
|----------|-------|--------|
| Bundle Size | {OK/WARN} | {size} |
| Type Safety | {OK/FAIL} | {N} errors |
| Mock Data | {OK/FAIL} | {N} references |
| Timezones | {OK/WARN} | {N} unprotected |
| Accessibility | {OK/WARN} | {N} missing |
| Code Reuse | {OK/INFO} | {suggestions} |

Overall: {PASS/NEEDS ATTENTION}
```
