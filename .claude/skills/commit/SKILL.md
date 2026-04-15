---
name: commit
description: Smart commit workflow for t4a-ops. Analyzes all changes, groups them logically, and creates one or multiple well-scoped commits as needed. Handles inventory updates, docs, scripts, and configs separately.
disable-model-invocation: true
allowed-tools: Bash(git status *) Bash(git diff *) Bash(git log *) Bash(git add *) Bash(git commit *) Read Grep Glob
---

You are committing changes to the t4a-ops infrastructure repo. Follow this workflow:

## Step 1: Analyze changes

Run these in parallel:
- `git status` (never use `-uall`)
- `git diff` and `git diff --cached` to see all staged and unstaged changes
- `git log --oneline -5` to match the existing commit message style

## Step 2: Group changes logically

Categorize every changed file into one of these scopes:
- **inventory** — changes to `inventory/*.md`
- **docs** — changes to `docs/adr/*`, `docs/runbooks/*`
- **scripts** — changes to `scripts/*`
- **docker/k8s** — changes to `docker/*` or `k8s/*`
- **config** — changes to root config files (`.gitignore`, `CLAUDE.md`, etc.)
- **skills** — changes to `.claude/skills/*`

## Step 3: Decide single vs. multiple commits

- If ALL changes are in **one scope** or are tightly related -> **single commit**
- If changes span **multiple unrelated scopes** -> **multiple commits**, one per scope
- When in doubt, prefer fewer well-described commits over many tiny ones

## Step 4: Create commits

For each commit:
1. Stage only the files for that scope using specific file paths (never `git add -A` or `git add .`)
2. Never commit files matching: `.env*`, `*.pem`, `*.key`, `credentials.json`, `secrets/`
3. Write a commit message:
   - Format: `<scope>: <what changed and why>` (e.g., `inventory: add production server cluster details`)
   - Keep the first line under 72 characters
   - Add a body paragraph if the "why" isn't obvious from the title
   - End with: `Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>`
4. Use a HEREDOC for the message:
   ```
   git commit -m "$(cat <<'EOF'
   scope: message

   Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
   EOF
   )"
   ```

## Step 5: Verify

Run `git status` and `git log --oneline -5` to confirm everything is clean and the commits look right. Report the result.
