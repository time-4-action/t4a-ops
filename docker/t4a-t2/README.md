# T4A T2 — Docker Compose Reference

Reference docker-compose configs for all services on the T4A T2 cloud instance.

## Server layout on disk

```
/data/
├── certbot/              # SSL certs (Let's Encrypt via Cloudflare DNS)
├── patrik/               # patrik-api data + SQLite DB
├── patrik-products/      # Product CSV catalog + category mappings
├── n8n/
│   ├── postgres_data/    # N8N PostgreSQL data
│   ├── n8n_data/         # N8N workflows + config
│   └── local-files/      # N8N file storage
└── stack/apps/
    └── time-4-action/
        ├── admin/        # t4a-admin env + build
        ├── chat/         # t4a-chat env + debug script
        ├── export/
        │   ├── api/      # Export API data
        │   └── ui/       # Export UI env
        ├── mcp/          # MCP server + ChromaDB + BM25 indexes + uploads
        └── sync/         # T4A sync data + SQLite DB
```

## Service groups

Each subdirectory here contains a `docker-compose.yaml` reference (secrets redacted).

| Directory | Services | Ports |
|-----------|----------|-------|
| `patrik/` | patrik-api, patrik-products-automation, patrik-products-ui | 3000, 3001, 3002 |
| `n8n/` | n8n, n8n-postgres | 5678 (localhost) |
| `t4a-admin/` | t4a-admin | 3005 |
| `t4a-chat/` | t4a-chat (ai-agent-ui) | 3003 |
| `t4a-export/` | t4a-export-api, t4a-export-ui | 3001, 3002 |
| `t4a-mcp/` | t4a-mcp, t4a-chromadb | 8000, 8001 |
| `t4a-sync/` | t4a-sync | 3000 |

## Domains & routing (nginx reverse proxy)

| Domain | Service | Port |
|--------|---------|------|
| `t4a.etiam.si` | Main / nginx | 443 |
| `product.t4a.etiam.si` | patrik-products-ui | 3002 |
| `admin.time-4-action.com` | t4a-admin | 3005 |
| `chat.time-4-action.com` | t4a-chat | 3003 |
| `mcp.time-4-action.com` | t4a-mcp | 8000 |

## Cron schedules

| Service | Job | Schedule |
|---------|-----|----------|
| patrik-api | warehouseSync | `*/15 * * * *` |
| t4a-sync | warehouseSync | `0,15,30,45 * * * *` |
| t4a-sync | productSync | `0 2-23/3 * * *` (every 3h) |

## Notes

- All compose files use `restart: unless-stopped`.
- Secrets live in `.env` / `.env.local` files on the server, never in this repo.
- Port overlaps (3000, 3001, 3002) between patrik and stack services are isolated by separate Docker Compose networks.
