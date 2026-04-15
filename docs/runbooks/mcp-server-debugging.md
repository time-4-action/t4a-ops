# Runbook: MCP Server Debugging (t4a-mcp)

## Symptoms

- `mcp.time-4-action.com` returns 502/503/504
- AI chat features (search, document retrieval) fail
- Auth0 JWT validation errors (401 responses)
- ChromaDB vector search returns empty results

## Diagnosis

1. Run the comprehensive debug script (on the server):
   ```bash
   cd /data/stack/apps/time-4-action/chat
   bash debug.sh --env /data/stack/apps/time-4-action/mcp/.env
   ```

2. Quick manual checks:
   ```bash
   # Container status and health
   docker ps --filter name=t4a-mcp --format '{{.Names}} {{.Status}}'
   docker ps --filter name=t4a-chromadb --format '{{.Names}} {{.Status}}'

   # Health endpoints
   curl -f http://localhost:8000/health
   curl -f http://localhost:8001/api/v1/heartbeat

   # Recent logs
   docker logs t4a-mcp --tail 50
   docker logs t4a-chromadb --tail 50
   ```

3. Check Auth0 connectivity from inside container:
   ```bash
   docker exec t4a-mcp printenv AUTH0_DOMAIN
   docker exec t4a-mcp curl -sf "https://$(docker exec t4a-mcp printenv AUTH0_DOMAIN)/.well-known/jwks.json" | head -1
   ```

4. Check nginx routing:
   ```bash
   curl -sf https://mcp.time-4-action.com/health
   ```

## Resolution

1. **Container down** — restart:
   ```bash
   cd /data/stack/apps/time-4-action/mcp
   docker compose up -d
   ```

2. **ChromaDB unhealthy** — MCP depends on ChromaDB; restart ChromaDB first:
   ```bash
   cd /data/stack/apps/time-4-action/mcp
   docker compose restart chromadb
   # Wait for healthcheck, then restart MCP
   docker compose restart t4a-mcp
   ```

3. **Auth0 JWT failures** — check `.env` for correct `AUTH0_DOMAIN`, `AUTH0_MCP_AUDIENCE`:
   ```bash
   cat /data/stack/apps/time-4-action/mcp/.env
   ```

4. **nginx not forwarding auth header** — ensure nginx config includes:
   ```
   proxy_set_header Authorization $http_authorization;
   ```

5. **Pull latest image and redeploy**:
   ```bash
   cd /data/stack/apps/time-4-action/mcp
   docker compose pull
   docker compose up -d
   ```

## Monitoring

- Health endpoint: `curl https://mcp.time-4-action.com/health`
- Container logs: `docker logs t4a-mcp --follow`
- ChromaDB heartbeat: `curl http://localhost:8001/api/v1/heartbeat`

## Escalation

- Auth0 config issues: check Auth0 dashboard for API/audience settings
- Vector DB corruption: ChromaDB data in `/data/stack/apps/time-4-action/mcp/chroma_db/`
