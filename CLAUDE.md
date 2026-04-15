# CLAUDE.md — t4a-ops

## What is this repo?
Central "Source of Truth" for the T4A ecosystem infrastructure. Manages deployment configs, inventory, and operational health for ~20 apps and ~10 servers.

## Directory layout
- `inventory/` — Service, server, and repository tables (Markdown)
- `k8s/`, `docker/` — Container orchestration manifests
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
- **No hardcoded secrets.** Use env vars or a secret manager.
- **Scripts must be idempotent** — safe to run repeatedly.
- **Every infra change needs a rollback plan.**
- **Use Mermaid.js** for architectural diagrams in docs.
- **DRY docs** — link between files, don't duplicate content.
