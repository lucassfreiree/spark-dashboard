# Runbooks — Falhas Comuns do Autopilot Backup

## 1. CI Falhou Apos Version Bump

**Sintoma**: Version bump pushado, CI retorna `failure` em um ou mais checks.

**Diagnostico**:
```bash
# Ver quais checks falharam
curl -s -H "Authorization: token $BBVINET_TOKEN" \
  "https://api.github.com/repos/{repo}/commits/{sha}/check-runs" | \
  jq '[.check_runs[] | select(.conclusion=="failure") | {name, conclusion, output: .output.title}]'
```

**Acoes**:
1. **ESLint errors**: Verificar se sao pre-existentes. Se sim, proceder com deploy.
2. **Jest failures**: Verificar se testes foram afetados pelo bump. Geralmente nao.
3. **sonarQube/checkmarx**: Raramente falham por version bump. Verificar se pre-existente.
4. **workflow-npm (build)**: Se falhou, verificar se package-lock.json esta consistente.

**Rollback** (se necessario):
```bash
# Reverter version bump no repo corporativo
cd /tmp/corp-{component}
git revert HEAD --no-edit
git config commit.gpgsign false
git push "https://x-access-token:${BBVINET_TOKEN}@github.com/{repo}.git" main
```

**Atualizar state**:
```
# Via MCP: atualizar release state para "failed"
mcp__github__create_or_update_file(
  path="state/workspaces/{ws_id}/{component}-release-state.json",
  branch="autopilot-state",
  status="failed", ciResult="failure"
)
```

---

## 2. Token Expirado Mid-Release

**Sintoma**: Operacao falha com HTTP 401 ou "Bad credentials".

**Diagnostico**:
```bash
curl -s -H "Authorization: token $BBVINET_TOKEN" "https://api.github.com/user"
# Se retorna 401, token expirado
```

**Acoes**:
1. Solicitar novo token ao usuario
2. Exportar: `export BBVINET_TOKEN="ghp_novo_token..."`
3. Salvar: `echo "$BBVINET_TOKEN" > ~/.autopilot-token && chmod 600 ~/.autopilot-token`
4. **Continuar de onde parou** — verificar ultimo step completado no release state

**Continuacao**:
- Se parou no step 6 (push): Verificar se push foi feito (`git log` no repo)
- Se parou no step 7 (CI): Apenas continuar monitorando
- Se parou no step 8 (CAP): Executar promote-cap.sh manualmente
- Se parou no step 9 (state): Atualizar state manualmente via MCP

---

## 3. Lock Preso (Agente Crashou)

**Sintoma**: Novo release falha com "Lock held by X".

**Diagnostico**:
```
# Via MCP: ler lock atual
mcp__github__get_file_contents(
  path="state/workspaces/{ws_id}/locks/session-lock.json",
  ref="refs/heads/autopilot-state"
)
```

**Acoes**:
1. Verificar `lockedAt` e `ttlMinutes` — se expirado, o script deve override automaticamente
2. Se nao expirou mas agente crashou, liberar manualmente:

```
# Via MCP: escrever lock vazio
mcp__github__create_or_update_file(
  path="state/workspaces/{ws_id}/locks/session-lock.json",
  branch="autopilot-state",
  content='{"lockedBy":null,"operation":null,"releasedAt":"<now>","releasedBy":"manual-override"}'
)
```

3. Escrever audit entry explicando o override manual

---

## 4. State Branch Corrompido

**Sintoma**: JSON invalido no state branch, ou campos faltando.

**Diagnostico**:
```
# Via MCP: tentar ler o arquivo
mcp__github__get_file_contents(
  path="state/workspaces/{ws_id}/workspace.json",
  ref="refs/heads/autopilot-state"
)
# Se JSON invalido, estado corrompido
```

**Acoes**:
1. **Restaurar de backup**:
   ```
   # Ler do branch autopilot-backups
   mcp__github__get_file_contents(
     path="state/workspaces/{ws_id}/workspace.json",
     ref="refs/heads/autopilot-backups"
   )
   # Copiar para autopilot-state
   ```

2. **Reconstruir manualmente**: Se backup tambem corrompido, reconstruir estado a partir dos repos corporativos:
   - Ler `package.json` de cada repo para obter versao atual
   - Ler ultimo commit SHA
   - Reconstruir release-state.json

3. **Validar apos restauracao**:
   ```bash
   # Usar schema-validator.sh
   bash autopilot-backup/core/schema-validator.sh validate_workspace_config <json>
   ```

---

## 5. CAP Promotion Falhou

**Sintoma**: values.yaml nao foi atualizado no CAP repo.

**Diagnostico**:
```bash
# Verificar estado atual do values.yaml
curl -s -H "Authorization: token $BBVINET_TOKEN" \
  "https://api.github.com/repos/{cap_repo}/contents/releases/openshift/hml/deploy/values.yaml" | \
  jq -r '.content' | base64 -d | grep "image:"
```

**Acoes**:
1. Verificar se tem permissao de push no CAP repo
2. Retry manual:
   ```bash
   # Ler SHA atual do values.yaml
   SHA=$(curl -s -H "Authorization: token $BBVINET_TOKEN" \
     "https://api.github.com/repos/{cap_repo}/contents/releases/openshift/hml/deploy/values.yaml" | \
     jq -r '.sha')
   
   # Ler conteudo, substituir tag, push
   CONTENT=$(curl -s -H "Authorization: token $BBVINET_TOKEN" \
     "https://api.github.com/repos/{cap_repo}/contents/releases/openshift/hml/deploy/values.yaml" | \
     jq -r '.content' | base64 -d)
   
   UPDATED=$(echo "$CONTENT" | sed "s|psc-sre-automacao-{component}:.*|psc-sre-automacao-{component}:{new_tag}|")
   
   curl -s -X PUT -H "Authorization: token $BBVINET_TOKEN" \
     "https://api.github.com/repos/{cap_repo}/contents/releases/openshift/hml/deploy/values.yaml" \
     -d "{\"message\":\"chore(release): {component} → {version}\",\"content\":\"$(echo "$UPDATED" | base64 -w0)\",\"sha\":\"$SHA\",\"branch\":\"main\"}"
   ```

3. Atualizar release state com `promoted: true` apos sucesso

---

## 6. GitHub API Rate Limit

**Sintoma**: HTTP 403 com mensagem "rate limit exceeded".

**Diagnostico**:
```bash
curl -s -H "Authorization: token $BBVINET_TOKEN" "https://api.github.com/rate_limit" | \
  jq '.resources.core | {limit, remaining, reset: (.reset | todate)}'
```

**Acoes**:
1. Aguardar reset (campo `reset` mostra quando)
2. Se urgente, usar git clone em vez de API calls
3. Rate limit para PAT: 5000 req/h — geralmente suficiente

---

## 7. package-lock.json Dessincronizado

**Sintoma**: Build falha porque package-lock.json tem versao diferente do package.json.

**Acoes**:
1. Atualizar TODOS os 3 arquivos de versao:
   - `package.json`
   - `package-lock.json` (campo `version` no topo)
   - `src/swagger/swagger.json` (campo `info.version`)
2. Sempre usar o mesmo valor de versao nos 3 arquivos

---

## 8. Git Push Falha com "gpg failed to sign"

**Sintoma**: `error: gpg failed to sign the data` ao commitar.

**Fix**:
```bash
git config commit.gpgsign false
```

Isso e necessario no ambiente de execucao do backup system. Sempre aplicar antes de commitar em repos clonados.
