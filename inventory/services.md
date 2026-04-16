# Service Inventory

Central registry mapping services to their repositories and deployment targets.

| Service | Repository | Server(s) | Port | Status | Notes |
|---------|-----------|-----------|------|--------|-------|
| certbot | — | t4a-t2 | — | Active | SSL cert renewal via Let's Encrypt + Cloudflare DNS. Domain: `t4a.etiam.si`. Renews 30 days before expiry, reloads nginx on renewal. |
| mariadb | `mariadb-server` (dnf) | t4a-t2 | 3306 (localhost) | Active | MariaDB 10.5.29. Database server for WordPress sites. Bare-metal install (not Docker). Datadir: `/mnt/vdc/mysql/`. Socket: `/mnt/vdc/mysql/mysql.sock`. Per-site DBs: `wp_{sitename}`. See [runbook](../docs/runbooks/mariadb-maintenance.md). |
| n8n | `docker.n8n.io/n8nio/n8n` | t4a-t2 | 5678 (localhost) | Active | Workflow automation. Backed by n8n-postgres. Bound to 127.0.0.1 only (proxied via nginx). Env-based config via `.env`. |
| n8n-postgres | `postgres:16-alpine` | t4a-t2 | 5432 (internal) | Active | PostgreSQL database for N8N. Healthcheck enabled. Data: `/data/n8n/postgres_data`. |
| php-fpm | `php-fpm` (Remi 8.5) | t4a-t2 | `/run/php-fpm/www.sock` | Active | PHP process manager for WordPress. Bare-metal install via Remi repo. Runs as `nginx` user. Config: `/etc/php-fpm.d/www.conf`. |
| patrik-api | `etiamsi/patrik-metakocka-automation-api` | t4a-t2 | 3000 | Active | Metakocka ERP sync API. Cron: warehouse sync every 15 min. Data: `/data/patrik`. SQLite DB. |
| patrik-products-automation | `etiamsi/patrik-products-automation` | t4a-t2 | 3001 | Active | Product catalog automation. Data: `/data/patrik-products`. CSV product DB (~2k products). |
| patrik-products-ui | `etiamsi/patrik-products-ui` | t4a-t2 | 3002 | Active | Product management UI. Connects to `product.t4a.etiam.si`. Gmail integration for notifications. |
| t4a-admin | `etiamsi/t4a-admin` | t4a-t2 | 3005 | Active | Admin dashboard (Next.js). Auth0 SSO. Domain: `admin.time-4-action.com`. Env file: `.env.local`. |
| t4a-chat | `etiamsi/t4a-ai-agent-ui` | t4a-t2 | 3003 | Active | AI agent chat interface. Auth0 SSO. Domain: `chat.time-4-action.com`. Env file: `.env.local`. |
| t4a-chromadb | `chromadb/chroma:0.6.3` | t4a-t2 | 8001 | Active | Vector database for MCP semantic search. Persistent storage. Healthcheck on `/api/v1/heartbeat`. |
| t4a-export-api | `etiamsi/t4a-export-api` | t4a-t2 | 3001 | Active | Product export API. Data: `/data/stack/apps/time-4-action/export/api/data`. Shares port 3001 with patrik-products (separate compose network). |
| t4a-export-ui | `etiamsi/patrik-products-ui` | t4a-t2 | 3002 | Active | Export UI (reuses patrik-products-ui image). Env file: `.env`. Shares port 3002 with patrik-products-ui (separate compose network). |
| t4a-mcp | `etiamsi/t4a-mcp` | t4a-t2 | 8000 | Active | MCP server — AI-powered search with ChromaDB + BM25. Python/FastAPI. Auth0 JWT auth. Domain: `mcp.time-4-action.com`. Healthcheck on `/health`. |
| t4a-sync | `etiamsi/patrik-metakocka-automation-api` | t4a-t2 | 3000 | Active | T4A warehouse/product sync. Cron: warehouse every 15 min, products every 3h. Data: `/data/stack/apps/time-4-action/sync`. Shares port 3000 with patrik-api (separate compose network). |
| wordpress | WordPress (latest) | t4a-t2 | — | Active | Multi-site WordPress hosting. Bare-metal installs (not Docker). Each site in `/mnt/vdc/www/t4a/<domain>/`. Served by nginx + php-fpm. Block volume `/dev/vdc` mounted at `/mnt/vdc`. See [runbook](../docs/runbooks/wordpress-multisite-setup.md). |

> **Instructions:** Add one row per deployed service. Keep sorted alphabetically by service name.
> For server details, see [servers.md](./servers.md).
