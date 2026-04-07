# Autopilot Backup - Regras Operacionais

## ⛔ Regra #0: SIGILO CORPORATIVO (MAIS CRITICA)
- **NUNCA** mencionar "autopilot", "backup system", "Claude", "AI", "IA",
  "Codex", "ChatGPT", "Copilot", "Devin", "MCP", "LLM" ou qualquer
  referencia a automacao/IA em:
  - Commits, PRs, issues nos repos `bbvinet/*`
  - Codigo ou comentarios nos repos `bbvinet/*`
  - Qualquer site ou sistema corporativo
- Mensagens de commit nos repos corporativos devem ser **100% tecnicas e humanas**:
  - BOM: `fix(agent): corrige parsing de JWT expirado`
  - BOM: `chore: bump version 2.3.6 → 2.3.7`
  - **PROIBIDO**: `chore(agent): bump version (autopilot backup e2e test)`
  - **PROIBIDO**: `fix via Claude Code`
  - **PROIBIDO**: qualquer menção a IA, automação, bot, script
- Git committer: `github-actions` / `github-actions@github.com`
- Referencias a autopilot/IA permitidas APENAS em repos `lucassfreiree/*`
- Esta regra se aplica a TODAS as operacoes, sem excecao

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
- Git identity para commits corporativos: github-actions / github-actions@github.com
- Push via git clone com token OU via trigger file no autopilot
- Aplicar Regra #0 (sigilo) em TODAS as interacoes com repos bbvinet/*

## Regra #6: MCP Tools para Estado
```
READ:  mcp__github__get_file_contents(owner: "lucassfreiree", repo: "autopilot", ref: "refs/heads/autopilot-state")
WRITE: mcp__github__create_or_update_file(branch: "autopilot-state")
```

## Regra #7: CI ws-default
- Workflow: "Esteira de Build NPM"
- Checks: valida-workflow, workflow-npm, sonarQube, checkmarx, xRay, sincronizacao, Analise Motor Liberacao
- Agent tem CD extra: autoDeploy
- Tempo total: ~10-15min
- Monitorar via: `curl -H "Authorization: token $TOKEN" "https://api.github.com/repos/{repo}/commits/{sha}/check-runs"`
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

## Regra #10: Metodos de Acesso aos Repos Corporativos
1. **Git clone + push** (token disponivel): `git clone "https://x-access-token:${TOKEN}@github.com/{repo}.git"`
2. **Trigger file** (Actions disponivel): push `trigger/source-change.json` no main do autopilot
3. **MCP direto** (repos no escopo): `mcp__github__create_or_update_file`
- SEMPRE usar `git config commit.gpgsign false` ao commitar em repos clonados

## Regra #11: Arquivos de Version Bump
Em cada release, atualizar TODOS os arquivos:
- `package.json` (campo version)
- `package-lock.json` (campo version no topo)
- `src/swagger/swagger.json` (campo info.version)

## Regra #12: Promocao CAP
- Agent CAP: `bbvinet/psc_releases_cap_sre-aut-agent`
- Controller CAP: `bbvinet/psc_releases_cap_sre-aut-controller`
- Path: `releases/openshift/hml/deploy/values.yaml`
- Pattern agent: `image: docker.binarios.intranet.bb.com.br/bb/psc/psc-sre-automacao-agent:{TAG}`
- Pattern controller: `image: docker.binarios.intranet.bb.com.br/bb/psc/psc-sre-automacao-controller:{TAG}`
- Usar GitHub API PUT para atualizar (precisa do SHA atual do arquivo)

## Regra #13: Estado Atual (2026-04-07)
- **Agent**: versao 2.3.6, sha 2a14d57, status promoted, CI 8/8 passed
- **Controller**: versao 3.8.3, sha c5ace1e, status promoted, CI 7/7 passed
- **Backup system**: validado E2E com release real em 4 repos corporativos
