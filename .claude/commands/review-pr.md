# Review and Fix PR

@description Review an existing PR with parallel agents, fix findings, and push.
@arguments $PR_NUMBER: GitHub PR number to review and fix

Read PR #$PR_NUMBER using `gh pr view` (description, linked issues,
commits) and the diff against the base branch.

Detect the upstream repository: if a git remote named `upstream`
exists, use it as the canonical repo; otherwise `origin`. Resolve
`owner/name` and pass `--repo <owner/name>` on every `gh` command.
`git fetch <upstream-remote>`, then check out the PR branch.

Execute every step below sequentially. Do not stop or ask for
confirmation at any step.

## 0. Prepare shared review inputs (once)

Do this in the main context so agents don't each redo it:

```bash
DIFF_FILE=$(mktemp -t pr-review-diff)
git diff <upstream-remote>/<base-branch>...HEAD > "$DIFF_FILE"
git diff --name-only <upstream-remote>/<base-branch>...HEAD
DIFF_LINES=$(wc -l < "$DIFF_FILE")
```

Every review agent prompt must include: the PR title/description
(one paragraph), the changed-file list, and the path `$DIFF_FILE` —
instructing the agent to read the diff from that file and only open
source files it needs beyond the diff. Agents must NOT re-run
`gh pr view` or regenerate the diff.

## 1. Review

Scale the review to the diff, and never spawn an agent for an
unavailable external tool.

### Availability pre-check (cheap, main context)

```bash
command -v codex >/dev/null && echo codex-ok
command -v gemini >/dev/null && echo gemini-ok
```

Only run an external pass whose CLI exists. If neither exists,
note "external passes skipped" in the summary and move on — do not
spawn agents to discover this.

### Size gate

- **Small PR** (`DIFF_LINES` < 200 and ≤ 5 changed files): launch
  ONE `pr-review-toolkit:code-reviewer` agent covering quality,
  silent failures, and test gaps in a single pass. Skip the other
  two toolkit agents.
- **Otherwise**: launch all three toolkit agents **in parallel**
  (single message, multiple tool calls):

| agent | focus |
|-------|-------|
| `pr-review-toolkit:code-reviewer` | Code quality, style, project guidelines |
| `pr-review-toolkit:silent-failure-hunter` | Silent failures, swallowed errors, bad fallbacks |
| `pr-review-toolkit:pr-test-analyzer` | Test coverage gaps and missing edge cases |

### External second opinions (only if the pre-check passed)

Run these as **background Bash calls** (`run_in_background: true`)
started in the same message as the toolkit agents — do NOT wrap
them in general-purpose agents; a subagent context buys nothing
over reading the command's stdout.

**Codex** (if installed):

```bash
codex review --base <upstream-remote>/<base-branch> \
  -c model='"gpt-5.3-codex"'
```

- Default reasoning effort (do not set `xhigh` — it multiplies
  wall time for marginal gain on a PR-sized diff)
- If `gpt-5.3-codex` fails with an auth error, retry once with
  `gpt-5.2-codex`; if that also fails (auth/login), skip and note it
- When reading the output, use only the findings — ignore
  `[thinking]`/`[exec]` blocks and sandbox warnings

**Gemini** (if installed):

```bash
{
  echo "Review this diff for bugs, correctness, and quality. Report findings only, one per line, with file:line."
  if [ -f CLAUDE.md ]; then
    echo ""; echo "Project conventions:"; echo "---"
    head -c 8000 CLAUDE.md
    echo "---"
  fi
  echo ""; echo "Diff:"
  cat "$DIFF_FILE"
} | gemini -p - -m gemini-3-pro-preview --yolo
```

- If it exits with an auth error, skip and note it — do not retry
  or attempt to re-authenticate

While the background commands run, collect the toolkit agents'
results; read the background outputs when they finish. If an
external command hasn't finished by the time findings are merged
and fixes are underway, check it once before committing — don't
poll.

### Merge findings

Deduplicate across sources — keep the most specific description,
note consensus. Rank by severity:

- **P1** — blocks merge (correctness bugs, security issues)
- **P2** — important (missing error handling, test gaps, logic flaws)
- **P3** — nice to have (style, naming, minor simplifications)
- **P4** — informational

## 2. Fix findings

Address all P1–P3 findings. For each: **fix it**, or **dismiss it**
with inline reasoning (false positive, stylistic disagreement,
impossible edge case). Adversarially verify a finding against the
actual code before fixing — plausible findings often misread it.

When a fix requires external context (unfamiliar library behavior,
unrecognized error), search with Exa (`mcp__exa__web_search_exa`)
rather than guessing.

P4 findings: note, don't fix unless trivial.

After fixing, read the diff of your own fixes and verify each is
correct and doesn't regress the PR.

## 3. Verify

**If no fixes were applied (all findings dismissed or none found),
skip this section entirely** — the PR's own CI already covers the
unchanged branch. Note "no changes; verification delegated to CI"
in the summary.

### 3a. Resolve project checks (cheapest source first)

1. **CLAUDE.md / Makefile first.** If the repo's CLAUDE.md or
   Makefile names build/test commands (e.g. `make test`,
   `make build`), use those. Stop here — do not read CI workflows.
2. **Otherwise read the main CI workflow** (`.github/workflows/`
   — typically `ci.yml`/`test.yml`) and extract the test, lint,
   and codegen-sync commands (steps followed by
   `git diff --exit-code`).
3. **Otherwise fall back** by manifest: `Cargo.toml` →
   `cargo build && cargo test && cargo clippy -- -D warnings &&
   cargo fmt --check`; `pyproject.toml` → `pytest -q && ruff check
   && ruff format --check && ty check`; `package.json` → project
   build/test scripts + `tsc --noEmit`; `go.mod` →
   `go build ./... && go test ./... && go vet ./...`.

### 3b. Run the pipeline

1. **Build**, 2. **Test** (iterate on failures until green),
3. **Lint/format**. Run codegen-sync and docs-build checks only if
the fixes touched generated sources or docs. Run supply-chain
audits only if the fixes changed dependency manifests. If a tool
is not installed, skip with a note.

## 4. Commit and push

- Commit fixes as a separate commit (don't squash — preserve
  review history)
- Subject: `fix: resolve code review findings for PR #$PR_NUMBER`;
  body lists findings by severity, fixed vs dismissed (with brief
  reasoning), and pipeline status
- Push (regular push, not force-push)
- Delete any now-resolved `todos/` files the review created

## 5. PR comment

Post a summary via `gh pr comment $PR_NUMBER --repo <owner/name>`:

```
## Review Summary

### Findings

| # | Severity | Finding | Resolution |
|---|----------|---------|------------|
| 1 | P1 | [description] | Fixed: [what was done] |
| 2 | P2 | [description] | Dismissed: [reasoning] |

### Verification

- **Tests**: [pass/fail count, or "no fixes — delegated to CI"]
- **Lint**: [clean/issues]

### Commit

[commit SHA and subject line, or "no changes pushed"]

### Review coverage

[which passes ran: toolkit agents (1 or 3), codex, gemini — and which were skipped and why]
```
