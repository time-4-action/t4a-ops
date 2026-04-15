# ADR-001: Repository Structure for t4a-ops

- **Status:** Accepted
- **Date:** 2026-04-15
- **Author:** Grega Rotar

## Context

The T4A ecosystem spans ~20 repositories and ~10 servers. There is no single source of truth for infrastructure configuration, service inventory, or operational runbooks.

## Decision

Adopt the directory structure defined in `CLAUDE_GUIDE.md`:

- `/inventory` — Markdown tables mapping services, repos, and servers.
- `/k8s`, `/docker` — Container orchestration manifests.
- `/scripts` — Automation, maintenance, and backup scripts.
- `/docs/adr` — Architecture Decision Records.
- `/docs/runbooks` — Step-by-step operational guides.
- `/.claude/skills/` — Custom Claude Code skills for repo workflows.

## Consequences

- All infrastructure knowledge lives in one searchable, scannable repo.
- New team members can onboard by reading inventory tables and ADRs.
- Changes to infra require PRs here, creating an audit trail.

## Rollback Plan

This is a greenfield structure — no rollback needed.
