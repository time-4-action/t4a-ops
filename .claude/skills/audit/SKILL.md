---
name: audit
description: Audit the t4a-ops inventory for completeness, consistency, and staleness. Checks that services, servers, and repos are cross-referenced correctly and flags gaps. Use periodically or before reviews to ensure documentation is accurate.
disable-model-invocation: true
allowed-tools: Read Grep Glob Bash(git log *)
---

Run a full audit of the t4a-ops inventory and documentation.

## Checks to perform

### 1. Cross-reference integrity
- Read `inventory/services.md`, `inventory/servers.md`, `inventory/repositories.md`
- Every **server IP** mentioned in `services.md` must have a corresponding row in `servers.md`
- Every **repository** mentioned in `services.md` must have a corresponding row in `repositories.md`
- Every **service** listed on a server in `servers.md` must exist in `services.md`
- Flag any orphaned entries (exist in one table but not referenced by others)

### 2. Completeness
- Flag any rows with empty required fields (service name, repo, server, IP, hostname, role)
- Flag any services still using the `_example_` placeholder
- Check that every service has a port assigned

### 3. Runbook coverage
- For each service in `services.md`, check if there's at least one runbook in `docs/runbooks/` that mentions it
- List services without any runbook coverage

### 4. ADR health
- Check for any ADRs with status `Proposed` older than 30 days (based on the Date field) — they should be accepted or dropped
- Check for ADRs with status `Deprecated` that are still referenced elsewhere

### 5. Documentation freshness
- Use `git log --format='%ai' -1 -- <file>` on each inventory file to check last modified date
- Flag any inventory file not updated in over 90 days

## Output

Present a clear report with sections:
- **Passed** — checks that are clean
- **Warnings** — non-critical issues (missing runbooks, stale files)
- **Errors** — broken cross-references, missing required fields

End with a prioritized list of suggested actions.
