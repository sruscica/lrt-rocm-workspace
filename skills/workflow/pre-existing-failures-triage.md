# Phase 3 Step 3a.5: Pre-existing Failures Triage

> Invoked from Phase 3 Step 3a.5 of `skills/workflow/SKILL.md`. Inputs: `<thinking_dir>/pre-existing-failures.md` and `<owner>/<repo>` (cached from Phase 1). Outputs: `<known_issues_section>` string used in Step 3b PR body composition. Caches `<issue_mode>` for the remainder of the pipeline run. The session reads this file when entering Step 3a.5 and follows the steps below.

3a.5. Pre-existing Failures Triage (only if Phase 2.5 surfaced any):

    **i. Read triage file and short-circuit:**
    Check for `<thinking_dir>/pre-existing-failures.md`. If absent OR the
    `## Failures` table contains zero data rows, skip directly to step 3b
    with `<known_issues_section>` set to empty string.

    Otherwise, parse the file. Extract:
    - The Reproduction Context block (workspace, workspace_head, branch_base,
      base_head, gpu_arch, project, test_command_pattern, submodule_status)
    - All failure rows (test name, suite, classification, evidence, sub-step)

    **ii. Ask user once: live vs draft mode** (cache as `<issue_mode>`):
    Use AskUserQuestion. This decision applies to the entire pipeline run.

    Question: "Pre-existing failures were surfaced. How should I handle GitHub
    issue creation for failures you mark for new-issue tracking?"
    Options:
    - "Create issues live" — session runs `gh issue create` directly
    - "Draft only (manual)" — session emits ready-to-paste issue bodies in the
      PR description; user creates issues manually later

    Cache the answer as `<issue_mode>` (`live` or `draft`).

    **iii. Per-failure GitHub issue search:**
    For each failure row, derive the search keywords:
    - Always include: the test name (or its last path segment if it contains slashes)
    - Always include: the suite name
    - For PRE-EXISTING: add `flaky OR failing`
    - For CANNOT-CLASSIFY: add `flaky`
    - For UNTRIAGED-CANNOT-CLASSIFY: add `failing`

    Run:
    ```
    gh issue list --repo <owner>/<repo> --state open \
      --search "<test_name> <suite> <classification_keywords>" \
      --json number,title,url --limit 10
    ```
    The `<owner>/<repo>` comes from the same source used for `gh pr create`
    (parse from `git -C <workspace> remote get-url origin` if not already cached).

    Capture the result list per failure as `<failure>.candidates` (may be empty).

    **iv. Batched per-category user prompt:**
    Group failures by classification (PRE-EXISTING, CANNOT-CLASSIFY,
    UNTRIAGED-CANNOT-CLASSIFY). For each NON-EMPTY group, emit ONE
    AskUserQuestion with `multiSelect: true`. The question lists every
    failure in the group; each option corresponds to one failure with this
    label format:

    ```
    <test_name> (<suite>) — candidates: #<n1> "<title1>", #<n2> "<title2>", ...
                                       (or "no open issues found")
    ```

    For each failure the user picks one of:
    - **Link to existing #N** — paste the issue number
    - **Create new** — session will create (live) or draft (draft mode)
    - **Skip** — omit from PR body (default if user dismisses)

    Capture per-failure decisions as `<failure>.decision` and
    `<failure>.linked_issue` (only for "link to existing").

    **v. Issue creation / drafting:**
    For each failure with `decision == "create new"`:

    Build the issue title:
    ```
    [<classification>] <test_name> failing in <suite>
    ```

    Build the issue body using this template (substitute live values):
    ```markdown
    ## Failure
    - Test: <suite>::<test_name>
    - Classification: <classification>
    - Triage evidence: <evidence>
    - Detected during: PR #<pr_number_or_pending> pipeline run

    ## Reproduction
    - Workspace: <workspace>
    - Workspace HEAD: <workspace_head>
    - Base branch: <branch_base> @ <base_head>
    - GPU arch: <gpu_arch>
    - Container project: <project>
    - Submodule state at triage time:
      ```
      <submodule_status>
      ```
    - Test command pattern: <test_command_pattern>

    ## Investigation Hints
    - Test source file: <derived_test_path or "unknown — search test suite source">
    - Last commit on test file: <git log -1 --format="%h %s (%ar)" -- <derived_test_path> output, or "unknown">
    - Suggested next steps:
      1. Reproduce against base branch alone (without PR changes)
      2. Re-run with `--repeat 10` to characterize flake rate
      3. Search recent CI runs for the same failure signature

    ## Cross-references
    - Surfacing PR: <pr_url_or_branch_name>
    - Triage data: <thinking_dir>/pre-existing-failures.md
    ```

    Derive `<derived_test_path>` best-effort from the test name (e.g., for
    Google Test names `Suite.Case`, search the workspace for `Case` in test
    sources). If no confident match, use `"unknown — search test suite source"`.
    Do not block on this — investigation hints are best-effort.

    Then:
    - **If `<issue_mode>` == "live"**: run
      ```
      gh issue create --repo <owner>/<repo> --title "<title>" --body "<body>"
      ```
      Capture the returned URL as `<failure>.created_issue_url`.
      If the call fails, log the error, fall back to draft for this failure
      (do not block other failures), and continue.
    - **If `<issue_mode>` == "draft"**: stash the title+body in the session
      under `<failure>.draft_issue` for inclusion in the PR body.

    **vi. Compose `<known_issues_section>`:**
    Build a single markdown string with this structure (omit empty subsections):

    ```markdown
    ## Known Issues Surfaced During This PR

    These tests failed during wider-suite triage and are NOT regressions
    introduced by this PR (or could not be classified within budget).

    ### Linked to existing issues
    | Test | Suite | Classification | Issue |
    |------|-------|----------------|-------|
    | <test> | <suite> | <classification> | #<N> |

    ### New issues filed
    | Test | Suite | Classification | Issue |
    |------|-------|----------------|-------|
    | <test> | <suite> | <classification> | <created_issue_url> |

    ### Suggested issues (please file manually)
    <For each draft failure, render:>

    <details>
    <summary><classification>: <test> (<suite>)</summary>

    **Title:** <issue title>

    **Body:**
    ```
    <issue body>
    ```
    </details>
    ```

    Cache the result as `<known_issues_section>`. If the user skipped every
    failure, set it to empty string.
