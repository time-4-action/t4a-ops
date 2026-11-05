#!/usr/bin/env bash
# Start one of the ~/t4a apps locally on its fixed port. One app per terminal.
#
#   portal-api   http://localhost:3000   t4a-partner-portal-api (the "export portal" API)
#   portal-ui    http://localhost:3001   t4a-partner-portal-ui
#   hub          http://localhost:3100   recharge-hub (Shopify CLI, plus its Postgres on 5432)
#   integration  http://localhost:4545   recharge-partners-integration-api
#
# portal-api and integration use the local Mongo from ./docker-compose.yml (localhost:27017).
set -euo pipefail
T="$(cd "$(dirname "$0")" && pwd)"

mongo() { docker compose -f "$T/docker-compose.yml" up -d --wait mongo; }

case "${1:-}" in
  portal-api)  mongo && cd "$T/t4a-partner-portal/t4a-partner-portal-api" && PORT=3000 exec npm run dev ;;
  portal-ui)   cd "$T/t4a-partner-portal/t4a-partner-portal-ui"  && PORT=3001 exec npm run dev ;;
  integration) mongo && cd "$T/recharge-partners-integration-api"          && PORT=4545 exec npm run dev ;;
  hub)
    cd "$T/recharge-hub"
    # Not ./dev.sh: that one runs `down --volumes` and wipes the local database.
    docker compose -f docker-compose.dev.yml up -d --wait postgres
    shift; exec npm run dev -- "$@" ;;
  *) sed -n '2,8p' "$0"; exit 1 ;;
esac
