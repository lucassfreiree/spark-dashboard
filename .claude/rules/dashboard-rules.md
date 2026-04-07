# Spark Dashboard — Claude Code Rules

## Data Rules
1. **NEVER use mock/fake data** — only real state.json in production
2. **Handle missing fields gracefully** — state.json may be partial
3. **All dates in Sao Paulo timezone** (GMT-3) via `src/lib/timezone-converter.ts`
4. **Types MUST match state.json v3 schema** — `src/types/dashboard.ts` is the contract

## Code Rules
1. **React 19 + TypeScript strict mode** — no `any` types, no `@ts-ignore`
2. **Tailwind CSS** — no inline styles, use design tokens from `tailwind.config.js`
3. **shadcn/ui components** — always check `src/components/ui/` before creating new ones
4. **Dark theme by default** — all new components must support dark mode
5. **Auto-refresh every 30s** — use `use-dashboard-data.ts` hook, never manual fetch

## Architecture Rules
1. **No backend/API** — pure static client-side app
2. **No authentication** — public dashboard
3. **No external CDN** — all dependencies bundled via Vite
4. **Data source**: `public/state.json` synced from autopilot repo every 5-15min
5. **Path alias**: use `@/` for imports (maps to `src/`)

## Performance Rules
1. **Keep bundle under 500KB** — monitor with `npm run build`
2. **Lazy load pages** — use React.lazy for route-level code splitting
3. **No unnecessary re-renders** — use React.memo for expensive components

## Before Every Commit
1. Run `npx tsc --noEmit` — zero type errors allowed
2. Run `npm run build` — must build successfully
3. Verify no mock data references in production code
