# ~/t4a local dev

What each app is and how they connect: [SYSTEM.md](SYSTEM.md).

Start each app in its own terminal with `./dev.sh <app>`:

| App | Command | URL | Needs |
|---|---|---|---|
| Export portal API (`t4a-partner-portal-api`) | `./dev.sh portal-api` | http://localhost:3000 | local Mongo (auto-started) |
| Export portal UI (`t4a-partner-portal-ui`) | `./dev.sh portal-ui` | http://localhost:3001 | portal API, Auth0 login |
| Recharge Hub | `./dev.sh hub --config dev` | via Shopify admin | Postgres (auto-started), a dev Partner app |
| Partners integration API | `./dev.sh integration` | http://localhost:4545 | local Mongo (auto-started) |
| `rechargesi` (theme) | `shopify theme dev` inside `rechargesi/` | Shopify CLI prints it | Shopify store access |

Databases (Docker):
- Mongo `localhost:27017` from `./docker-compose.yml`. DBs: `t4a` (portal) and `recharge` (integration). Starts empty.
- Postgres `localhost:5432` from `recharge-hub/docker-compose.dev.yml`, DB `orchestrator`.

Local-only changes to `.env` files (the originals are kept as `.env.bak-before-local`):
- portal API: `MONGO_URI` points at local Mongo, and `PRODUCTS_DOWNLOAD_SCHEDULE` is empty so the hourly PNV download stays off.
- integration API: `MONGO_URI` points at local Mongo.
- hub: `PORT=3100`, `EXPORT_PORTAL_URL=http://localhost:3000`, plus `POSTGRES_*` values that match `DATABASE_URL`.

Don't run `recharge-hub/dev.sh`: it does `down --volumes` and wipes the hub database.

Filling the empty portal DB with products (reads Patrik International's catalogue with the PNV credentials):

    curl -X POST -H "Authorization: Bearer $PARTNER_ADMIN_TOKEN" http://localhost:3000/api/admin/system/sync/pnv/run

`PARTNER_ADMIN_TOKEN` is in `t4a-partner-portal/t4a-partner-portal-api/.env`.
