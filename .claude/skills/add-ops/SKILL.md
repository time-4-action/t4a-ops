---
name: add-ops
description: Analyze pasted content (configs, logs, service definitions, deployment output, incident notes, etc.) and apply the right updates to the t4a-ops repo. Auto-detects what type of change is needed and which files to update.
disable-model-invocation: true
allowed-tools: Read Edit Write Grep Glob Bash(git status *) Bash(git diff *) Bash(git log *)
---

You are updating the t4a-ops infrastructure repo based on pasted content. The content to analyze is:

---
$ARGUMENTS
---

## Step 1: Classify the content

Read the pasted content and identify its type. It may be one or more of:

| Type | Signals |
|------|---------|
| **New service** | docker-compose snippet, new container name, new port, new domain |
| **Service change** | updated port, new domain, changed image, status change, migrated host |
| **New server** | new IP, new hostname, new cloud instance info |
| **Docker Compose config** | `services:`, `image:`, `volumes:`, `networks:` keys |
| **Incident / postmortem** | error logs, timeline of events, root cause, remediation steps |
| **Runbook candidate** | step-by-step ops procedure, "how to" instructions, maintenance steps |
| **ADR candidate** | architectural decision, trade-off analysis, "we decided to…" language |
| **Script** | shell commands, bash snippets, automation steps |
| **Inventory correction** | factual update to an existing row (wrong port, wrong repo, stale notes) |

If the content is ambiguous, pick the most likely type and state your interpretation before proceeding. If it's clearly multi-type, handle each type in sequence.

If the pasted content is empty or unrecognizable, ask the user to paste the content as an argument: `/add-ops <paste content here>`.

## Step 2: Read relevant files

Based on the classified type(s), read only the files you'll need to update. Do these reads in parallel:

- **New / changed service** → `inventory/services.md`, `inventory/repositories.md`, `inventory/servers.md`
- **New server** → `inventory/servers.md`, `inventory/services.md`
- **Docker Compose config** → `docker/t4a-t2/` (glob for the right compose file or determine the correct path)
- **Incident / runbook** → `docs/runbooks/` (glob to check for existing runbooks on the affected service)
- **ADR** → `docs/adr/` (glob to find the highest-numbered ADR for sequential numbering)
- **Script** → `scripts/` (glob to check for existing scripts with similar names)
- **Inventory correction** → `inventory/services.md` and/or `inventory/servers.md`

## Step 3: Plan the changes

Before editing anything, output a short plan (bullet list) of exactly which files will be created or modified and what will change. Keep it under 10 bullets. Then proceed without waiting for confirmation unless the change is destructive (e.g., deleting a service row or replacing an entire file).

## Step 4: Apply the changes

### New service
1. Add a row to `inventory/services.md` — keep alphabetical order; fill all columns from the pasted content.
2. If a repo slug is identifiable, add a row to `inventory/repositories.md` if not already present.
3. If a Docker Compose snippet was pasted, write or append it to `docker/t4a-t2/<service-name>.yml` (create the file if it doesn't exist; use the pasted content as-is, adding a comment header: `# Auto-captured from /add-ops on <date>`).
4. If the server is new, tell the user to also run `/add-server`.

### Service change / inventory correction
1. Find the matching row in `inventory/services.md` by service name.
2. Update only the changed fields — do not rewrite the entire row.
3. If a port or domain changed, check `docker/t4a-t2/` for a matching compose file and update it too.

### New server
Run the `/add-server` skill instead and pass the extracted details.

### Docker Compose config
1. Determine the service name from the compose file's top-level service key.
2. Write to `docker/t4a-t2/<service-name>.yml`. If the file already exists, diff the pasted config against the current file and apply only the changed keys — do not overwrite unchanged sections.
3. Update `inventory/services.md` if the image version, port, or status changed.

### Incident / postmortem → Runbook
1. Check if a runbook for the affected service already exists in `docs/runbooks/`.
2. If yes, append a new "## Incident: <date>" section at the bottom.
3. If no, create `docs/runbooks/<service-name>-incidents.md` using this template:
   ```markdown
   # <Service Name> — Incidents & Runbook

   ## Overview
   <one-line description of the service>

   ## Incident: <date>

   **Symptoms:** <from pasted content>
   **Root cause:** <from pasted content>
   **Resolution:**
   <numbered steps from pasted content>

   **Prevention:**
   <any follow-up actions>
   ```

### Runbook (procedural / how-to)
1. Check for an existing runbook in `docs/runbooks/` covering the same topic.
2. If yes, update the relevant section.
3. If no, create `docs/runbooks/<topic-slug>.md` using the `/add-runbook` template conventions: `# Title`, `## Prerequisites`, `## Steps`, `## Rollback`.

### ADR
1. Glob `docs/adr/` to find the highest-numbered file (e.g., `0005-*.md` → next is `0006`).
2. Create `docs/adr/<next-number>-<slug>.md` using this template:
   ```markdown
   # ADR-<N>: <Title>

   **Date:** <today>
   **Status:** Proposed

   ## Context
   <from pasted content>

   ## Decision
   <from pasted content>

   ## Consequences
   <from pasted content>
   ```

### Script
1. If the pasted content is a shell script or set of commands, save it to `scripts/<purpose-slug>.sh`.
2. Add a shebang (`#!/usr/bin/env bash`) and `set -euo pipefail` if missing.
3. Ensure the script is idempotent — add a comment if it already is, or note if idempotency needs to be verified.

## Step 5: Summarize

After all edits, output:
- Files created or modified (with paths)
- Any fields you couldn't fill from the pasted content and left as `—` or `TODO`
- Any follow-up actions the user should take (e.g., run `/commit`, add a server, fill in missing repo URL)
