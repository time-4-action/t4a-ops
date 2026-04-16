# t4a-ops

Ops source of truth for the T4A ecosystem. Everything about what's running, where, and how to fix it.

## T4A T2 Cloud Instance

Docker services run as independent Compose stacks behind an nginx reverse proxy with Let's Encrypt SSL (Cloudflare DNS). The server also hosts a bare-metal WordPress stack (PHP 8.5 FPM + MariaDB) for multi-site WordPress hosting.

### Services

| Service | Port | Domain |
|---------|------|--------|
| patrik-api | 3000 | — |
| patrik-products-automation | 3001 | — |
| patrik-products-ui | 3002 | `product.t4a.etiam.si` |
| n8n (+ postgres) | 5678 | — |
| t4a-admin | 3005 | `admin.time-4-action.com` |
| t4a-chat | 3003 | `chat.time-4-action.com` |
| t4a-export-api | 3001 | — |
| t4a-export-ui | 3002 | — |
| t4a-mcp (+ chromadb) | 8000 | `mcp.time-4-action.com` |
| t4a-sync | 3000 | — |
| certbot | — | `t4a.etiam.si` |
| wordpress (multi-site) | — | per-site domains |
| php-fpm (Remi 8.5) | sock | — |
| mariadb | 3306 | — |

### Server disk layout

```
/data/
├── certbot/                          # SSL certs
├── patrik/                           # patrik-api
├── patrik-products/                  # products automation + UI
├── n8n/                              # N8N + postgres
└── stack/apps/time-4-action/
    ├── admin/                        # t4a-admin
    ├── chat/                         # t4a-chat
    ├── export/{api,ui}/              # export services
    ├── mcp/                          # MCP + ChromaDB
    └── sync/                         # t4a-sync

/mnt/vdc/                             # Block volume (/dev/vdc)
├── mysql/                            # MariaDB datadir
└── www/t4a/
    ├── <site1.domain.com>/           # WordPress site 1
    ├── <site2.domain.com>/           # WordPress site 2
    └── ...
```

### Cron jobs

| Service | Job | Schedule |
|---------|-----|----------|
| patrik-api | warehouseSync | every 15 min |
| t4a-sync | warehouseSync | every 15 min |
| t4a-sync | productSync | every 3h |

## Repo structure

```
inventory/       Services, servers, repositories tables
docker/t4a-t2/   Reference docker-compose files (secrets redacted)
docs/runbooks/   Incident/fix guides
docs/adr/        Architecture Decision Records
scripts/         Automation scripts
```

## Quick links

- [Service inventory](inventory/services.md)
- [Server inventory](inventory/servers.md)
- [Repository inventory](inventory/repositories.md)
- [Docker configs](docker/t4a-t2/)
- [Runbooks](docs/runbooks/)
