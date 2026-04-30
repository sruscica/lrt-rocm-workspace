---
name: bump-rocm-systems-pin
description: Bump TheRock's rocm-systems gitlink to a new SHA after a release-branch PR merges. Dispatched by /pr-feedback or invoked directly with a PR URL or explicit --sha + --branch.
---

# Bump rocm-systems Pin

Update TheRock's pinned `rocm-systems` SHA after a release-branch PR merges. Release-line bumps are manual; develop is auto-bumped elsewhere and is out of scope for this skill.

This skill is pure orchestration. All git operations go through the **git-agent** sub-agent so they inherit the alignment check, READ_ONLY_PINNED gate, and never-commit-detached defenses defined in `agents/DISPATCH-PROTOCOL.md`.

**Usage:**
- `/lrt-rocm:bump-rocm-systems-pin <PR URL>` — preferred; merge SHA and base branch are extracted via `gh`
- `/lrt-rocm:bump-rocm-systems-pin --sha <40-char-sha> --branch release/therock-X.Y` — direct invocation when you already know the target

## Step 0: Parse arguments

Two argument shapes — pick the one matching `$ARGUMENTS`:

**A. PR URL form.** Single argument that is a GitHub PR URL or `owner/repo#number` short form. Parse to extract owner, repo, number. Then:

```
gh pr view <number> --repo <owner>/<repo> --json state,baseRefName,title,mergeCommit,url,headRepository
```

Refuse with a clear error if any of:
- `state != "MERGED"` — say: "PR is `<state>`. This skill bumps the gitlink AFTER the PR has merged. Re-run once the PR is merged."
- `mergeCommit.oid` is null — say: "PR is marked merged but has no merge commit recorded. Cannot proceed."

Set `<new_sha>` = `mergeCommit.oid`, `<release_branch>` = `baseRefName`, `<pr_title>` = `title`, `<pr_url>` = `url`, `<pr_number>` = `number`.

**B. Direct form.** `--sha <40-char-sha> --branch <branch>`. Parse both. Set `<new_sha>` = the value, `<release_branch>` = the value. There is no `<pr_title>`/`<pr_url>`/`<pr_number>` in this form — the commit message will use a generic subject (see Step 6).

If `$ARGUMENTS` matches neither shape, print the usage block above and stop.

## Step 1: Validate base branch is a release line

The base branch (PR form) or `--branch` (direct form) MUST match the regex `^release/therock-[0-9]+\.[0-9]+$`. If it does not, refuse:

> This skill bumps gitlinks for release lines only. Branch `<release_branch>` is not a release line. The mainline `develop` branch is auto-bumped by upstream automation and does not need a manual bump. If you believe this branch should be supported, file an issue.

Stop. Do not dispatch git-agent.

## Step 2: Resolve TheRock workspace

Same logic as `pr-feedback` Step 2:

```
test -f /.dockerenv && echo "DOCKER=yes" || echo "DOCKER=no"
printenv THEROCK_WORK_DIR PROJECT
```

- Inside Docker with `THEROCK_WORK_DIR` set → `<workspace>` = `THEROCK_WORK_DIR`
- Outside Docker → ask the user for the TheRock workspace path

Validate that `<workspace>/rocm-systems/` exists as a directory. If not, refuse: "`<workspace>` does not look like a TheRock workspace (no `rocm-systems/` submodule). Aborting."

## Step 3: Dispatch git-agent for alignment check

Dispatch git-agent. The skill itself runs no git commands — git-agent owns all git operations.

```
Agent(subagent_type: "git-agent", prompt: """
You are the git-agent in the ROCm Agent Pipeline.
You do NOT have the Agent tool.

COMMAND RULES (mandatory):
- NEVER use `cd /path && git ...` → use `git -C /path ...`
- NEVER use `echo "$VAR"` → use `printenv VAR`
- NEVER use brace expansion `{a,b,c}` → spell out each argument
- NEVER use `$VAR` in any command → use `printenv VAR`

## Task

A release-line gitlink bump is being prepared. Before any commit can happen,
verify alignment for the matching release branch.

Workspace: <workspace>
Target rocm-systems branch: <release_branch>

Do the following and report results:

1. Run `git -C <workspace> branch --show-current` and record TheRock's current branch.
2. Run `git -C <workspace> rev-parse HEAD:rocm-systems` and record the current pinned rocm-systems SHA.
3. Run the canonical 7-step rocm-systems alignment check (per agents/DISPATCH-PROTOCOL.md), with the mapped branch hard-set to `<release_branch>` (do NOT re-derive from TheRock's current branch — the caller has already validated the mapping).
4. Report the canonical `ALIGNMENT_CHECK:` line per the schema in agents/DISPATCH-PROTOCOL.md.

DO NOT commit anything. DO NOT branch. DO NOT push. This is a verification-only dispatch.

## Required output format

Emit (anchored, one per line, exact prefixes):

THEROCK_BRANCH: <branch name from step 1>
PINNED_SHA: <40-char hex from step 2>
ALIGNMENT_CHECK: <one of the 5 enum values from agents/DISPATCH-PROTOCOL.md>

If your alignment check produced a divergence report, include it verbatim under
the marker `--- DIVERGENCE REPORT ---` after the lines above.
""")
```

## Step 4: Branch on alignment result

Parse the git-agent output for the three required lines (`THEROCK_BRANCH:`, `PINNED_SHA:`, `ALIGNMENT_CHECK:`). If any is missing or malformed, halt and tell the user:

> git-agent did not return the expected alignment-check schema. Cannot proceed. Re-run the skill — this may be a transient agent output issue.

Then branch on the values:

- **`ALIGNMENT_CHECK: ATTACHED_AND_PROCEEDED` AND `THEROCK_BRANCH == <release_branch>`** → continue to Step 5.
- **`ALIGNMENT_CHECK: ATTACHED_AND_PROCEEDED` AND `THEROCK_BRANCH != <release_branch>`** → halt:
  > TheRock is on branch `<actual>`. To bump the gitlink for `<release_branch>`, you must first check out the matching release branch in TheRock. Run `git -C <workspace> checkout <release_branch>` and re-invoke this skill.
- **`ALIGNMENT_CHECK: DIVERGENCE_HALTED`** → halt:
  > rocm-systems on `<release_branch>` has diverged from TheRock's pinned SHA. Bump cannot proceed safely. The divergence report from git-agent:
  >
  > <divergence report verbatim>
  >
  > Resolve via `/workflow` first, then re-invoke this skill.
- **`ALIGNMENT_CHECK: FORK_BRANCH_AMBIGUOUS`** → halt:
  > git-agent cannot map TheRock's current branch to a rocm-systems branch (TheRock appears to be on a fork branch). Check out the release branch first: `git -C <workspace> checkout <release_branch>`, then re-invoke this skill.
- **`ALIGNMENT_CHECK: TRIGGER_DID_NOT_FIRE` or `NOT_APPLICABLE`** → halt:
  > Unexpected alignment-check verdict `<verdict>` for a release-line bump. This indicates a workspace state the skill does not handle. Aborting.

The `ALIGNMENT_CHECK:` enum is exactly the 5 canonical values defined in `agents/DISPATCH-PROTOCOL.md` (`NOT_APPLICABLE`, `TRIGGER_DID_NOT_FIRE`, `ATTACHED_AND_PROCEEDED`, `DIVERGENCE_HALTED`, `FORK_BRANCH_AMBIGUOUS`). `READ_ONLY_PINNED` is a session-mode concept from `/workflow`'s Phase 1.5 pre-flight; it does NOT propagate to this standalone skill, and git-agent does not emit it on the `ALIGNMENT_CHECK:` line. If a user has independently set their workspace into a state that should refuse commits, git-agent's commit-time defenses (Step 6) will catch it.

In every halt case, do NOT dispatch git-agent again. Stop.

### Idempotence — already at target SHA

If `PINNED_SHA == <new_sha>` (full 40-char comparison), the gitlink is already
at the target SHA and there is nothing to bump. Exit cleanly:

> TheRock's `rocm-systems` gitlink on `<release_branch>` is already at
> `<short_new>`. Nothing to do.

Do NOT proceed to Step 5. This makes re-invocation safe — a user (or the
`/pr-feedback` Step 7 re-prompt) can run this skill on the same PR multiple
times without creating duplicate commits.

## Step 5: Show preview and confirm

Compute `<short_old>` = first 12 chars of `PINNED_SHA`, `<short_new>` = first 12 chars of `<new_sha>`.

Present:

> **Gitlink bump preview**
>
> - TheRock branch:     `<release_branch>`
> - rocm-systems pin:   `<short_old>` → `<short_new>`
> - Source PR:          `<pr_url>` (PR #`<pr_number>`: `<pr_title>`)   *(omit this line in direct form)*
>
> Create the bump commit?

Wait for explicit `yes`/`no`. On no, exit cleanly: "No commit created. Done." On yes, continue.

## Step 6: Dispatch git-agent for the bump

Construct the commit subject. PR form:

```
Bump rocm-systems to <short_new> on <release_branch> (PR #<pr_number>: <pr_title>)
```

Direct form:

```
Bump rocm-systems to <short_new> on <release_branch>
```

Commit body (PR form): `Source: <pr_url>`. Direct form: omit body.

Dispatch git-agent:

```
Agent(subagent_type: "git-agent", prompt: """
You are the git-agent in the ROCm Agent Pipeline.
You do NOT have the Agent tool.

COMMAND RULES (mandatory):
- NEVER use `cd /path && git ...` → use `git -C /path ...`
- NEVER use `echo "$VAR"` → use `printenv VAR`
- NEVER use brace expansion `{a,b,c}` → spell out each argument
- NEVER use `$VAR` in any command → use `printenv VAR`

## Task

Land the rocm-systems gitlink bump that the user just confirmed.

Workspace: <workspace>
Target rocm-systems branch: <release_branch>
Target merge SHA: <new_sha>

Steps:

1. Run the canonical 7-step rocm-systems alignment check again (per agents/DISPATCH-PROTOCOL.md) with mapped branch `<release_branch>`. If the result is anything other than ATTACHED_AND_PROCEEDED, REFUSE and report the verdict — do not proceed.
2. Run `git -C <workspace>/rocm-systems fetch origin <release_branch>`.
3. Run `git -C <workspace>/rocm-systems checkout <release_branch>`.
4. Run `git -C <workspace>/rocm-systems pull --ff-only origin <release_branch>`.
5. Verify the local rocm-systems HEAD now equals or is a fast-forward descendant of <new_sha>: run `git -C <workspace>/rocm-systems merge-base --is-ancestor <new_sha> HEAD` and check the exit code. If non-zero, REFUSE — the merge SHA is not reachable from the release branch tip.
6. Stage the gitlink change in TheRock: `git -C <workspace> add rocm-systems`.
7. Confirm `git -C <workspace> diff --cached --name-only` shows ONLY `rocm-systems`. If anything else is staged, REFUSE — the user has unstaged work that must not be silently included.
8. Commit:

```
git -C <workspace> commit -m "<commit subject>" \
                         <add -m "<commit body>" if PR form>
```

9. Report the new TheRock commit SHA via:

```
COMMIT_SHA: <40-char hex>
```

10. Re-emit the canonical alignment-check line:

```
ALIGNMENT_CHECK: <enum>
```

DO NOT push. Push is a separate dispatch.
""")
```

If git-agent reports a refusal at any step, present the refusal to the user verbatim and exit. Do not retry, do not work around.

If git-agent reports `COMMIT_SHA:` and `ALIGNMENT_CHECK: ATTACHED_AND_PROCEEDED`, continue to Step 7.

## Step 7: Push gate

Present:

> Bump commit created: `<COMMIT_SHA short>` on `<release_branch>`.
>
> Push to `origin/<release_branch>`?

Wait for explicit `yes`/`no`. On no:

> Commit is local. To push later: `git -C <workspace> push origin <release_branch>`. Re-invoking this skill will short-circuit (idempotence detects the gitlink already at the target SHA) and will NOT re-offer push — push by hand if you skip it now.

On yes, dispatch git-agent:

```
Agent(subagent_type: "git-agent", prompt: """
You are the git-agent in the ROCm Agent Pipeline.
You do NOT have the Agent tool.

COMMAND RULES (mandatory):
- NEVER use `cd /path && git ...` → use `git -C /path ...`
- NEVER use `echo "$VAR"` → use `printenv VAR`
- NEVER use brace expansion `{a,b,c}` → spell out each argument
- NEVER use `$VAR` in any command → use `printenv VAR`

## Task

Push the bump commit just created.

Workspace: <workspace>
Branch: <release_branch>

Run `git -C <workspace> push origin <release_branch>` and report the result.

If the push is rejected (non-fast-forward, protected branch, etc.), do NOT force-push. Report the rejection reason and stop.
""")
```

Present git-agent's push result verbatim. Done.
