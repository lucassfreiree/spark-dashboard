# Autopilot Backup - Plano B sem GitHub Actions

Sistema de backup completo do autopilot CI/CD control plane. Opera sem depender de GitHub Actions, usando GitHub MCP tools ou API direta via Claude Code web sessions.

## Quando usar este sistema

- GitHub Actions esta indisponivel ou com problemas
- Precisa executar operacoes urgentes de release/deploy
- Quer monitorar estado do sistema sem esperar workflows

## Estrutura

```
autopilot-backup/
  config.json                 # Configuracao central
  core/                       # Engine central (7 scripts)
    state-manager.sh          # CRUD no state branch
    session-guard.sh          # Locks multi-agente
    audit-writer.sh           # Audit trail
    version-bump.sh           # Bump semver (0-9 rule)
    workspace-resolver.sh     # Resolver workspace
    trigger-engine.sh         # Triggers sem Actions
    schema-validator.sh       # Validacao JSON
  operations/                 # Replicas de workflows (24 scripts)
    release-agent.sh          # Release do agent
    release-controller.sh     # Release do controller
    promote-cap.sh            # Promover para CAP
    ci-status-check.sh        # Verificar CI
    health-check.sh           # Health check
    ...
  contracts/                  # Contratos de agentes (copia)
  schemas/                    # Schemas de validacao (copia)
  triggers/                   # Sistema de triggers local
    templates/                # Templates de trigger
    pending/                  # Triggers pendentes
    completed/                # Triggers processados
  compliance/                 # Regras de compliance
```

## Como usar via Claude Code

### 1. Health Check
```
Leia: autopilot-backup/operations/health-check.sh
Execute as instrucoes MCP descritas no script
```

### 2. Verificar status de CI
```
Leia: autopilot-backup/operations/ci-status-check.sh
Use mcp__github__list_commits para ver ultimo commit
Use mcp__github__get_commit para ver status de CI
```

### 3. Release completo (agent)
```
1. Leia workspace config: state/workspaces/ws-default/workspace.json
2. Adquira lock: session-guard.sh -> acquire_lock
3. Bump version: version-bump.sh
4. Push para repo corporativo
5. Aguarde CI: ci-status-check.sh
6. Promova para CAP: promote-cap.sh
7. Atualize state: state-manager.sh
8. Libere lock: session-guard.sh -> release_lock
```

### 4. Backup de estado
```
Leia: autopilot-backup/operations/backup-state.sh
Copia todo o branch autopilot-state para autopilot-backups
```

### 5. Freeze de releases
```
Leia: autopilot-backup/operations/release-freeze.sh
Bloqueia releases por workspace com motivo e duracao
```

## Regras Criticas

1. **NUNCA** misture workspaces - isolacao estrita por workspace_id
2. **NUNCA** assuma workspace default - sempre identifique explicitamente
3. **SEMPRE** adquira lock antes de operacoes de estado
4. **SEMPRE** escreva audit entry apos mutacoes
5. **NUNCA** armazene secrets nos repos
6. State branch (`autopilot-state`) e a fonte de verdade

## Workspaces

| ID | Empresa | Status |
|----|---------|--------|
| ws-default | Getronics/BB | Ativo |
| ws-cit | CIT | Setup |
| ws-corp-1 | Corp 1 | Vazio |
| ws-socnew | SocNew | Terceiro |

## Mapeamento: Workflow Original -> Script Backup

| Workflow (Actions) | Script Backup |
|-------------------|---------------|
| release-agent.yml | operations/release-agent.sh |
| release-controller.yml | operations/release-controller.sh |
| promote-cap.yml | operations/promote-cap.sh |
| ci-status-check.yml | operations/ci-status-check.sh |
| ci-diagnose.yml | operations/ci-diagnose.sh |
| fix-corporate-ci.yml | operations/fix-corporate-ci.sh |
| ci-monitor-loop.yml | operations/ci-monitor-loop.sh |
| ci-self-heal.yml | operations/ci-self-heal.sh |
| health-check.yml | operations/health-check.sh |
| backup-state.yml | operations/backup-state.sh |
| restore-state.yml | operations/restore-state.sh |
| bootstrap.yml | operations/bootstrap.sh |
| seed-workspace.yml | operations/seed-workspace.sh |
| workspace-lock-gc.yml | operations/workspace-lock-gc.sh |
| release-freeze.yml | operations/release-freeze.sh |
| release-approval.yml | operations/release-approval.sh |
| apply-source-change.yml | operations/apply-source-change.sh |
| fetch-files.yml | operations/fetch-files.sh |
| clone-corporate-repos.yml | operations/clone-corporate-repos.sh |
| agent-bridge.yml | operations/agent-bridge.sh |
| enqueue-agent-handoff.yml | operations/agent-handoff.sh |
| sync-spark-dashboard.yml | operations/sync-spark-dashboard.sh |
| deploy-panel.yml | operations/deploy-panel.sh |
| post-deploy-validation.yml | operations/post-deploy-validation.sh |
| post-merge-monitor.yml | operations/post-merge-monitor.sh |

## Versionamento

- Patch: 0-9 apenas (2.1.9 -> 2.2.0, NUNCA 2.1.10)
- Tag format: `{version}-{7char_sha}` (ex: 2.1.1-3a58260)
- Script: `core/version-bump.sh <patch|minor|major>`
