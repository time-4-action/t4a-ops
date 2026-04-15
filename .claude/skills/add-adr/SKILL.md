---
name: add-adr
description: Create a new Architecture Decision Record. Auto-numbers based on existing ADRs and guides through context, decision, consequences, and rollback plan. Use when documenting an infrastructure or architectural decision.
disable-model-invocation: true
argument-hint: [decision-title]
allowed-tools: Read Write Glob Grep
---

Create a new ADR for: **$ARGUMENTS**

## Steps

1. Find the next ADR number by scanning `docs/adr/` for existing files matching `NNN-*.md`. The new ADR gets the next sequential number, zero-padded to 3 digits.

2. Read `docs/adr/000-template.md` for the base structure.

3. Ask the user for the following (skip what they already provided):
   - **Context:** What problem or situation prompted this decision?
   - **Decision:** What are we doing about it?
   - **Consequences:** What gets easier? What gets harder?
   - **Rollback plan:** How do we undo this if it goes wrong?

4. Create the file at `docs/adr/<NNN>-<slugified-title>.md`.
   - Set Status to `Proposed` (user can change to `Accepted`/`Deprecated`/`Superseded` later)
   - Set Date to today's date
   - Set Author from git config user.name, or ask

5. Write clear, concise prose. ADRs are read months later by people with no context — avoid jargon without explanation and link to relevant services/runbooks in the inventory when applicable.
