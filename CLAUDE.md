# CLAUDE.md — t4a-ops

## What is this repo?

Central "Source of Truth" for the T4A (Time 4 Action) ecosystem infrastructure. Manages deployment configs, inventory, and operational health for all T4A services and servers.

## Infrastructure overview

The T4A ecosystem runs on the **T4A T2** cloud instance, hosting 13 Docker services:

- **Patrik** — Metakocka ERP integration (API, products automation, products UI)
- **N8N** — Workflow automation engine (+ PostgreSQL)
- **T4A Platform** — Admin dashboard, AI chat agent, export services, sync services
- **T4A MCP** — AI-powered search server (FastAPI + ChromaDB + BM25)
- **Certbot** — SSL certificate management (Let's Encrypt via Cloudflare DNS)

Deployment model: per-service Docker Compose stacks behind nginx reverse proxy.

## Directory layout

- `inventory/` — Service, server, and repository tables (Markdown)
  - `services.md` — All 13 deployed services with ports, repos, status
  - `servers.md` — Server inventory (T4A T2 instance)
  - `repositories.md` — All application repositories
- `docker/` — Reference Docker Compose configs, organized by server
  - `docker/t4a-t2/` — All service compose files for the T4A T2 instance
- `k8s/` — Kubernetes manifests (future use)
- `scripts/` — Automation and maintenance scripts (must be idempotent)
- `docs/adr/` — Architecture Decision Records
- `docs/runbooks/` — Step-by-step incident/fix guides
- `.claude/skills/` — Custom Claude Code skills for this repo

## Available skills

- `/commit` — Smart multi-commit workflow, groups changes by scope
- `/add-service` — Register a new service in the inventory
- `/add-server` — Register a new server in the inventory
- `/add-runbook` — Create a runbook from template
- `/add-adr` — Create a numbered Architecture Decision Record
- `/audit` — Check inventory cross-references, completeness, and freshness

## Key conventions

- **No hardcoded secrets.** Use env vars or a secret manager. Secrets live in `.env` files on the server only.
- **Scripts must be idempotent** — safe to run repeatedly.
- **Every infra change needs a rollback plan.**
- **Use Mermaid.js** for architectural diagrams in docs.
- **DRY docs** — link between files, don't duplicate content.
