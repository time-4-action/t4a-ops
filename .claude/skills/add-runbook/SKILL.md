---
name: add-runbook
description: Create a new operational runbook from the template. Guides through symptoms, diagnosis, resolution, monitoring, and escalation sections. Use when documenting how to handle a specific incident or operational procedure.
disable-model-invocation: true
argument-hint: [incident-or-procedure-name]
allowed-tools: Read Write Edit Grep Glob
---

Create a new runbook for: **$ARGUMENTS**

## Steps

1. Read `docs/runbooks/template.md` for the base structure.

2. Ask the user for the following (skip what they already provided):
   - **What service/system does this affect?**
   - **What are the symptoms?** (alerts, error messages, user-visible impact)
   - **How do you diagnose it?** (commands to run, logs to check, dashboards to look at)
   - **How do you fix it?** (step-by-step resolution)
   - **How do you verify the fix?** (monitoring commands, dashboard links)
   - **Who to escalate to?** (team, person, Slack channel)

3. Create the file at `docs/runbooks/<slugified-name>.md` where the slug is lowercase, hyphenated (e.g., `docs/runbooks/database-connection-timeout.md`).

4. Fill in all sections from the template. Every command in the Diagnosis and Resolution sections must be a copy-pasteable shell command or a clear instruction — no vague "check the logs" without specifying which log and how.

5. Cross-reference: if the affected service exists in `inventory/services.md`, mention the service name and server details in the runbook for quick context.

## Quality checks

- Every resolution step must be specific and actionable
- Include rollback steps if the resolution could make things worse
- Monitoring section must have at least one concrete verification command
