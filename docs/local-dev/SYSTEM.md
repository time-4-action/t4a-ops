# How the ~/t4a apps fit together

Five repos, two GitHub organisations, one Shopify store that matters most (Recharge).
This page says what each app owns, who calls whom, and which app may write what into
Shopify. Each repo's own `CLAUDE.md` / `AGENTS.md` / `docs/` has the detail.

## The apps

| Name used here | Repo (GitHub) | What it is | Stack | Local |
|---|---|---|---|---|
| **Export portal API** | `t4a-partner-portal/t4a-partner-portal-api` (time-4-action) | Time 4 Action's product sync ("Product Sync"). Pulls Patrik International's catalogue from PNV, stock and prices from MetaKocka, takes in **Own Source** brand feeds, and **pushes products and stock to connected Shopify stores**. Serves the Sources API (`/api/v1`) | Express 5, MongoDB (`t4a`) | :3000 |
| **Export portal UI** | `t4a-partner-portal/t4a-partner-portal-ui` (time-4-action) | The partners' web app for the portal: products, exports, AI categories, Shopify integration, Own Sources. Thin proxy to the portal API, Auth0 login | Next.js 16, JS | :3001 |
| **Partners integration API** | `recharge-partners-integration-api` (recharge-si) | Turns each partner's own export (POINT-7, Unifiber, …) into one standard JSON feed at `/api/export/<id>`. **Never writes to Shopify**: the export portal reads those URLs as Own Sources | Next.js 16, TS, MongoDB (`recharge`) | :4545 |
| **Recharge Hub** | `recharge-hub` (recharge-si) | Recharge's embedded Shopify app: MetaKocka ↔ Shopify orders and inventory, sale campaigns, attributes, translations, and a **Sources** screen that drives the export portal through `/api/v1` | React Router 7, TS, Prisma/Postgres | :3100 |
| **rechargesi** | `rechargesi` (recharge-si) | The Recharge storefront theme (Dawn 15.4.1, customised) | Liquid/JS/CSS, no build | `shopify theme dev` |

"Export portal" always means the portal API + UI pair (Time 4 Action product). Older
names for it in docs: *partner portal*, *Product Sync*, *patrik-products*.

## Data flow

```
 PNV (Patrik catalogue) ─┐
 MetaKocka (stock, price)─┼─▶ Export portal API ──push──▶ Shopify store(s)
 Own Source feeds ───────┘        ▲     ▲                    ▲   ▲
   ▲                              │     │ /api/v1 (key per   │   │ orders, inventory,
   │ GET /api/export/<id>         │     │  store)            │   │ prices (sale campaigns),
   │                       Export portal UI   Recharge Hub ──┘   │ translations
 Partners integration API                       │                │
   ▲ partner exports (POINT-7 JSON,             └─ MetaKocka ────┘
     Unifiber CSV)                                                 rechargesi theme (storefront)
```

## Rules that keep it coherent

1. **One writer per thing in Shopify.** Product and stock pushes from catalogues and
   brand feeds go through the export portal only, each source at its own Shopify
   location. Recharge Hub owns MetaKocka inventory at its own location(s), orders,
   sale-campaign prices and translations. The partners integration API writes nothing.
   A new feature that writes to Shopify must say which of these it belongs to.
2. **One feed contract.** The Own Source feed format is the portal's JSON Schema,
   `t4a-partner-portal-api/src/services/external/schema/own-source.v1.json`, served at
   `https://api.time-4-action.com/api/export/schemas/own-source.v1.json`. The partners
   integration API keeps a verbatim copy and its CI (`npm run check:schema`) fails on
   drift. Change the portal's file first.
3. **One API contract between Hub and portal.** `/api/v1` is documented on both sides:
   `t4a-partner-portal-api/docs/sources-api.md` (portal) and `recharge-hub/docs/sources.md`
   (hub). Change them together.
4. **Copies that must stay equal.** The portal UI's `src/lib/priceRounding.js` and
   `comparePrice.js` are ports of the API's `src/services/shopify/*.util.js`; the UI's
   `npm test` compares them when both repos are checked out side by side.
5. **MetaKocka "available" stock** is the free amount (`free_amount`, or
   `amount - reserved_amount`), summed over a warehouse's microlocations, never raw
   `amount`. Both the portal API and the hub read MetaKocka; see each repo's notes.

## Working here

- `./dev.sh <app>` starts one app on its fixed port (see `README.md`).
- Every repo deploys from `main` via GitHub Actions to GHCR + SSH. Work on a branch,
  open a pull request; never push `main`.
- Tests: `npm test` in each Node repo (hub also has `npm run test:e2e`).
