# Phase 3 Step 3d: PR Feedback Handoff

> Invoked from Phase 3 Step 3d of `skills/workflow/SKILL.md` ONLY when the task description was passed a `pr-context.json` file by the `pr-feedback` skill. If no such file is in scope, the session skips this step entirely. The session reads this file when entering Step 3d and follows the steps below.

3d. Handle PR review comment updates (PR feedback tasks only):

    Check if the task description references a `pr-context.json` file.
    If not found: skip to Step 3e (this is a normal workflow, not PR feedback).

    If found, read the file. It contains `owner`, `repo`, `pr_number`, and a
    `comments` array with `id`, `node_id`, `classification`, and `fix_summary`
    for each review comment.

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

    **Error handling:** Failures in this step (API errors, permission issues)
    should be reported to the user but MUST NOT block the pipeline. If a
    reply, resolve, or description update fails, log the error and continue
    with the remaining comments. Present a summary of what succeeded and
    what failed.
