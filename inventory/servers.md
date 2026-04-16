# Server Inventory

| Hostname | IP | Role | OS | Provider | Services | Notes |
|----------|-----|------|-----|----------|----------|-------|
| t4a-t2 | — | App + Workflow + WordPress Server | AlmaLinux 9 | Cloud (OpenStack) | patrik-api, patrik-products-automation, patrik-products-ui, n8n, n8n-postgres, t4a-admin, t4a-chat, t4a-export-api, t4a-export-ui, t4a-mcp, t4a-chromadb, t4a-sync, certbot, wordpress, php-fpm, mariadb | Primary T4A instance. Docker services via per-directory Compose + bare-metal WordPress stack. Nginx reverse proxy with Let's Encrypt SSL (wildcard `*.t4a.etiam.si` via Cloudflare DNS). Data root: `/data/`. WordPress sites on block volume `/dev/vdc` at `/var/www/t4a/`. |

> **Instructions:** Add one row per server. Link services back to [services.md](./services.md).
