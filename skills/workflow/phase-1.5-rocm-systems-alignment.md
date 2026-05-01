# Phase 1.5: rocm-systems Alignment Pre-Flight

> **This is a reference file for the `/workflow` skill.** The session reads this file during Phase 1.5 execution. It is also the authoritative source for the alignment check procedure that DISPATCH-PROTOCOL.md references for per-agent re-verification.

## Why This Phase Exists

TheRock pins `rocm-systems` via gitlink (a specific SHA). After `git submodule update`, `rocm-systems` lands in detached HEAD. Any commit an agent makes in detached HEAD is silently abandoned the next time the submodule moves. Switching TheRock branches does NOT move `rocm-systems`, so the workspace can build against a different effective SHA than the user thinks. Phase 1.5 catches both failure modes before any agent runs.

This pre-flight is structural (session-enforced), not advisory. The session runs it on every workflow invocation in a TheRock workspace.

## Branch Mapping

| TheRock branch | Mapped rocm-systems branch |
|----------------|---------------------------|
| `main` | `develop` |
| `release/therock-X.Y` | `release/therock-X.Y` |
| Anything else (user/feature branch, fork) | UNKNOWN — ask the user |

If `<therock_branch>` matches `release/therock-*`, the mapped branch is the SAME `release/therock-*` string in rocm-systems. Do NOT collapse to `develop`.

## Step 1.5.1: Detect TheRock Workspace

```
IF <workspace>/rocm-systems/.git exists OR <workspace>/.gitmodules contains "rocm-systems":
  Set <is_therock_workspace> = true
ELSE:
  Set <is_therock_workspace> = false
  Set <alignment_status> = NOT_APPLICABLE
  Skip to Parsing PM Output.
```

## Step 1.5.2: Run Alignment Check (TheRock workspace only)

Run these commands one at a time. Do NOT capture into shell variables — the command rules forbid `$VAR` expansion.

```
1. git -C <workspace> branch --show-current
   → <therock_branch>

2. git -C <workspace> rev-parse HEAD:rocm-systems
   → <pinned_sha>

3. git -C <workspace>/rocm-systems symbolic-ref --short HEAD
   → <rocm_systems_branch> (or non-zero exit if detached)

4. Determine <mapped_branch> from the Branch Mapping table above.

5. IF <mapped_branch> is UNKNOWN:
     Set <alignment_status> = FORK_BRANCH_AMBIGUOUS
     Skip to Step 1.5.3.

6. git -C <workspace>/rocm-systems fetch origin <mapped_branch>
   git -C <workspace>/rocm-systems rev-parse origin/<mapped_branch>
   → <tip_sha>

7. Determine status by comparing pinned to tip and current ref:
   - <rocm_systems_branch> == <mapped_branch>:
       → <alignment_status> = TRIGGER_DID_NOT_FIRE (in-flight state)
   - detached AND <pinned_sha> == <tip_sha>:
       git -C <workspace>/rocm-systems checkout <mapped_branch>
       → <alignment_status> = ATTACHED_AND_PROCEEDED
   - detached AND <pinned_sha> != <tip_sha>:
       → <alignment_status> = DIVERGENCE_HALTED
   - on a branch != <mapped_branch>:
       → <alignment_status> = DIVERGENCE_HALTED
       (the user is on an unexpected branch — surface it, do not auto-attach)
```

## Step 1.5.3: Handle the Result

| `<alignment_status>` | Session action |
|----------------------|----------------|
| `TRIGGER_DID_NOT_FIRE` | Proceed to Parsing PM Output. Record status in status.md. |
| `ATTACHED_AND_PROCEEDED` | Proceed to Parsing PM Output. Record status in status.md. |
| `DIVERGENCE_HALTED` | Build the divergence report (below) and present to user. Halt. Do NOT dispatch any agent. |
| `FORK_BRANCH_AMBIGUOUS` | Ask the user which mapped branch the fork derives from. Halt. Do NOT dispatch any agent. |

**Divergence report (when `DIVERGENCE_HALTED`):**

Gather:
```
git -C <workspace>/rocm-systems rev-list --count <pinned_sha>..origin/<mapped_branch>
git -C <workspace>/rocm-systems rev-list --count origin/<mapped_branch>..<pinned_sha>
git -C <workspace>/rocm-systems log --oneline -10 <pinned_sha>..origin/<mapped_branch>
```

Present:
```
ROCM-SYSTEMS DIVERGENCE DETECTED

  TheRock branch:        <therock_branch>
  Expected rocm-systems: <mapped_branch>
  Pinned SHA:            <pinned_sha>     ← what TheRock builds today
  Branch tip SHA:        <tip_sha>
  Commits ahead of pin:  <N>
  Commits behind pin:    <M>

  Recent commits on <mapped_branch> not yet pinned in TheRock:
    <hash> <subject>
    ...

  Choose:
    (a) Use rocm-systems <mapped_branch> tip (<tip_sha>) — likely has fixes not yet bumped into TheRock; agents may commit on this branch
    (b) Use TheRock's pinned SHA (<pinned_sha>) — detached HEAD; READ-ONLY, no commits possible
    (c) Cancel workflow
```

On user response (a): `git -C <workspace>/rocm-systems checkout <mapped_branch> && git -C <workspace>/rocm-systems reset --hard origin/<mapped_branch>`. Re-run from Step 1.5.2 to confirm. Update `<alignment_status>`.

On user response (b): leave detached HEAD. Set `<alignment_status>` = `READ_ONLY_PINNED`. Mark the workflow as commit-restricted: any subsequent agent that attempts to commit in `rocm-systems` MUST be halted by the session (see Step 1.5.5).

On user response (c): exit the workflow.

## Step 1.5.4: Record Alignment Status in status.md

Dispatch note-taker to add (or update) the `Submodule Alignment Status` field:

```
Agent(subagent_type: "note-taker", prompt: """
Update <thinking_dir>/status.md to set:
  Submodule Alignment Status: <alignment_status>
  Submodule TheRock Branch: <therock_branch>
  Submodule Mapped Branch: <mapped_branch_or_NA>
  Submodule Pinned SHA: <pinned_sha_or_NA>
  Submodule Tip SHA: <tip_sha_or_NA>

If these fields don't exist in status.md yet, add them in the Pipeline Metadata section.
""")
```

This is the source of truth that downstream agents read. Per the re-verify rule, it is a HINT — agents that mutate state MUST re-run the verification commands.

## Step 1.5.5: Read-Only Pinned Mode Enforcement

When the user chose option (b) and `<alignment_status>` = `READ_ONLY_PINNED`, the session enters commit-restricted mode for `rocm-systems`. Before dispatching git-agent for a commit, the session checks the files staged. If any path begins with `rocm-systems/`, the session halts with:

```
COMMIT BLOCKED — READ-ONLY PINNED SHA MODE

You chose to operate at TheRock's pinned rocm-systems SHA (<pinned_sha>),
which means rocm-systems is in detached HEAD and commits would be orphaned.

The following staged paths cannot be committed:
  <path1>
  <path2>

Choose:
  (a) Discard the staged rocm-systems changes
  (b) Restart the workflow and pick option (a) at the divergence prompt
      (rocm-systems <mapped_branch> tip)
```

This enforcement runs in the Mandatory Post-Commit Sequence, BEFORE git-agent dispatch.

## Alignment Check Procedure (for per-agent re-verification)

This is the canonical procedure that agents reference when they need to re-verify alignment. The DISPATCH-PROTOCOL.md tells agents to re-verify; this section tells them how.

### Trigger Condition

Run the alignment check when **either** of these is true:
- `rocm-systems` is in detached HEAD, OR
- `rocm-systems` is on a branch that is **not** the mapped branch for TheRock's current branch.

If `rocm-systems` is already on the mapped branch — even with local commits ahead of the pinned SHA — the trigger does **not** fire. That is the normal in-flight development state.

### Commands

Same 7-step procedure as Step 1.5.2 above.

### ALIGNMENT_CHECK Output Schema

Every agent that touches `rocm-systems` MUST emit an `ALIGNMENT_CHECK:` line as the first parseable status line in its output:

| Value | Meaning |
|-------|---------|
| `NOT_APPLICABLE` | Operation does not touch `rocm-systems/` |
| `TRIGGER_DID_NOT_FIRE` | `rocm-systems` is on the mapped branch (in-flight state). Proceeded. |
| `ATTACHED_AND_PROCEEDED` | Was detached at SHA equal to mapped branch tip. Ran attach-checkout, then proceeded. |
| `DIVERGENCE_HALTED` | Pinned SHA ≠ mapped branch tip. Output divergence report and stopped. **Forbidden:** any state-mutating line after this. |
| `FORK_BRANCH_AMBIGUOUS` | TheRock on fork/feature branch with no mapping. Stopped. **Forbidden:** any state-mutating line after this. |

### Hard Rules

- **Never commit in detached HEAD.** Orphaned commits are silent data loss.
- **Re-run the check after any TheRock branch switch.** `git checkout <therock-branch>` does NOT move `rocm-systems`.
- **Re-run the check after `git submodule update`.** That command lands `rocm-systems` in detached HEAD.
