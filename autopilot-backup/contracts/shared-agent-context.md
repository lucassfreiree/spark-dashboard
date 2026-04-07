# Autopilot Shared Agent Context
> This file is injected into ALL agent prompts (Claude, Codex, Copilot).
> It contains the essential context every agent needs to operate correctly.
> Last updated: 2026-04-04

## What is Autopilot
Web-only CI/CD control plane for multi-workspace, multi-agent release orchestration.
Repo: `lucassfreiree/autopilot` (personal product / future SaaS). State stored on `autopilot-state` branch.

## Multi-Company Model (CRITICAL)
Autopilot manages MULTIPLE COMPANIES from a single repo. Each workspace = one consultancy engagement (company + client). COMPLETELY ISOLATED.

### Consultancy Model
The owner (lucassfreiree) works as a consultant for multiple companies, each serving a different end-client (bank/financial institution).

| Company | Client (End-Customer) | Workspace | Stack | Token | Status | Start |
|---------|----------------------|-----------|-------|-------|--------|-------|
| **Getronics** | **Banco do Brasil** | `ws-default` | Node/TypeScript (NestJS) | `BBVINET_TOKEN` | **Active** (ctrl 3.8.2, agent 2.3.3) | 2025 |
| **CIT** | **Itau Unibanco** | `ws-cit` | DevOps (K8s, Terraform, Docker, IaC) | `CIT_TOKEN` | **Onboarding** (starts 2026-04-06) | Apr 2026 |

### Blocked Workspaces (Third-Party — DO NOT OPERATE)
| Workspace | Owner | Policy |
|-----------|-------|--------|
| `ws-socnew` | Third-party | LOCKED — requires explicit authorization |
| `ws-corp-1` | Third-party | LOCKED — requires explicit authorization |

### Context Identification Rules
Agents MUST identify workspace from conversation context BEFORE any operation:
- **Getronics/BB keywords**: getronics, banco do brasil, bb, bbvinet, controller, agent, nestjs, psc-sre, automacao, esteira, cap, hml
- **CIT/Itau keywords**: cit, itau, itaú, unibanco, devops, terraform, helm, argocd, ansible, k8s, kubernetes, docker, cloud, aws, azure, gcp
- **Ambiguous?** → ASK the user. Never assume.
- **Full rules**: `contracts/workspace-context-rules.json`

### Corporate Environment Rules (CRITICAL — Owner Directive)
**NEVER mention AI, artificial intelligence, Claude, GPT, LLM, or any AI tool in corporate-facing content.**
This includes: commit messages, PR titles/descriptions, issue titles, branch names, code comments pushed to corporate repos.
All work pushed to corporate repos (bbvinet/*, CIT repos) must appear as regular developer work.
Internal autopilot references (CLAUDE.md, session memory, contracts) are OK — they stay in the autopilot repo.

### Cross-Contamination Prevention
- NEVER reference BB data/repos in CIT context or vice-versa
- NEVER use BBVINET_TOKEN for CIT or CIT_TOKEN for Getronics
- NEVER mention AI in any corporate-facing content
- Dashboard uses color coding: green=Getronics/BB, orange=CIT/Itau, red=locked
- Every commit, issue, and PR for workspace-specific work MUST include workspace_id

## Current State (ws-default — Getronics/BB)
- **Controller version**: 3.8.2 (deployed and verified)
- **Agent version**: 2.3.3 (deployed and verified)
- **Last successful deploy run**: #103
- **Last trigger run**: 103
- **Pipeline status**: operational
- **Autopilot product version**: 1.0.3

## Current State (ws-cit — CIT/Itau)
- **Status**: Onboarding (starts 2026-04-06)
- **Repos**: Not yet configured
- **Token**: CIT_TOKEN (not yet available)
- **Ops environment**: Ready (scripts, runbooks, templates in ops/)
- **First tasks**: Receive repo access, configure token, map CI/CD pipelines

## Key Architecture
- **State branch**: `autopilot-state` (source of truth for all runtime state)
- **Deploy pipeline**: `apply-source-change.yml` (7 stages: Setup > Session Guard > Apply & Push > CI Gate > Promote > Save State > Audit)
- **Multi-agent safety**: `session-guard.yml` acquires locks before state changes
- **Agents**: Claude Code (primary), Codex (via codex-apply.yml), Copilot (dispatch/review)

## Deploy Flow (Mandatory Steps)
1. Fetch current corporate files via `fetch-files.yml`
2. Create minimal patches in `patches/` from CURRENT corporate base
3. Validate via `validate-patches.yml` (clone + npm ci + tsc + eslint + jest)
4. Update `trigger/source-change.json` (increment `run` field!)
5. Update `references/controller-cap/values.yaml` + session memory
6. Branch `claude/*` or `codex/*` > PR > squash merge to main
7. Workflow auto-triggers on merge (path: trigger/source-change.json)
8. Monitor workflow + corporate CI until Docker image published

## Versioning Rules
- Current: 3.6.3. Next: 3.6.4 (or 3.7.0 if after 3.6.9)
- Pattern: After X.Y.9 goes to X.(Y+1).0 - NEVER X.Y.10
- 4 files must be aligned: package.json, package-lock.json (2 places), swagger.json
- CI rejects duplicate tags - always check before bumping

## Git Rules
- NEVER push directly to main (403). Always branch + PR + squash merge
- Branch prefixes: `claude/*` for Claude, `codex/*` for Codex
- Always fetch origin/main before creating branch
- Trigger files: increment `run` field to dispatch workflow

## Trigger Files
| File | Workflow |
|------|----------|
| trigger/source-change.json | apply-source-change.yml |
| trigger/codex-commit.json | codex-apply.yml |
| trigger/agent-bridge.json | agent-bridge.yml |
| trigger/fetch-files.json | fetch-files.yml |
| trigger/ci-diagnose.json | ci-diagnose.yml |
| trigger/fix-ci.json | fix-corporate-ci.yml |
| trigger/full-test.json | test-full-flow.yml |
| trigger/improvement.json | continuous-improvement.yml |

## Codex-Specific: How to Commit Code
Codex can commit via `codex-apply.yml` workflow:
1. Edit `trigger/codex-commit.json` with task + bump run
2. Merge to main triggers the workflow
3. Workflow calls OpenAI API with structured prompt
4. Codex returns JSON: `{branch_name, commit_message, pr_title, changes: [{action, path, content}]}`
5. Workflow applies changes, creates `codex/*` branch, commits, opens PR
6. If `auto_merge: true`, squash merges automatically

## Known Failures & Fixes (Learn from Past Mistakes)
| Problem | Fix | Pattern |
|---------|-----|---------|
| Tag duplicada no registry | Incrementar patch version | `duplicate tag\|already exists` |
| TypeScript TS2769 jwt.sign | Use parseExpiresIn() with cast | `No overload matches` |
| ESLint no-use-before-define | Define functions BEFORE using them | `was used before it was defined` |
| Agent 401 internal-origin | Controller must mint JWT via mintInternalOriginJwt() | `Unauthorized` + internal-origin |
| JWT scope claim wrong | Agent reads `payload.scope` (singular), NEVER `scopes` | `Insufficient scope` |
| validateTrustedUrl in fetch | NEVER - breaks mock tests. Use parseSafeIdentifier on input | Test failures with mock URLs |
| CI Gate pre-existing bug | CI Gate NOT reliable. Check ci-logs-controller-*.txt for REAL status | ci-failed-preexisting |
| Swagger garbled chars | ASCII only, NEVER accents | UTF-8 encoding errors |
| Push to main 403 | Always use branch + PR + squash merge | HTTP 403 |

## Auth Architecture
- **Secrets**: sre-controller-auth (OAS_* vars), psc-sre-automacao-controller-runtime (JWT_*, SCOPE_*, AWS/OSS)
- **Auth flow**: Headers x-techbb-namespace/service-account > evaluateOasOriginAuth() > if match: internal-origin, else: JWT
- **Trusted caller**: namespace=sgh-oaas-playbook-jobs, serviceAccount=default
- **OaaS integration**: Validated end-to-end. POST /oas/sre-controller?mode=sync > 200 OK

## Web Session Auth (Codex/Copilot/Claude in browser terminals)
- If `gh` CLI is unavailable, use GitHub REST API via `curl` with `Authorization: Bearer <TOKEN>`.
- Use token only in runtime environment variables (`GH_TOKEN`/`GITHUB_TOKEN`) for the active session.
- NEVER persist tokens in tracked files, trigger JSONs, patches, or state snapshots.
- If a token is accidentally exposed in chat/logs, revoke and rotate immediately before continuing.
- Session memory may store the **process** (how to authenticate), never the secret value.

## Security Patterns (Mandatory)
- XSS: Use sanitizeForOutput() on all user input before response
- SSRF: Use parseSafeIdentifier on input, NEVER validateTrustedUrl inside fetch
- DoS: Always use MAX_RESULTS for loop bounds
- Error leak: Never return error.message directly, use sanitizeForOutput()

## Session History (Key Milestones)
| Date | What | Result |
|------|------|--------|
| 2026-03-23 | Historia #868216 complete | Deploy 3.5.4 with auth, swagger, CI fixes |
| 2026-03-23 | Deploy 3.5.5 | Swagger 18 routes + full deploy guide |
| 2026-03-24 | Deploy 3.5.6 | ESLint fix + corporate CI passed |
| 2026-03-24 | Multi-company setup | CIT workspace + ops environment |
| 2026-03-25 | Security fixes 3.6.3 | XSS + DoS + SSRF. Checkmarx findings resolved |
| 2026-03-25 | OaaS integration test | End-to-end validated. compliance_status=success |
| 2026-03-25 | Codex commit workflow | codex-apply.yml created |

## Operational Environment (ops/)
Complete DevOps platform for CIT workspace:
- **Scripts**: diagnose.sh, analyze-pipeline.sh, cluster-health.sh, tf-ops.sh, cloud-check.sh, alert-check.sh
- **Runbooks**: incidents, pipelines, k8s, terraform, cloud, monitoring
- **Templates**: GitLab CI, GitHub Actions, Jenkins, Terraform, K8s, Prometheus, Grafana
- **Readiness**: 17% (structure complete, credentials pending)

## File Locations
| What | Where |
|------|-------|
| Session memory | contracts/claude-session-memory.json |
| Codex session memory (separada) | contracts/codex-session-memory.json |
| Shared context (this file) | contracts/shared-agent-context.md |
| Workspace config | state/workspaces/<ws_id>/workspace.json |
| Patches | patches/ |
| Trigger files | trigger/ |
| CAP values | references/controller-cap/values.yaml |
| Schemas | schemas/ |
| Agent contracts | contracts/ |

## Agent Separation Policy (Claude x Codex)
- Claude memory (`contracts/claude-session-memory.json`) permanece estável e não deve ser reescrita por preferências específicas do Codex.
- Codex registra modo de trabalho próprio em `contracts/codex-session-memory.json`.
- Sincronização entre agentes deve compartilhar fatos globais (versão alvo, run, status, lições), sem alterar comportamento funcional já estável do Claude.
- Execução operacional deve ser centralizada no ambiente web do Autopilot, sem depender de shell local do usuário.
