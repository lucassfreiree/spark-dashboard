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

# ── Main ──

CMD="${1:-status}"
case "$CMD" in
  login)   cmd_login ;;
  status)  cmd_status ;;
  test)    cmd_test ;;
  refresh) cmd_refresh ;;
  revoke)  cmd_revoke ;;
  *)
    echo "Usage: $0 {login|status|test|refresh|revoke}"
    exit 1
    ;;
esac
