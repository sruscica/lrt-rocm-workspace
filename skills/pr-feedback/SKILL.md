---
name: pr-feedback
description: Fetch and triage PR review comments with expert assessment, then optionally transition to /workflow to address them
---

# PR Feedback

Review and triage pull request comments with expert assessment on what should be addressed.

**Usage:**
- `/pr-feedback <PR URL or owner/repo#number>` — triage mode (default)
- `/pr-feedback verify <PR URL or owner/repo#number>` — verify-mode round-trip check

## Step 0: Argument disambiguation

Parse `$ARGUMENTS`:

- If the first whitespace-separated token is the literal word `verify` (case-insensitive), this is **verify mode**. The remaining argument(s) form the PR reference. Branch immediately to **Step V1: Verify Mode** at the bottom of this file. Do NOT continue to Step 1.
- Otherwise this is **triage mode** (the original flow). Continue to Step 1 with `$ARGUMENTS` as the PR reference.

If `$ARGUMENTS` is `verify` with no PR reference: search the workspace for a recent `pr-context.json` (look in `<artifact_base>/thinking/*-pr-*-feedback/pr-context.json`, sorted by modification time, newest first). If exactly one is found, use it and continue. If zero or multiple are found, ask the user to specify the PR.

## Step 1: Parse PR reference

Parse `$ARGUMENTS` to extract the PR:

- Full URL: `https://github.com/owner/repo/pull/123` → extract owner, repo, number
- Short form: `owner/repo#123` → extract directly
- Number only: `#123` or `123` → determine owner/repo from the current git remote

Run:
```
gh pr view <number> --repo <owner>/<repo> --json title,headRefName,baseRefName,state,url,body,mergeCommit
```

Present to the user:
> PR #<number>: <title>
> Branch: <headRefName> → <baseRefName>
> Status: <state>

If the PR is merged or closed, warn the user and ask if they want to continue.

## Step 2: Gather environment and workspace

Determine the local workspace for this repo:

```
# Check Docker environment
test -f /.dockerenv && echo "DOCKER=yes" || echo "DOCKER=no"
printenv THEROCK_WORK_DIR PROJECT
```

Match the repo to a local workspace path. If uncertain, ask the user.

Determine `<artifact_base>`:
- Inside Docker with THEROCK_WORK_DIR set → `<artifact_base>` = THEROCK_WORK_DIR
- Otherwise → `<artifact_base>` = workspace path

Create a thinking directory:
```
mkdir -p <artifact_base>/thinking/YYYY-MM-DD-pr-<number>-feedback
```

## Step 3: Fetch PR comments

Fetch all review feedback:

```
gh api repos/<owner>/<repo>/pulls/<number>/comments
gh api repos/<owner>/<repo>/pulls/<number>/reviews
```

The first command returns inline code review comments (attached to specific lines).
The second returns top-level review summaries (approve/request changes/comment).

Also fetch the PR diff for context:
```
gh pr diff <number> --repo <owner>/<repo>
```

Write the raw data to `<thinking_dir>/pr-comments.md` for reference.

If there are no comments, **do not stop yet** — continue to Step 3.5. The PR may still
have verification gaps worth surfacing even without reviewer activity.

## Step 3.5: Detect verification gaps

Verification gaps are objective signals that the PR is incomplete, separate from any
reviewer feedback. Two sources:

### A. Unchecked Test plan items

The `body` field fetched in Step 1 may contain a `## Test plan` section with checklist
items. Extract any unchecked items from that section.

Parsing rules (apply in order):
1. Locate the line matching `## Test plan` (case-insensitive on "Test plan", `##` exact).
2. Collect every subsequent line until the next `##`-level heading or end of body.
3. From that range, extract lines matching `- [ ]` (with a single space inside the brackets).
   - Treat `- [x]` and `- [X]` as checked → ignore.
   - Capture only the bullet's first line of text. If the item wraps onto subsequent
     indented lines, take just the first line.
4. Lines matching `- [ ]` that appear *outside* the `## Test plan` section are ignored.
5. If no `## Test plan` heading is found, record "No `## Test plan` section found" and
   produce zero unchecked items (this is not an error).

### B. CI status

Run:
```
gh pr checks <number> --repo <owner>/<repo>
```

Capture any check that is failing or pending. Passing/skipped checks are not gaps.
If `gh pr checks` errors (e.g., no checks configured), record "No CI checks
configured" and treat as zero CI gaps.

### Output

Write `<thinking_dir>/verification-gaps.md` with two subsections:

```markdown
# Verification Gaps for PR #<number>

## Unchecked Test plan items
- <verbatim text of each unchecked item>
- ...
(or: "No `## Test plan` section found" / "All Test plan items checked")

## CI status
- <check name>: <state> — <description>
- ...
(or: "No CI checks configured" / "All CI checks passing")
```

If both subsections are empty (no unchecked items AND no failing/pending checks),
write a single line: "No verification gaps detected."

### Combined stop condition

If Step 3 found zero comments AND Step 3.5 found no verification gaps, report
"No review comments or verification gaps found on this PR." and stop.

## Step 4: Select expert and dispatch for assessment

If Step 3 found zero comments (but verification gaps exist), skip the expert dispatch
entirely and proceed to Step 4b with an empty comments array. There are no comments
to classify.

Determine which expert to dispatch based on the files touched by PR comments:

| Comment file extensions | Expert |
|------------------------|--------|
| `.sh`, Dockerfile, `.yaml`, `.json`, `.toml`, config | `bash-expert` |
| `.cpp`, `.hip`, `.c`, `.h`, `.hpp`, `.cmake`, `CMakeLists.txt` | `hip-expert` |
| Mixed or unclear | `hip-expert` (default) |

Dispatch the selected expert:

```
Agent(subagent_type: "<expert>", prompt: """
You are the <expert> in the ROCm Agent Pipeline.
You do NOT have the Agent tool.

COMMAND RULES (mandatory):
- NEVER use `cd /path && git ...` → use `git -C /path ...`
- NEVER use `echo "$VAR"` → use `printenv VAR`
- NEVER use brace expansion `{a,b,c}` → spell out each argument
- NEVER use `$VAR` in any command → use `printenv VAR`

## Task

Assess the following PR review comments and classify each one.

PR: <owner>/<repo>#<number> — <title>
Branch: <headRefName> → <baseRefName>

### Review Comments

<for each comment, include:>
---
Comment #<n>:
  Comment ID: <api id from Step 3 — integer, e.g. 1234567890>
  Author: <author>
  File: <path> (line <line>)
  Body: <comment body>
---

### PR Diff (for context)

<PR diff, truncated if very large>

### Classification

For each comment, provide:
1. **Comment ID**: echo the Comment ID exactly as given in the input. The session
   uses this as the match key to merge your classifications back into the API
   data — if it is missing or wrong, the comment will be defaulted to
   informational and no reply will be posted.
2. **Classification**: one of:
   - **Actionable** — a legitimate issue that should be fixed (bug, missing validation,
     style violation per project conventions, etc.)
   - **Informational** — no code change needed (praise, acknowledgment, explanation,
     question already answered by the code)
   - **Discussion** — needs the PR author's input before deciding (design question,
     trade-off choice, scope question)
3. **Reasoning**: one sentence explaining why
4. **Suggested fix** (actionable only): brief description of what to change

Write your assessment to <thinking_dir>/expert-assessment.md
""")
```

## Step 4b: Write structured PR context

After the expert assessment completes, write `<thinking_dir>/pr-context.json` combining
the raw comment data (IDs from Step 3) with the expert's classifications (from Step 4).

The session already has the raw API response from Step 3. Extract the relevant fields
and merge with the expert's classification for each comment:

```json
{
  "owner": "<owner>",
  "repo": "<repo>",
  "pr_number": <number>,
  "title": "<PR title>",
  "comments": [
    {
      "id": <comment id from API>,
      "node_id": "<comment node_id from API>",
      "path": "<file path>",
      "line": <line number>,
      "author": "<comment author>",
      "body_excerpt": "<first 100 chars of comment body>",
      "classification": "actionable|informational|discussion",
      "fix_summary": "<expert's suggested fix, or null if not actionable>"
    }
  ]
}
```

Write this file using the Write tool.

**Match logic (id-based, deterministic):** Build a map from Comment ID to
classification by parsing the `Comment ID:` lines in the expert's assessment.
For each comment in the API response, look up its `id` in this map.

`(file, line)` is NOT a usable match key because it can collide: two reviewers
can comment on the same line, a reviewer can leave multiple comments on one
line, and file-level review comments have `line: null` which collides with
every other null-line comment in the same file. The Comment ID is unique per
comment in the GitHub API and is the only safe key.

**Fallback for unmatched comments** (expert omitted the Comment ID, or returned
an ID not in the API set):
- `classification: "informational"`
- `fix_summary: null`
- Log a warning to the user: `"Expert assessment did not classify comment <id>
  (<path>:<line>) — defaulting to informational, no reply will be posted."`

Informational is the safe default — Phase 3 Step 3d (in the workflow skill)
skips reply posting and thread resolution for informational comments, so a
missed classification becomes a no-op rather than a misattributed reply on
the wrong comment thread.

## Step 5: Present assessment

Read the expert's assessment (if dispatched) and the verification gaps file, then
present them grouped by category. Verification Gaps come first because they are
objective and typically blocking; reviewer feedback follows.

### Verification Gaps
Read `<thinking_dir>/verification-gaps.md` and present its contents directly. If the
file says "No verification gaps detected.", omit this section entirely.

### Actionable Items
For each actionable comment:
> **Comment #<n>** (<author> on `<file>:<line>`):
> <comment body>
> Expert recommendation: <suggested fix>

### Discussion Items
For each discussion comment:
> **Comment #<n>** (<author>):
> <comment body>
> This needs your input — <expert's note>

### Informational
> <count> informational comments (no action needed). See `<thinking_dir>/expert-assessment.md` for details.

Then ask the user, adapting to what was found:
- If both gaps and actionable items exist: "Would you like to address the actionable items and close out the verification gaps?"
- If only gaps exist: "Would you like to close out the verification gaps?"
- If only actionable items exist: "Would you like to address the actionable items?"

If there are discussion items, also ask the user to resolve them. Incorporate their
decisions into the actionable list.

## Step 6: Transition to /workflow

If the user says no: Done. The assessment is saved at `<thinking_dir>/` for reference.

If the user says yes:

1. **Check out the PR branch** if not already on it:
   ```
   git -C <workspace> checkout <headRefName>
   ```

2. **Construct task description** from the verification gaps and actionable items.
   Assemble in this order, omitting any section that has no items:

   ```
   Address PR #<number> (<owner>/<repo>):

   ## Verification gaps to close out
   <for each unchecked Test plan item:>
   - <verbatim item text>
   <for each failing/pending CI check:>
   - CI: <check name> is <state>

   ## Review feedback to address
   <for each actionable item:>
   - [<file>:<line>] <summary of what to fix>

   Expert assessment: <thinking_dir>/expert-assessment.md (if dispatched)
   PR comments: <thinking_dir>/pr-comments.md
   PR context: <thinking_dir>/pr-context.json
   Verification gaps: <thinking_dir>/verification-gaps.md

   PR_CONTEXT: <absolute path to pr-context.json>
   ```

   The final `PR_CONTEXT:` line is a structured handoff marker that the workflow
   skill's Phase 3 Step 3d uses to detect PR feedback tasks. It MUST:
   - Be on its own line, anchored at the start of the line (no leading whitespace).
   - Contain the literal prefix `PR_CONTEXT: ` followed by the absolute path.
   - Use the absolute path (not the `<thinking_dir>/` shorthand) — the path is
     consumed by `test -f` and parsed by line-anchored regex.

   This marker is required regardless of which sections (gaps, actionable, or
   both) are present in the task description above. Always include it whenever
   `pr-context.json` was written in Step 4b.

   If only gaps exist (no actionable items), omit the "Review feedback" section and
   the assessment-file reference. If only actionable items exist, omit the
   "Verification gaps" section and the gaps-file reference.

   **Handoff contract.** This task description hands off to `/workflow`, which
   runs its full Phase 1 → Phase 3 flow. The user gates in `/workflow` Phase 3
   (review offer and push confirmation) ALWAYS apply — including for PR-feedback
   tasks. Do not embed imperative push or commit instructions ("After commit,
   push to the PR branch...") in the task description: the workflow will offer
   to commit and push at the appropriate gates regardless. The `PR_CONTEXT:`
   marker above is the only structured handoff signal `/workflow` needs.

3. **Invoke the workflow skill:**
   ```
   Skill(skill: "lrt-rocm:workflow", args: "<task description>")
   ```

The workflow pipeline will detect `branch_action: use-existing` (the PR branch
is already checked out) and proceed with the regular Phase 1 → Phase 2 → Phase 3 flow.
The expert assessment file provides context for the pipeline's specialists.

## Step 7: Post-merge gitlink bump offer (release-line PRs only)

This step runs after Step 6 ONLY when Step 6 did not transition to `/workflow`
(i.e., the user said no, or there were no actionable items / gaps to ask about
in the first place). If `/workflow` was invoked, this skill has already ended
and Step 7 is unreachable.

### Trigger conditions (ALL must hold)

Inspect the PR data already fetched in Step 1:

- `state == "MERGED"`
- The repo (from the parsed PR reference, case-insensitive) is `rocm-systems`
- `baseRefName` matches the regex `^release/therock-[0-9]+\.[0-9]+$`

If any condition fails, this step is a no-op — return silently. Existing
behavior is unchanged for unmerged PRs, non-rocm-systems PRs, and
develop-target PRs.

### Behavior when triggered

Compute `<short_sha>` = first 12 chars of `mergeCommit.oid` (already in the
Step 1 fetch). Present:

> This PR was merged into `<baseRefName>`. TheRock pins `rocm-systems` per
> branch, so the matching TheRock release branch needs its gitlink bumped to
> `<short_sha>`.
>
> Update TheRock's gitlink for `<baseRefName>` now?

Wait for explicit `yes`/`no`.

- **no** → exit cleanly: "Skipping gitlink bump. To run it later: `/lrt-rocm:bump-rocm-systems-pin <PR URL>`."
- **yes** → invoke the bump skill:

  ```
  Skill(skill: "lrt-rocm:bump-rocm-systems-pin", args: "<PR URL>")
  ```

The bump skill handles workspace resolution, alignment check via git-agent,
preview, commit, and push gate independently. This skill's responsibility ends
once the bump skill is invoked.

### Note on re-entry

A user may re-run `/pr-feedback` on the same merged PR multiple times (e.g.,
after addressing follow-up reviewer comments that landed post-merge). Step 7
re-fires every time. The bump skill itself detects whether the gitlink is
already at the merge SHA and exits without creating a duplicate commit, so the
re-prompt is harmless.

---

## Step V1: Verify Mode (entered from Step 0)

Verify mode is **strictly read-only**. It checks whether a prior `/pr-feedback` →
`/workflow` round trip actually landed on GitHub. It NEVER mutates GitHub state:
no `gh pr edit`, no `gh pr comment`, no GraphQL mutations, no posting replies.

### V1.1: Resolve context

The verify run needs two things: the cached `pr-context.json` (what we intended
to address) and the live PR state (what's actually on GitHub).

Resolve the PR reference and the cached context:

- If a `pr-context.json` path was inferred in Step 0 from the workspace search,
  read it directly. The PR reference comes from the file's `owner`, `repo`,
  `pr_number` fields.
- If a PR reference was given on the command line: parse it (same rules as
  Step 1 of triage mode), then search the workspace for a matching
  `pr-context.json` (filter by `pr_number` field). If none found, tell the user:
  > Verify mode requires a cached `pr-context.json` from a prior `/pr-feedback`
  > run. None found for PR #<number>. Pure-from-URL verification (without a
  > cached context) is not supported — there is no record of which comments
  > we intended to address.

### V1.2: Fetch live PR state

Run (all read-only):

```
gh pr view <number> --repo <owner>/<repo> --json body,headRefName,state,url
gh api repos/<owner>/<repo>/pulls/<number>/comments
```

For each comment in the cached context, query its current thread state via
GraphQL (read-only query, no mutation):

```
gh api graphql -f query='query { node(id: "<node_id>") { ... on PullRequestReviewComment { id databaseId pullRequestReview { id } } } }'
```

Then query the thread resolution status. The simplest read-only path is to
fetch all review threads on the PR once and index them locally:

```
gh api graphql -f query='query { repository(owner: "<owner>", name: "<repo>") { pullRequest(number: <number>) { reviewThreads(first: 100) { nodes { id isResolved comments(first: 1) { nodes { databaseId } } } } } }'
```

Index by `databaseId` of the first comment in each thread. Match each cached
comment's `id` (which is `databaseId`) to find its thread's `isResolved`.

### V1.3: Match and detect drift

For each comment in the cached `pr-context.json`:

- **Skipped (not actionable):** classification was `informational` or
  `discussion`. No reply expected. No thread resolution expected.
  Verify outcome: `skipped` (always passes — nothing to check).
- **Actionable:** classification was `actionable`. Expected:
  1. A reply from us containing the marker `🤖 *Claude Code* 🤖` on this
     comment thread.
  2. The review thread is resolved (`isResolved: true`).
  3. The PR body contains the `## Review feedback addressed` section with a
     row referencing this comment.

For each expected item, mark `present` or `missing` based on the live state.

### V1.4: Report drift

Present a per-comment table:

```
| Comment | File:Line | Reply | Thread | PR body row |
|---------|-----------|-------|--------|-------------|
| #<id>   | <path>:<line> | ✅ posted | ✅ resolved | ✅ present |
| #<id>   | <path>:<line> | ❌ missing | ❌ unresolved | ❌ missing |
| #<id>   | <path>:<line> | — skipped (informational) | — | — |
```

Below the table, summary line:
> Round trip: <N> actionable comments, <K> fully addressed, <M> with drift.

If `M > 0`, suggest next steps to the user:
> To address the drift, either:
> 1. Re-run `/workflow` with the original PR feedback task (the existing
>    `pr-context.json` will be picked up by Phase 3 Step 3d).
> 2. Manually post replies and resolve threads via the GitHub UI for items
>    you've already addressed locally.

If `M == 0`: print one line:
> Round trip verified: all actionable items addressed.

Verify mode ends here. Do not transition to `/workflow`. Do not modify any
GitHub state. Done.
