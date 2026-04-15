# Server Inventory

| Hostname | IP | Role | OS | Provider | Services | Notes |
|----------|-----|------|-----|----------|----------|-------|
| t4a-t2 | — | App + Workflow Server | Linux | Cloud | patrik-api, patrik-products-automation, patrik-products-ui, n8n, n8n-postgres, t4a-admin, t4a-chat, t4a-export-api, t4a-export-ui, t4a-mcp, t4a-chromadb, t4a-sync, certbot | Primary T4A instance. Runs all services via per-directory Docker Compose. Nginx reverse proxy with Let's Encrypt SSL (wildcard `*.t4a.etiam.si` via Cloudflare DNS). Data root: `/data/`. |

> **Instructions:** Add one row per server. Link services back to [services.md](./services.md).
