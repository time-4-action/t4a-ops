# Runbook: Service Restart (General)

## Symptoms

- A service is unresponsive or returning errors
- Container has exited or is in a restart loop
- Need to deploy a new image version

## Diagnosis

1. Check all container states:
   ```bash
   docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
   ```

2. Check specific service logs:
   ```bash
   docker logs <container_name> --tail 100
   ```

3. Check disk space (data volumes are under `/data/`):
   ```bash
   df -h /data
   ```

## Resolution

### Restart a single service

Each service has its own docker-compose directory on the server:

| Service | Server path |
|---------|-------------|
| patrik-api | `/data/patrik/` |
| patrik-products-automation | `/data/patrik-products/` |
| patrik-products-ui | `/data/patrik-products/` (separate compose or same dir) |
| n8n + postgres | `/data/stack/apps/n8n/` |
| t4a-admin | `/data/stack/apps/time-4-action/admin/` |
| t4a-chat | `/data/stack/apps/time-4-action/chat/` |
| t4a-export-api | `/data/stack/apps/time-4-action/export/api/` |
| t4a-export-ui | `/data/stack/apps/time-4-action/export/ui/` |
| t4a-mcp + chromadb | `/data/stack/apps/time-4-action/mcp/` |
| t4a-sync | `/data/stack/apps/time-4-action/sync/` |

```bash
cd <server_path>
docker compose restart
```

### Pull latest and redeploy

```bash
cd <server_path>
docker compose pull
docker compose up -d
```

### Restart all services (use with caution)

```bash
for dir in /data/patrik /data/patrik-products /data/stack/apps/n8n /data/stack/apps/time-4-action/admin /data/stack/apps/time-4-action/chat /data/stack/apps/time-4-action/export/api /data/stack/apps/time-4-action/export/ui /data/stack/apps/time-4-action/mcp /data/stack/apps/time-4-action/sync; do
  echo "Restarting $dir..."
  (cd "$dir" && docker compose up -d)
done
```

## Monitoring

- Verify container is running: `docker ps --filter name=<container_name>`
- Check service health (for services with healthchecks):
  ```bash
  docker inspect --format='{{.State.Health.Status}}' <container_name>
  ```
- Reload nginx if proxy config changed: `systemctl reload nginx`

## Escalation

- If a container keeps crash-looping, check `docker logs` for the root cause
- If disk is full, clean old images: `docker system prune -f`
