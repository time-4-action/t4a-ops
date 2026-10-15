# ADR-0002: CI/CD for t4a-ops

- **Status:** Accepted
- **Date:** 2026-10-15
- **Author:** Grega

## Context

The backup script and its systemd units in `scripts/` were installed on t4a-t2 by hand
from a clone at `/root/t4a-ops` ([Backup & Restore](../runbooks/backup-restore.md), step 5).
Nothing checked a change before merge, and nothing made the server match `main` after it.
The app repos (t4a-admin, t4a-partner-portal-api, patrik-warranty-form) already
deploy over SSH from GitHub Actions with org secrets `PROD_DEPLOY_*`, a host-key
fingerprint pin, a post-deploy check and an automatic rollback.

## Decision

One `ci` workflow, `check` → `deploy`, shaped like the app repos':

- **check** on every PR and push: secret scan, shellcheck, `systemd-analyze verify`,
  `docker compose config` on the reference compose files, actionlint, Markdown link check.
- **deploy** on `main` only: no image. It streams `git archive HEAD scripts` over SSH to the
  same VM and user as the apps and runs `sudo t4a-ops-deploy <sha>`, a root-owned installer
  that is the only thing `deploy` may sudo. It installs, verifies (including
  `t4a-backup.sh check`) and restores the previous files if verification fails.
- The server needs no git checkout and no credential for this repo.
- Reference compose files stay documentation; deploying them is out of scope.
- The deploy never enables timers or edits `/etc/t4a-backup.env`.

Details: [t4a-ops CI/CD runbook](../runbooks/ops-deploy.md).

## Consequences

- `main` is what is installed; a hand edit on the server is overwritten by the next deploy.
- A broken `/etc/t4a-backup.env` or missing backup tool now fails a deploy, which is the first
  place it shows up instead of the next nightly run.
- `deploy` gains a sudo rule. It already runs Docker (root-equivalent), so no new privilege.
- `/root/t4a-ops` on the server is no longer used.

## Rollback Plan

Each failed deploy restores the previous files on its own. To stop CI deploys entirely:
delete `/etc/sudoers.d/t4a-ops-deploy` on t4a-t2 (deploys then fail at sudo and change
nothing), revert the workflow, and go back to the manual install in the backup runbook.
