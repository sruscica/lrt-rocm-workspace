# Phase 3 Step 3d: PR Feedback Handoff

> Invoked from Phase 3 Step 3d of `skills/workflow/SKILL.md` ONLY when the task description was passed a `pr-context.json` file by the `pr-feedback` skill. If no such file is in scope, the session skips this step entirely. The session reads this file when entering Step 3d and follows the steps below.

3d. Handle PR review comment updates (PR feedback tasks only):

    **Detection (structured marker, not prose match):**
    Parse the task description for a line matching the line-anchored regex
    `^PR_CONTEXT: (\S+)$`. The pr-feedback skill emits this marker as the
    final structured handoff line.

    - If no line in the task description matches the regex: skip to Step 3e
      (this is a normal workflow, not PR feedback). Do NOT search the task
      description for prose mentions of `pr-context.json` — they are not the
      handoff signal.
    - If a line matches: capture the path. Run `test -f <path>` to verify the
      file exists. If `test` fails, log a warning to the user
      ("PR_CONTEXT marker present but file missing at <path> — skipping PR
      feedback handoff") and skip to Step 3e.
    - If both checks pass, read the file. It contains `owner`, `repo`,
      `pr_number`, and a `comments` array with `id`, `node_id`,
      `classification`, and `fix_summary` for each review comment.

    **Reply to actionable comments:**
    First, get the current short commit hash:
    ```
    git -C <workspace> rev-parse --short HEAD
    ```
    Store this as `<commit_short>`. Then for each comment where `classification`
    is `"actionable"`, reply with the fix summary:
    ```
    gh api repos/<owner>/<repo>/pulls/<pr_number>/comments/<comment_id>/replies \
      -f body="Addressed in <commit_short>: <fix_summary>

🤖 *Claude Code* 🤖"
    ```
    Use inline values for all fields. Do NOT use variable expansion or command
    substitution.

    **Resolve comment threads:**
    For each actionable comment, resolve its review thread via GraphQL.
    First, query the thread ID from the comment's node_id:
    ```
    gh api graphql -f query='query { node(id: "<node_id>") { ... on PullRequestReviewComment { pullRequestReview { id } pullRequestReviewThread: thread { id } } } }'
    ```
    Extract the thread `id` from the response, then resolve it:
    ```
    gh api graphql -f query='mutation { resolveReviewThread(input: {threadId: "<thread_id>"}) { thread { isResolved } } }'
    ```

    **Update PR description:**
    Fetch the current PR body:
    ```
    gh pr view <pr_number> --repo <owner>/<repo> --json body --jq '.body'
    ```
    Append a section summarizing the addressed feedback:
    ```
    ## Review feedback addressed

    | Comment | File | Fix |
    |---------|------|-----|
    | <body_excerpt> | `<path>:<line>` | <fix_summary> |
    ...

    Commit: <short hash>

    🤖 *Claude Code* 🤖
    ```
    Update the PR body:
    ```
    gh pr edit <pr_number> --repo <owner>/<repo> --body "<updated body>"
    ```

    **Outcome accumulation (run inline with the loop, not at the end):**
    For each comment processed in the steps above, build a record:
    ```json
    {
      "comment_id": <id>,
      "node_id": "<node_id>",
      "path": "<path>",
      "line": <line>,
      "classification": "<classification>",
      "reply_posted": true | false,
      "reply_error": null | "<error message>",
      "thread_resolved": true | false,
      "thread_error": null | "<error message>"
    }
    ```
    For non-actionable comments (informational/discussion), set both
    `reply_posted` and `thread_resolved` to `false` with `reply_error` /
    `thread_error` set to `"skipped: not actionable"` — this preserves a
    full audit trail of what was considered.

    For the PR description update, track separately:
    ```json
    { "pr_body_updated": true | false, "pr_body_error": null | "<error>" }
    ```

    **Write outcome file (after the loop completes, even on partial failure):**
    Compose the full outcome and write it to
    `<thinking_dir>/pr-feedback-outcome.json`:
    ```json
    {
      "pr_number": <pr_number>,
      "owner": "<owner>",
      "repo": "<repo>",
      "commit_short": "<commit_short>",
      "pr_body_updated": <bool>,
      "pr_body_error": <null | string>,
      "comments": [ <records from the loop> ]
    }
    ```
    Use the Write tool with the absolute path. If this file write itself
    fails, log to the user and continue (do not retry, do not block) — the
    user-facing summary below still works from in-memory state in that case.

    **Error handling:** Failures in this step (API errors, permission issues)
    should be reported to the user but MUST NOT block the pipeline. If a
    reply, resolve, or description update fails, log the error in the
    outcome record and continue with the remaining comments. Present a
    summary of what succeeded and what failed (Phase 3 Step 1 reads the
    outcome file and surfaces it to the user).
