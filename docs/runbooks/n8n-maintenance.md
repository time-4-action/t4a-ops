# Runbook: N8N Maintenance

## Symptoms

- N8N UI unreachable
- Workflows not executing / webhooks failing
- PostgreSQL connection errors in N8N logs
- N8N reporting encryption key issues

## Diagnosis

1. Check container status:
   ```bash
   docker ps --filter name=n8n --format 'table {{.Names}}\t{{.Status}}'
   docker ps --filter name=n8n_postgres --format 'table {{.Names}}\t{{.Status}}'
   ```

2. Check N8N logs:
   ```bash
   docker logs n8n --tail 50
   ```

3. Check PostgreSQL health:
   ```bash
   docker exec n8n_postgres pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}
   ```

4. Verify N8N is reachable through nginx:
   ```bash
   curl -sf http://127.0.0.1:5678/healthz
   ```
   Note: N8N binds to `127.0.0.1:5678` only. It's accessed externally via nginx reverse proxy.

## Resolution

1. **Restart N8N stack** (postgres first, then n8n):
   ```bash
   cd /data/stack/apps/n8n
   docker compose restart postgres
   # Wait for postgres healthcheck
   docker compose restart n8n
   ```

2. **Full redeploy** (pulls latest N8N image):
   ```bash
   cd /data/stack/apps/n8n
   docker compose pull
   docker compose up -d
   ```

3. **PostgreSQL recovery** — if postgres data is corrupted:
   ```bash
   # Data lives in /data/n8n/postgres_data
   # Check postgres logs first
   docker logs n8n_postgres --tail 100
   ```

4. **Environment config** — env vars are in `/data/stack/apps/n8n/.env`:
   - `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`
   - `N8N_HOST`, `N8N_PORT`, `N8N_PROTOCOL`
   - `WEBHOOK_URL` — must match the external URL for webhooks to work
   - `N8N_ENCRYPTION_KEY` — changing this breaks encrypted credentials in workflows

## Monitoring

- N8N health: `curl http://127.0.0.1:5678/healthz`
- Postgres health: `docker exec n8n_postgres pg_isready`
- N8N data: `/data/n8n/n8n_data/` (workflows, config)
- N8N files: `/data/n8n/local-files/` (uploaded files)

## Escalation

- N8N encryption key issues are critical — do not change the key without migrating credentials
- Postgres data: `/data/n8n/postgres_data/`
