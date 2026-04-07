# CLAUDE.md - Spark Dashboard + Autopilot Backup

## Projeto

Este repositorio contem:
1. **Spark Dashboard** - React 19 + TypeScript + Vite dashboard para monitoramento CI/CD
2. **Autopilot Backup** - Sistema de backup do autopilot CI/CD control plane (Plano B sem GitHub Actions)

## Stack

- React 19, TypeScript 6, Vite 6, Tailwind CSS 4
- shadcn/ui components, Recharts, Phosphor Icons
- Deploy: GitHub Pages via `deploy-dashboard.yml`

## Comandos

```bash
npm run dev      # Dev server
npm run build    # Build producao
npx tsc --noEmit # Type check (deve ter 0 erros)
```

## Regras do Dashboard

- NUNCA usar mock/fake data - apenas `public/state.json` real
- Todas as datas em timezone Sao Paulo (GMT-3)
- Dark theme por default
- Auto-refresh a cada 30s via `use-dashboard-data.ts`
- Bundle maximo: 500KB
- Path alias: `@/` -> `src/`

---

## AUTOPILOT BACKUP SYSTEM

### O que e

Sistema de backup completo do autopilot (`lucassfreiree/autopilot`) - control plane CI/CD que orquestra releases multi-workspace e multi-agente. Opera SEM GitHub Actions, usando GitHub MCP tools diretamente.

### Quando usar

- GitHub Actions indisponivel
- Operacoes urgentes de release/deploy
- Monitoramento de estado sem esperar workflows

### Localizacao

```
autopilot-backup/
  config.json          # Configuracao central
  core/                # 7 scripts do engine central
  operations/          # 24 scripts replicando workflows
  contracts/           # 16 contratos de agentes
  schemas/             # 13 schemas JSON
  triggers/            # Sistema de triggers local
  compliance/          # Regras de seguranca
```

### Repositorios envolvidos

| Repo | Funcao |
|------|--------|
| `lucassfreiree/autopilot` | Control plane principal |
| `lucassfreiree/spark-dashboard` | Dashboard + backup |
| `bbvinet/psc-sre-automacao-agent` | Codigo do Agent (corporativo) |
| `bbvinet/psc-sre-automacao-controller` | Codigo do Controller (corporativo) |
| `bbvinet/psc_releases_cap_sre-aut-agent` | Deploy CAP Agent |
| `bbvinet/psc_releases_cap_sre-aut-controller` | Deploy CAP Controller |

### Branches importantes

| Branch | Repo | Funcao |
|--------|------|--------|
| `main` | autopilot | Codigo fonte e workflows |
| `autopilot-state` | autopilot | Source of truth do estado |
| `autopilot-backups` | autopilot | Snapshots de backup |
| `main` | spark-dashboard | Dashboard + backup system |
| `gh-pages` | spark-dashboard | Deploy do dashboard |

### Workspaces

| ID | Empresa | Cliente | Status |
|----|---------|---------|--------|
| `ws-default` | Getronics | Banco do Brasil | **Ativo** |
| `ws-cit` | CIT | CIT | Setup |
| `ws-corp-1` | Corp 1 | - | Vazio |
| `ws-socnew` | SocNew/Matheus | - | Terceiro |

**REGRA CRITICA**: NUNCA assumir workspace default. Sempre identificar explicitamente.

### Estado atual (ws-default, 2026-04-07)

- **Agent**: SHA `9a48212`, tag `source-change`, status `ci-passed`
- **Controller**: tag `3.8.2`
- **Health**: `degraded` (1 lock ativo, drift warning)
- **Token**: `BBVINET_TOKEN` para repos corporativos

### Fluxo de Release (ws-default)

```
1. Resolver workspace -> ler workspace.json
2. Adquirir session lock (TTL 30min)
3. Ler release state atual
4. Ler package.json do repo corporativo
5. Bump version (regra 0-9: NUNCA patch >= 10)
6. Push package.json atualizado
7. Aguardar CI ("Esteira de Build NPM", ~14min)
8. Promover tag para CAP repo (values.yaml)
9. Atualizar release state no autopilot-state
10. Escrever audit entry
11. Liberar lock
```

### Versionamento

- **Patch**: 0-9 apenas. 2.1.9 -> 2.2.0 (NUNCA 2.1.10)
- **Tag format**: `{version}-{7char_sha}` (ex: 2.1.1-3a58260)
- **Script**: `autopilot-backup/core/version-bump.sh <patch|minor|major>`

### Core Engine (7 scripts em `autopilot-backup/core/`)

| Script | Funcao | Pode rodar offline |
|--------|--------|-------------------|
| `state-manager.sh` | CRUD no branch autopilot-state | Parcial (precisa MCP) |
| `session-guard.sh` | Locks multi-agente (TTL) | Parcial (logica local OK) |
| `audit-writer.sh` | Audit trail de operacoes | Parcial (precisa MCP) |
| `version-bump.sh` | Bump semver com regra 0-9 | **SIM (100% local)** |
| `workspace-resolver.sh` | Identificar workspace | Parcial |
| `trigger-engine.sh` | Triggers sem Actions | **SIM (100% local)** |
| `schema-validator.sh` | Validacao JSON vs schemas | **SIM (100% local)** |

### Operations (24 scripts em `autopilot-backup/operations/`)

**Release Pipeline**: release-agent.sh, release-controller.sh, promote-cap.sh, release-freeze.sh, release-approval.sh

**Corporate Repo**: apply-source-change.sh, fetch-files.sh, clone-corporate-repos.sh

**CI Operations**: ci-status-check.sh, ci-diagnose.sh, fix-corporate-ci.sh, ci-monitor-loop.sh, ci-self-heal.sh

**State Management**: backup-state.sh, restore-state.sh, bootstrap.sh, seed-workspace.sh, workspace-lock-gc.sh, health-check.sh

**Agent Coordination**: agent-bridge.sh, agent-handoff.sh

**Dashboard**: sync-spark-dashboard.sh, collect-state.sh, deploy-panel.sh, post-deploy-validation.sh, post-merge-monitor.sh

### Como operar via MCP

**Ler estado**:
```
mcp__github__get_file_contents(
  owner: "lucassfreiree",
  repo: "autopilot",
  path: "state/workspaces/ws-default/workspace.json",
  ref: "refs/heads/autopilot-state"
)
```

**Escrever estado**:
```
mcp__github__create_or_update_file(
  owner: "lucassfreiree",
  repo: "autopilot",
  path: "state/workspaces/ws-default/<file>.json",
  content: "<json>",
  message: "state: <description>",
  branch: "autopilot-state"
)
```

### Regras NAO NEGOCIAVEIS

1. **NUNCA** misturar workspaces
2. **NUNCA** assumir workspace default
3. **SEMPRE** adquirir lock antes de operacoes de estado
4. **SEMPRE** escrever audit entry apos mutacoes
5. **NUNCA** armazenar secrets nos repos
6. **NUNCA** patch >= 10 (overflow para minor)
7. Branch `autopilot-state` e a fonte de verdade
8. **NUNCA** usar regex para editar YAML - usar tooling estruturado
9. **SEMPRE** validar JSON antes de escrever no state
10. **SEMPRE** liberar lock em bloco finally

### CI Corporativo (ws-default)

- Workflow: "Esteira de Build NPM"
- Sucesso: ~14 min
- Falha: ~4 min
- Erros conhecidos: ESLint (no-nested-ternary, object-shorthand), Jest mocks
- Politica: Proceder com deploy se falhas sao conhecidas

### Agentes registrados

| Agente | Funcao |
|--------|--------|
| Claude Code | Arquitetura, code review, release orchestration |
| Codex | Implementacao, bulk changes, CI monitoring |
| ChatGPT | Implementacao, refactoring, testes |
| Copilot | Workflow dispatch, PR review |
| Devin | Tarefas especializadas |

### Session Lock Format

```json
{
  "schemaVersion": 1,
  "lockedBy": "claude-code",
  "operation": "release-agent",
  "acquiredAt": "2026-04-07T18:00:00Z",
  "expiresAt": "2026-04-07T18:30:00Z",
  "ttlMinutes": 30
}
```

Path: `state/workspaces/{ws_id}/locks/session-lock.json`
TTL: 30 min default, 120 min max

### Testes validados (2026-04-07)

- version-bump.sh: 6/6 cenarios passaram (patch, overflow, minor, major, invalid, double overflow)
- schema-validator.sh: 8/8 cenarios passaram (json valid/invalid, fields, workspace, release state)
- trigger-engine.sh: create, list, map funcionando
- config.json: JSON valido, 4 workspaces, repos corretos
- session-guard.sh: is-expired com datas passadas/futuras OK
- MCP real: workspace.json, agent-release-state, health.json lidos com sucesso
