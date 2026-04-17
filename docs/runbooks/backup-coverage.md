# Backup Coverage — t4a-t2

> **Purpose:** single source of truth for what is (and is not) captured by the
> restic backup on t4a-t2. If you are ever unsure *"is X in the backup?"*, read
> this file. For *how* to run backups/restores, see
> [backup-restore.md](./backup-restore.md).

**Destination:** Hetzner Storage Box, restic repo `sftp:t4a-storagebox:restic/t4a-t2`
**Schedule:** nightly ~03:00 (all tags), maintenance Sun ~04:00
**Retention:** 7 daily, 4 weekly, 6 monthly per `host,tags` group

## TL;DR

Green = safe. Yellow = partially covered or reconstructible with effort. Red = total loss if the disk dies tonight.

| Area | State |
|---|---|
| WordPress sites (files + MariaDB) | 🟢 covered |
| System configs (nginx, letsencrypt, fstab, systemd, my.cnf.d) | 🟢 covered |
| Docker compose files + their `.env` secrets | 🟢 covered |
| n8n (Postgres dump + `n8n_data` + `local-files`) | 🟢 covered |
| Patrik SQLite DB (`/data/patrik/`) | 🔴 NOT covered |
| T4A sync SQLite DB (`/data/stack/apps/time-4-action/sync/`) | 🔴 NOT covered |
| ChromaDB vector store (`/data/stack/apps/time-4-action/mcp/chroma_db/`) | 🟡 reconstructible (reindex) |
| BM25 indexes + MCP uploads | 🟡 reconstructible |
| Export API data (`/data/stack/apps/time-4-action/export/api/data/`) | 🔴 NOT covered |
| patrik-products CSV catalog (`/data/patrik-products/`) | 🔴 NOT covered |

## Tag → source map

The nightly `t4a-backup.sh all` run creates one snapshot per tag below. `n8n` is a single sub-command that produces two snapshots (`n8n-postgres` + `n8n-files`).

| Tag | Source on server | Mechanism |
|---|---|---|
| `mariadb` | all MariaDB databases | `mariadb-dump --all-databases --single-transaction` → stdin → restic |
| `wordpress` | `/mnt/vdc/www/t4a/` | restic filesystem backup, excludes WP caches + `*.log` |
| `n8n-postgres` | n8n Postgres database inside `n8n_postgres` container | `docker exec … pg_dump --clean --if-exists` → stdin → restic |
| `n8n-files` | `/data/n8n/n8n_data/` + `/data/n8n/local-files/` | restic filesystem backup |
| `configs` | system `/etc/*` + all docker-compose `.yaml` + `.env` files | restic filesystem backup (explicit file list — see `backup.env.example`) |

Full path list for `configs` is in [`scripts/backup.env.example`](../../scripts/backup.env.example) → `BACKUP_PATHS_CONFIGS`. Changes to that file must be deployed to `/etc/t4a-backup.env` on the server.

## Per-service coverage

| Service | Data path on server | Backed up by | Recover from | Notes |
|---|---|---|---|---|
| **MariaDB** | `/mnt/vdc/mysql/` | `mariadb` tag | logical dump replay | Bare-metal install. Dump is `all-databases.sql`. |
| **WordPress (all sites)** | `/mnt/vdc/www/t4a/` | `wordpress` tag | rsync from restore | WP caches + `*.log` excluded. |
| **nginx config** | `/etc/nginx` | `configs` tag | restore to `/` | |
| **Let's Encrypt certs** | `/etc/letsencrypt` | `configs` tag | restore to `/` | Renewal also needs certbot compose + Cloudflare API secrets (in certbot `.env`, currently commented out — see "Known gaps"). |
| **MariaDB config** | `/etc/my.cnf.d` | `configs` tag | restore to `/` | |
| **fstab / hosts** | `/etc/fstab`, `/etc/hosts` | `configs` tag | restore to `/` | |
| **Backup systemd units** | `/etc/systemd/system/t4a-backup*` | `configs` tag | restore to `/` + `daemon-reload` | The backup backs up its own units so DR can re-enable the timer. |
| **n8n (app)** | `/data/n8n/n8n_data/` + `/data/n8n/local-files/` | `n8n-files` tag | rsync from restore | Holds `N8N_ENCRYPTION_KEY` copy + workflow files. |
| **n8n Postgres** | `/data/n8n/postgres_data/` (container volume) | `n8n-postgres` tag | `psql < n8n.sql` | Dump is taken via `docker exec pg_dump`. Container must be up. |
| **n8n compose + env** | `/data/n8n/docker-compose.yaml` + `.env` | `configs` tag | restore to `/` | |
| **Patrik compose + env** | `/data/patrik/docker-compose.yaml` + `.env` | `configs` tag | restore to `/` | 🔴 **App data** (`/data/patrik/` SQLite + cron.json + cron_state) is NOT backed up. |
| **patrik-products catalog** | `/data/patrik-products/` | — | — | 🔴 Not backed up. Contains CSV product DB (~2k products) and category mappings. |
| **T4A admin** | `/data/stack/apps/time-4-action/admin/` | compose + `.env.local` in `configs` | restore to `/` + `docker compose up -d` | No persistent runtime data (Next.js, stateless). |
| **T4A chat** | `/data/stack/apps/time-4-action/chat/` | compose + `.env.local` in `configs` | restore to `/` + `docker compose up -d` | Stateless. |
| **T4A export** | `/data/stack/apps/time-4-action/export/` | compose + `.env` in `configs` | restore to `/` + `docker compose up -d` | 🔴 `/export/api/data/` volume is NOT backed up. |
| **T4A MCP** | `/data/stack/apps/time-4-action/mcp/` | compose + `.env` in `configs` | restore to `/` + `docker compose up -d` | 🟡 `chroma_db/`, `bm25_indexes/`, `uploads/` NOT backed up. Reindex needed after restore. |
| **T4A sync** | `/data/stack/apps/time-4-action/sync/` | compose in `configs` | restore to `/` + `docker compose up -d` | 🔴 SQLite DB + cron state NOT backed up. Re-sync from Metakocka needed. |
| **certbot** | `/data/certbot/` | — (paths commented out in template) | — | Uncomment in `BACKUP_PATHS_CONFIGS` once layout confirmed. |

## Known gaps (priority order)

Ranked by "how bad is it if we lose this tonight."

### 🔴 Critical — stop-the-business if lost

None. The most business-critical state (MariaDB, n8n Postgres + files) is covered.

### 🔴 High — days of manual recovery work

| Gap | Impact | Close by |
|---|---|---|
| **Patrik SQLite DB** (`/data/patrik/`) | Metakocka ERP sync state + history lost. Full re-sync from ERP required. | Add `/data/patrik/` to a new `app-data` tag, or run SQLite `.backup` via a scheduled cron before the nightly restic run. |
| **T4A sync SQLite DB** (`/data/stack/apps/time-4-action/sync/`) | Warehouse/product sync state lost. Cron re-establishes sync but history gone. | Same approach as Patrik. |
| **patrik-products CSV catalog** (`/data/patrik-products/`) | ~2k products + category mappings lost. | Back up the whole dir — it's small and changes slowly. |

### 🟡 Medium — reconstructible but time-consuming

| Gap | Impact | Close by |
|---|---|---|
| **ChromaDB vector store** (`/data/stack/apps/time-4-action/mcp/chroma_db/`) | AI search broken until reindex. Rebuild is scripted but takes time. | Stop container briefly and file-copy, or use ChromaDB's native export. |
| **BM25 indexes + MCP uploads** | Similar to above; MCP uploads may include user-provided files. | Include in MCP backup. |
| **Export API data** (`/data/stack/apps/time-4-action/export/api/data/`) | Export history lost. Regenerable if the source data (MariaDB) is intact. | Add to `configs` or new `app-data` tag. |

### 🟢 Low — already covered or accepted risk

| Item | Why it's OK |
|---|---|
| n8n container volume (`/data/n8n/postgres_data/`) | Captured via logical `pg_dump` — more durable than volume copy. |
| WordPress caches | Regenerated on next request. |
| Docker images | Pulled from registries on recovery; not our data. |

## Secrets backed up in the restic repo

Every `.env` / `.env.local` captured by the `configs` tag contains production secrets. These are **encrypted client-side** by restic (AES-256 + Poly1305) before leaving the server. An attacker with:

- **Just the Storage Box SSH key** → can delete/corrupt backups, cannot read them.
- **Just the restic repo password** → useless without the encrypted blobs.
- **Both** → full access.

Storage locations on server:
- Repo password: `/root/.restic-password` (root-only, `chmod 600`, off-server copy in password manager).
- SSH identity: `/root/.ssh/hetzner_storagebox` (dedicated key, not reused).

Secrets included in backups:
- All MariaDB data (including hashed WP admin passwords, site secrets).
- `/data/n8n/n8n_data/` — includes copy of `N8N_ENCRYPTION_KEY` used to encrypt workflow credentials at rest.
- `.env` / `.env.local` for every docker stack — Auth0 client secrets, Metakocka API keys, Gmail app passwords, Postgres passwords, etc.
- `/etc/letsencrypt/` — SSL private keys.

## Recovery quick reference

> "I need to restore just X." Find X below, run the command, verify, move into place.

Assumes `RESTIC_REPOSITORY` + `RESTIC_PASSWORD_FILE` are exported (or source `/etc/t4a-backup.env`).

| Need | Tag(s) | See section in [backup-restore.md](./backup-restore.md) |
|---|---|---|
| Single WordPress file | `wordpress` | Restore a single WordPress file |
| Whole WordPress tree | `wordpress` | Restore the whole WordPress tree |
| MariaDB dump | `mariadb` | Restore a MariaDB dump |
| n8n workflows + Postgres | `n8n-files` + `n8n-postgres` | Restore n8n (PostgreSQL + files) |
| nginx config rollback | `configs` | (restore single path with `--include`) |
| SSL certs | `configs` | (restore `/etc/letsencrypt/`) |
| Full bare-metal | all | Full disaster recovery |

## Verifying coverage on the server

Sanity-check what the nightly run actually captured:

```bash
source <(grep -E '^(RESTIC|BACKUP_HOST)=' /etc/t4a-backup.env | sed 's/^/export /')
export RESTIC_PASSWORD_FILE

# One line per (host, tag) — latest snapshot only
restic snapshots --group-by 'host,tags' --latest 1

# See what files a specific snapshot contains (swap <id> for the snapshot id above)
restic ls <id> | head -50

# Grep for a specific path inside the latest configs snapshot
restic ls latest --tag configs | grep -E '(docker-compose|\.env)'
```

All `Time` columns in the snapshots output should be < 30h old. If a tag is missing entirely, the nightly didn't cover it — check `journalctl -u t4a-backup.service --since yesterday`.

## Changelog

- **2026-04-17** — Initial coverage map. Added n8n (Postgres dump + files), replaced `/opt/docker/*` placeholder paths in `configs` tag with real `/data/*` compose + env paths. Gaps documented: Patrik/sync SQLite, patrik-products catalog, ChromaDB/BM25/uploads, export API data, certbot compose.
