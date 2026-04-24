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
gh pr view <number> --repo <owner>/<repo> --json title,headRefName,baseRefName,state,url
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

If there are no comments, report "No review comments found on this PR." and stop.

## Step 4: Select expert and dispatch for assessment

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

## Step 5: Present assessment

Read the expert's assessment and present it grouped by classification:

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

Then ask: "Would you like to address the actionable items?"

If there are discussion items, also ask the user to resolve them. Incorporate their
decisions into the actionable list.

## Step 6: Transition to /workflow

If the user says no: Done. The assessment is saved at `<thinking_dir>/` for reference.

If the user says yes:

1. **Check out the PR branch** if not already on it:
   ```
   git -C <workspace> checkout <headRefName>
   ```

2. **Construct task description** from the actionable items:
   ```
   Address PR #<number> review feedback (<owner>/<repo>):
   <for each actionable item:>
   - [<file>:<line>] <summary of what to fix>
   
   Expert assessment: <thinking_dir>/expert-assessment.md
   PR comments: <thinking_dir>/pr-comments.md
   ```

3. **Invoke the workflow skill:**
   ```
   Skill(skill: "lrt-rocm:workflow", args: "<task description>")
   ```

The workflow pipeline will detect `branch_action: use-existing` (the PR branch
is already checked out) and proceed with the regular Phase 1 → Phase 2 → Phase 3 flow.
The expert assessment file provides context for the pipeline's specialists.
