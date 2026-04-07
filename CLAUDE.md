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

### Release E2E Real Validado (2026-04-07)

**Primeiro release completo executado 100% via backup system, sem GitHub Actions.**

#### O que foi feito:
1. Clone dos repos corporativos via `git clone` com `BBVINET_TOKEN`
2. Version bump em 3 arquivos (package.json, package-lock.json, swagger.json)
3. Push para `main` dos repos corporativos
4. Monitoramento de CI corporativa via GitHub API (`/commits/{sha}/check-runs`)
5. Promocao CAP: atualizacao de `values.yaml` nos repos de deploy via API
6. Atualizacao do release state no branch `autopilot-state`
7. Escrita de audit entry

#### Resultado:
| Componente | Versao | CI Checks | CAP |
|-----------|--------|-----------|-----|
| Agent | 2.3.5 → 2.3.6 | 8/8 passed | `agent:2.3.6` |
| Controller | 3.8.2 → 3.8.3 | 7/7 passed | `controller:3.8.3` |

#### Repos tocados:
- `bbvinet/psc-sre-automacao-agent` — version bump push
- `bbvinet/psc-sre-automacao-controller` — version bump push
- `bbvinet/psc_releases_cap_sre-aut-agent` — image tag atualizada
- `bbvinet/psc_releases_cap_sre-aut-controller` — image tag atualizada
- `lucassfreiree/autopilot` (autopilot-state) — release state + audit

#### Arquivos que precisam de bump em cada release:
- `package.json` (versao principal)
- `package-lock.json` (versao no topo)
- `src/swagger/swagger.json` (campo `info.version`)

### Como executar um release via backup system

#### Pre-requisitos:
- Token com acesso aos repos corporativos (ex: `BBVINET_TOKEN`)
- Acesso MCP ao `lucassfreiree/autopilot` para state/audit

#### Metodo 1: Git Clone + Push (token disponivel)
```bash
# 1. Exportar token
export BBVINET_TOKEN="ghp_xxx..."

# 2. Clonar repo
git clone "https://x-access-token:${BBVINET_TOKEN}@github.com/bbvinet/psc-sre-automacao-agent.git" /tmp/corp-agent

# 3. Configurar git identity
cd /tmp/corp-agent
git config commit.gpgsign false
git config user.name "github-actions"
git config user.email "github-actions@github.com"

# 4. Bump version (usar version-bump.sh ou sed)
sed -i 's/"version": "X.Y.Z"/"version": "X.Y.W"/g' package.json package-lock.json
sed -i 's/"version": "OLD"/"version": "X.Y.W"/' src/swagger/swagger.json

# 5. Commit e push
git add -A && git commit -m "chore(agent): bump version X.Y.Z → X.Y.W"
git push "https://x-access-token:${BBVINET_TOKEN}@github.com/bbvinet/psc-sre-automacao-agent.git" main

# 6. Monitorar CI
curl -s -H "Authorization: token $BBVINET_TOKEN" \
  "https://api.github.com/repos/bbvinet/psc-sre-automacao-agent/commits/{SHA}/check-runs" | \
  jq '[.check_runs[] | {name, status, conclusion}]'

# 7. Promover CAP (atualizar values.yaml)
# Ler values.yaml atual, substituir tag, push via API

# 8. Atualizar state via MCP
# mcp__github__create_or_update_file no autopilot-state
```

#### Metodo 2: Trigger File (GitHub Actions disponivel)
```
# Push trigger/source-change.json no branch main do autopilot
# O workflow apply-source-change.yml faz tudo automaticamente
```

#### Metodo 3: MCP Direto (repos no escopo MCP)
```
# Se os repos bbvinet/* estiverem no escopo MCP da sessao,
# usar mcp__github__create_or_update_file diretamente
```

### CI Corporativa — Checks Conhecidos

| Check | Componente | Tempo Medio |
|-------|-----------|-------------|
| `CI / valida-workflow` | Ambos | ~30s |
| `CI / workflow-npm` (Esteira de Build NPM) | Ambos | ~5-8min |
| `CI / sonarQube` | Ambos | ~3min |
| `CI / checkmarx` | Ambos | ~2min |
| `CI / xRay` | Ambos | ~5min |
| `CI / sincronizacao` | Ambos | ~1min |
| `CI / Análise Motor Liberação` | Ambos | ~2min |
| `CD (desenvolvimento) / autoDeploy` | Agent | ~3min |

**Tempo total**: ~10-15min do push ate todos os checks completarem

### Monitoramento de CI via API

```bash
# Verificar status de todos os checks de um commit
curl -s -H "Authorization: token $TOKEN" \
  "https://api.github.com/repos/{owner}/{repo}/commits/{sha}/check-runs" | \
  jq '{total: .total_count,
       completed: [.check_runs[] | select(.status=="completed")] | length,
       success: [.check_runs[] | select(.conclusion=="success")] | length,
       failed: [.check_runs[] | select(.conclusion=="failure")] | length}'
```

### Promocao CAP via API

```bash
# 1. Ler values.yaml atual
CONTENT=$(curl -s -H "Authorization: token $TOKEN" \
  "https://api.github.com/repos/{cap_repo}/contents/{path}" | jq -r '.content' | base64 -d)
SHA=$(curl -s -H "Authorization: token $TOKEN" \
  "https://api.github.com/repos/{cap_repo}/contents/{path}" | jq -r '.sha')

# 2. Substituir tag da imagem
UPDATED=$(echo "$CONTENT" | sed 's|psc-sre-automacao-{component}:OLD|psc-sre-automacao-{component}:NEW|g')

# 3. Push atualizado
curl -s -X PUT -H "Authorization: token $TOKEN" \
  "https://api.github.com/repos/{cap_repo}/contents/{path}" \
  -d '{"message":"chore(release): {component} → {version}","content":"'$(echo "$UPDATED" | base64 -w0)'","sha":"'$SHA'","branch":"main"}'
```
