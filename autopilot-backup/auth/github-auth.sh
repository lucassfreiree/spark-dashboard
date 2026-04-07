#!/usr/bin/env bash
# ============================================================
# GitHub Authentication — Plan B (OAuth Device Flow)
#
# Use quando NÃO tiver um token disponível.
# Abre um fluxo interativo onde o usuário autoriza via browser.
#
# Resultado: gera um access_token salvo em ~/.autopilot-token
#
# Usage:
#   ./github-auth.sh login      → Autenticar via Device Flow
#   ./github-auth.sh status     → Verificar token atual
#   ./github-auth.sh test       → Testar acesso aos repos
#   ./github-auth.sh refresh    → Renovar token
#   ./github-auth.sh revoke     → Revogar token
# ============================================================
set -euo pipefail

# GitHub CLI public OAuth App client_id
CLIENT_ID="Iv1.b507a08c87ecfe98"
SCOPES="repo,workflow,read:org"
TOKEN_FILE="$HOME/.autopilot-token"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ── Helpers ──

_load_token() {
  if [ -f "$TOKEN_FILE" ]; then
    cat "$TOKEN_FILE"
  elif [ -n "${BBVINET_TOKEN:-}" ]; then
    echo "$BBVINET_TOKEN"
  elif [ -n "${GITHUB_TOKEN:-}" ]; then
    echo "$GITHUB_TOKEN"
  else
    echo ""
  fi
}

_save_token() {
  local token="$1"
  echo "$token" > "$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE"
  echo -e "${GREEN}Token saved to $TOKEN_FILE${NC}"
}

# ── Commands ──

cmd_login() {
  echo -e "${BLUE}=== GitHub OAuth Device Flow ===${NC}"
  echo ""

  # Step 1: Request device code
  echo "Requesting device code..."
  RESPONSE=$(curl -s -X POST "https://github.com/login/device/code" \
    -H "Accept: application/json" \
    -d "client_id=${CLIENT_ID}&scope=${SCOPES}")

  DEVICE_CODE=$(echo "$RESPONSE" | jq -r '.device_code')
  USER_CODE=$(echo "$RESPONSE" | jq -r '.user_code')
  VERIFY_URI=$(echo "$RESPONSE" | jq -r '.verification_uri')
  EXPIRES_IN=$(echo "$RESPONSE" | jq -r '.expires_in')
  INTERVAL=$(echo "$RESPONSE" | jq -r '.interval')

  if [ -z "$DEVICE_CODE" ] || [ "$DEVICE_CODE" = "null" ]; then
    echo -e "${RED}Failed to get device code${NC}"
    echo "$RESPONSE"
    exit 1
  fi

  # Step 2: Show user code
  echo ""
  echo "============================================"
  echo -e "  ${YELLOW}Open:  ${VERIFY_URI}${NC}"
  echo -e "  ${YELLOW}Code:  ${USER_CODE}${NC}"
  echo "============================================"
  echo ""
  echo "Enter the code above in your browser, then press Enter here..."
  echo "(Expires in ${EXPIRES_IN}s)"
  echo ""

  # Step 3: Poll for token
  ELAPSED=0
  while [ "$ELAPSED" -lt "$EXPIRES_IN" ]; do
    sleep "$INTERVAL"
    ELAPSED=$((ELAPSED + INTERVAL))

    TOKEN_RESPONSE=$(curl -s -X POST "https://github.com/login/oauth/access_token" \
      -H "Accept: application/json" \
      -d "client_id=${CLIENT_ID}&device_code=${DEVICE_CODE}&grant_type=urn:ietf:params:oauth:grant-type:device_code")

    ERROR=$(echo "$TOKEN_RESPONSE" | jq -r '.error // empty')
    TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token // empty')

    case "$ERROR" in
      "authorization_pending")
        echo -n "."
        ;;
      "slow_down")
        INTERVAL=$((INTERVAL + 5))
        echo -n "."
        ;;
      "expired_token")
        echo ""
        echo -e "${RED}Code expired. Run again.${NC}"
        exit 1
        ;;
      "access_denied")
        echo ""
        echo -e "${RED}Access denied by user.${NC}"
        exit 1
        ;;
      "")
        if [ -n "$TOKEN" ]; then
          echo ""
          echo -e "${GREEN}Authentication successful!${NC}"
          _save_token "$TOKEN"

          # Verify
          USER=$(curl -s -H "Authorization: token $TOKEN" "https://api.github.com/user" | jq -r '.login')
          echo -e "Logged in as: ${GREEN}${USER}${NC}"
          return 0
        fi
        ;;
    esac
  done

  echo ""
  echo -e "${RED}Timeout waiting for authorization${NC}"
  exit 1
}

cmd_status() {
  TOKEN=$(_load_token)
  if [ -z "$TOKEN" ]; then
    echo -e "${RED}No token found${NC}"
    echo "Run: $0 login"
    exit 1
  fi

  echo -e "${BLUE}=== Token Status ===${NC}"
  RESULT=$(curl -s -H "Authorization: token $TOKEN" "https://api.github.com/user")
  LOGIN=$(echo "$RESULT" | jq -r '.login // "INVALID"')

  if [ "$LOGIN" = "INVALID" ] || [ "$LOGIN" = "null" ]; then
    echo -e "${RED}Token is invalid or expired${NC}"
    echo "Run: $0 login"
    exit 1
  fi

  echo -e "User: ${GREEN}${LOGIN}${NC}"
  echo -e "Name: $(echo "$RESULT" | jq -r '.name')"

  # Rate limit
  RATE=$(curl -s -H "Authorization: token $TOKEN" "https://api.github.com/rate_limit")
  REMAINING=$(echo "$RATE" | jq -r '.resources.core.remaining')
  LIMIT=$(echo "$RATE" | jq -r '.resources.core.limit')
  echo -e "Rate: ${REMAINING}/${LIMIT}"

  # Scopes
  SCOPES_HEADER=$(curl -sI -H "Authorization: token $TOKEN" "https://api.github.com/user" | grep -i "x-oauth-scopes" | cut -d: -f2- | tr -d ' \r')
  echo -e "Scopes: ${SCOPES_HEADER}"

  echo -e "${GREEN}Token is valid${NC}"
}

cmd_test() {
  TOKEN=$(_load_token)
  if [ -z "$TOKEN" ]; then
    echo -e "${RED}No token found. Run: $0 login${NC}"
    exit 1
  fi

  echo -e "${BLUE}=== Testing Access to Corporate Repos ===${NC}"
  echo ""

  REPOS=(
    "bbvinet/psc-sre-automacao-agent"
    "bbvinet/psc-sre-automacao-controller"
    "bbvinet/psc_releases_cap_sre-aut-agent"
    "bbvinet/psc_releases_cap_sre-aut-controller"
  )

  ALL_OK=true
  for REPO in "${REPOS[@]}"; do
    HTTP=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: token $TOKEN" "https://api.github.com/repos/$REPO")
    PERMS=$(curl -s -H "Authorization: token $TOKEN" "https://api.github.com/repos/$REPO" | jq -c '.permissions // {}')

    if [ "$HTTP" = "200" ]; then
      PUSH=$(echo "$PERMS" | jq -r '.push')
      if [ "$PUSH" = "true" ]; then
        echo -e "  ${GREEN}✓${NC} $REPO (push: true)"
      else
        echo -e "  ${YELLOW}⚠${NC} $REPO (read only)"
      fi
    else
      echo -e "  ${RED}✗${NC} $REPO (HTTP $HTTP)"
      ALL_OK=false
    fi
  done

  echo ""
  if [ "$ALL_OK" = "true" ]; then
    echo -e "${GREEN}All repos accessible!${NC}"
  else
    echo -e "${RED}Some repos not accessible${NC}"
  fi

  # Test API operations
  echo ""
  echo -e "${BLUE}=== Testing API Operations ===${NC}"

  # Read
  VERSION=$(curl -s -H "Authorization: token $TOKEN" \
    "https://api.github.com/repos/bbvinet/psc-sre-automacao-agent/contents/package.json" | \
    jq -r '.content' | base64 -d 2>/dev/null | jq -r '.version' 2>/dev/null || echo "FAILED")
  echo -e "  Read package.json: ${VERSION}"

  # CI
  SHA=$(curl -s -H "Authorization: token $TOKEN" \
    "https://api.github.com/repos/bbvinet/psc-sre-automacao-agent/commits?per_page=1" | \
    jq -r '.[0].sha' 2>/dev/null || echo "")
  if [ -n "$SHA" ]; then
    CI=$(curl -s -H "Authorization: token $TOKEN" \
      "https://api.github.com/repos/bbvinet/psc-sre-automacao-agent/commits/$SHA/check-runs" | \
      jq -r '.total_count' 2>/dev/null || echo "FAILED")
    echo -e "  CI check-runs: ${CI} checks found"
  fi

  # Workflows
  WF=$(curl -s -H "Authorization: token $TOKEN" \
    "https://api.github.com/repos/bbvinet/psc-sre-automacao-agent/actions/workflows" | \
    jq -r '.total_count' 2>/dev/null || echo "FAILED")
  echo -e "  Workflows: ${WF} found"

  echo ""
  echo -e "${GREEN}API access fully operational${NC}"
}

cmd_refresh() {
  echo "OAuth tokens from Device Flow don't support refresh."
  echo "Run: $0 login"
  cmd_login
}

cmd_revoke() {
  TOKEN=$(_load_token)
  if [ -z "$TOKEN" ]; then
    echo "No token to revoke."
    exit 0
  fi

  echo "Revoking token..."
  rm -f "$TOKEN_FILE"
  echo -e "${GREEN}Token file removed${NC}"
  echo "Note: To fully revoke, go to GitHub Settings > Applications > Authorized OAuth Apps"
}

# ── PAT Commands ──

cmd_setup_pat() {
  echo -e "${BLUE}=== PAT Setup Guide ===${NC}"
  echo ""
  echo "PAT (Personal Access Token) is the ONLY method that works for bbvinet/* repos."
  echo "OAuth Device Flow does NOT work due to org restrictions."
  echo ""
  echo -e "${YELLOW}Step 1: Generate a PAT on GitHub${NC}"
  echo "  1. Go to: https://github.com/settings/tokens"
  echo "  2. Click 'Generate new token (classic)'"
  echo "  3. Select scopes: repo, workflow, admin:org (read)"
  echo "  4. Set expiration as needed"
  echo "  5. Copy the token (ghp_...)"
  echo ""
  echo -e "${YELLOW}Step 2: Configure the token${NC}"
  echo "  Option A (env var):  export BBVINET_TOKEN=\"ghp_your_token_here\""
  echo "  Option B (file):     echo \"ghp_your_token_here\" > ~/.autopilot-token && chmod 600 ~/.autopilot-token"
  echo ""
  echo -e "${YELLOW}Step 3: Validate${NC}"
  echo "  Run: $0 validate-pat"
  echo ""

  # Interactive setup
  echo -n "Do you want to enter your PAT now? (y/n): "
  read -r answer
  if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
    echo -n "Enter PAT: "
    read -rs pat_input
    echo ""
    if [[ -n "$pat_input" ]]; then
      _save_token "$pat_input"
      echo ""
      echo "Validating..."
      BBVINET_TOKEN="$pat_input" cmd_validate_pat
    fi
  fi
}

cmd_validate_pat() {
  local token="${BBVINET_TOKEN:-$(_load_token)}"
  if [[ -z "$token" ]]; then
    echo -e "${RED}No token found.${NC}"
    echo "Run: $0 setup-pat"
    exit 1
  fi

  echo -e "${BLUE}=== PAT Validation ===${NC}"
  echo ""

  # 1. Check identity
  local user_info
  user_info=$(curl -s -H "Authorization: token $token" "https://api.github.com/user" 2>/dev/null)
  local login
  login=$(echo "$user_info" | jq -r '.login // "INVALID"' 2>/dev/null || echo "INVALID")

  if [[ "$login" == "INVALID" || "$login" == "null" ]]; then
    echo -e "  ${RED}✗${NC} Token is invalid or expired"
    exit 1
  fi
  echo -e "  ${GREEN}✓${NC} Identity: ${login} ($(echo "$user_info" | jq -r '.name // ""'))"

  # 2. Check scopes
  local scopes
  scopes=$(curl -sI -H "Authorization: token $token" "https://api.github.com/user" 2>/dev/null | \
    grep -i "x-oauth-scopes" | cut -d: -f2- | tr -d ' \r')
  echo -e "  ${GREEN}✓${NC} Scopes: ${scopes:-none}"

  # 3. Check rate limit
  local remaining limit
  remaining=$(curl -s -H "Authorization: token $token" "https://api.github.com/rate_limit" 2>/dev/null | \
    jq -r '.resources.core.remaining // "?"')
  limit=$(curl -s -H "Authorization: token $token" "https://api.github.com/rate_limit" 2>/dev/null | \
    jq -r '.resources.core.limit // "?"')
  echo -e "  ${GREEN}✓${NC} Rate limit: ${remaining}/${limit}"

  # 4. Check corporate repo access
  echo ""
  echo -e "${BLUE}--- Corporate Repo Access ---${NC}"
  local repos=(
    "bbvinet/psc-sre-automacao-agent"
    "bbvinet/psc-sre-automacao-controller"
    "bbvinet/psc_releases_cap_sre-aut-agent"
    "bbvinet/psc_releases_cap_sre-aut-controller"
  )

  local all_ok=true
  for repo in "${repos[@]}"; do
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
      -H "Authorization: token $token" "https://api.github.com/repos/$repo" 2>/dev/null)
    if [[ "$http_code" == "200" ]]; then
      local push_perm
      push_perm=$(curl -s -H "Authorization: token $token" "https://api.github.com/repos/$repo" 2>/dev/null | \
        jq -r '.permissions.push // false')
      echo -e "  ${GREEN}✓${NC} ${repo} (push: ${push_perm})"
    else
      echo -e "  ${RED}✗${NC} ${repo} (HTTP ${http_code})"
      all_ok=false
    fi
  done

  echo ""
  if [[ "$all_ok" == "true" ]]; then
    echo -e "${GREEN}PAT is fully operational for all corporate repos.${NC}"
  else
    echo -e "${YELLOW}Some repos not accessible. Check PAT scopes and org membership.${NC}"
  fi
}

# ── Main ──

CMD="${1:-status}"
case "$CMD" in
  login)         cmd_login ;;
  status)        cmd_status ;;
  test)          cmd_test ;;
  refresh)       cmd_refresh ;;
  revoke)        cmd_revoke ;;
  setup-pat)     cmd_setup_pat ;;
  validate-pat)  cmd_validate_pat ;;
  help|--help|-h)
    echo "github-auth.sh — Authentication for Corporate Repos"
    echo ""
    echo "PAT (recommended):"
    echo "  $0 setup-pat       — Interactive PAT setup guide"
    echo "  $0 validate-pat    — Validate PAT access to repos"
    echo ""
    echo "OAuth (limited — does NOT work for bbvinet repos):"
    echo "  $0 login           — OAuth Device Flow login"
    echo ""
    echo "General:"
    echo "  $0 status          — Check current token"
    echo "  $0 test            — Test repo access"
    echo "  $0 revoke          — Remove saved token"
    ;;
  *)
    echo "Usage: $0 {setup-pat|validate-pat|login|status|test|revoke|help}"
    exit 1
    ;;
esac
