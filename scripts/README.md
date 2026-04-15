# Scripts

Automation, maintenance, and backup scripts for the T4A infrastructure.

## Conventions

- Scripts must be **idempotent** — safe to run multiple times.
- Never hardcode secrets; use environment variables or a secret manager.
- Include a `--dry-run` flag where destructive operations are involved.
- Add a brief comment header describing purpose, usage, and prerequisites.
