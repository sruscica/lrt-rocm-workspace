---
name: pr-feedback
description: Fetch and triage PR review comments with expert assessment, then optionally transition to /workflow to address them
---

# PR Feedback

Review and triage pull request comments with expert assessment on what should be addressed.

**Usage:** `/pr-feedback <PR URL or owner/repo#number>`

## Step 1: Parse PR reference

Parse `$ARGUMENTS` to extract the PR:

- Full URL: `https://github.com/owner/repo/pull/123` → extract owner, repo, number
- Short form: `owner/repo#123` → extract directly
- Number only: `#123` or `123` → determine owner/repo from the current git remote

Run:
```
gh pr view <number> --repo <owner>/<repo> --json title,headRefName,baseRefName,state,url,body
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
  Author: <author>
  File: <path> (line <line>)
  Body: <comment body>
---

### PR Diff (for context)

<PR diff, truncated if very large>

### Classification

For each comment, provide:
1. **Classification**: one of:
   - **Actionable** — a legitimate issue that should be fixed (bug, missing validation,
     style violation per project conventions, etc.)
   - **Informational** — no code change needed (praise, acknowledgment, explanation,
     question already answered by the code)
   - **Discussion** — needs the PR author's input before deciding (design question,
     trade-off choice, scope question)
2. **Reasoning**: one sentence explaining why
3. **Suggested fix** (actionable only): brief description of what to change

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

Write this file using the Write tool. Match each expert classification to its comment
by file path and line number (the expert's output references the same comment numbers
and file locations as the API data).

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
   ```

   If only gaps exist (no actionable items), omit the "Review feedback" section and
   the assessment-file reference. If only actionable items exist, omit the
   "Verification gaps" section and the gaps-file reference.

3. **Invoke the workflow skill:**
   ```
   Skill(skill: "lrt-rocm:workflow", args: "<task description>")
   ```

The workflow pipeline will detect `branch_action: use-existing` (the PR branch
is already checked out) and proceed with the regular Phase 1 → Phase 2 → Phase 3 flow.
The expert assessment file provides context for the pipeline's specialists.
