# Scripts

Automation, maintenance, and backup scripts for the T4A infrastructure.

## Conventions

- Scripts must be **idempotent** — safe to run multiple times.
- Never hardcode secrets; use environment variables or a secret manager.
- Include a `--dry-run` flag where destructive operations are involved.
- Add a brief comment header describing purpose, usage, and prerequisites.

## Deployment

CI installs these on T4A T2 on every push to `main`. A new file is deployed only once it is in
the `MANIFEST` of `deploy/t4a-ops-deploy.sh`. See [t4a-ops CI/CD](../docs/runbooks/ops-deploy.md).
