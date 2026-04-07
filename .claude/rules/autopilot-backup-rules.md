# Autopilot Backup - Regras Operacionais

## Regra #1: Workspace Isolation
- NUNCA misturar workspaces - identificar workspace_id ANTES de qualquer operacao
- Se ambiguo: PERGUNTAR ao usuario
- Workspaces ativos: ws-default (Getronics/BB), ws-cit (CIT)

## Regra #2: Session Lock
- SEMPRE adquirir lock antes de operacoes que modificam estado
- TTL default: 30 min, max: 120 min
- Se outro agente tem lock: criar handoff em vez de forcar
- SEMPRE liberar lock no final (try/finally)

## Regra #3: State Branch
- Branch `autopilot-state` no repo `lucassfreiree/autopilot` e a fonte de verdade
- NUNCA confiar em memoria do agente - sempre ler estado fresco
- Validar JSON com schema-validator.sh antes de escrever
- Escrever audit entry apos cada mutacao

## Regra #4: Versionamento
- Patch vai de 0-9 APENAS
- 2.1.9 -> 2.2.0 (NUNCA 2.1.10)
- Tag format: {version}-{7char_sha}
- Usar core/version-bump.sh para calcular

## Regra #5: Repos Corporativos
- NUNCA armazenar codigo corporativo no autopilot
- NUNCA armazenar secrets (tokens, keys, kubeconfig)
- NUNCA push direto - usar workflows/scripts
- Git identity para commits corporativos: github-actions / github-actions@github.com

## Regra #6: MCP Tools para Estado
```
READ:  mcp__github__get_file_contents(owner: "lucassfreiree", repo: "autopilot", ref: "refs/heads/autopilot-state")
WRITE: mcp__github__create_or_update_file(branch: "autopilot-state")
```

## Regra #7: CI ws-default
- Workflow: "Esteira de Build NPM"
- Sucesso ~14min, falha ~4min
- Erros conhecidos: ESLint (no-nested-ternary, object-shorthand)
- Politica: Proceder se falhas sao pre-existentes

## Regra #8: Operacoes Manuais (3 gates)
1. release-freeze - requer confirmacao humana
2. corporate-release-approval - requer confirmacao humana
3. destructive-rollback - requer confirmacao humana

## Regra #9: Scripts do Backup
- Core engine: autopilot-backup/core/ (7 scripts)
- Operations: autopilot-backup/operations/ (24 scripts)
- Cada script documenta MCP calls necessarios
- version-bump.sh, trigger-engine.sh e schema-validator.sh rodam 100% local
