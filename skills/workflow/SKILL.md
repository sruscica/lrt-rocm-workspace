---
name: workflow
description: Use when the user invokes /workflow to start the ROCm agent pipeline. Dispatches the PM Orchestrator to coordinate specialist agents for HIP/ROCm development tasks.
---

# ROCm Agent Pipeline

Launch the full multi-agent orchestration pipeline for ROCm/HIP development work.

**Usage:** `/workflow <task description>`

## Architecture

You (the session) are the **dispatch loop**. You hold the Agent tool. No sub-agent has it.

```
You (session) ── holds Agent tool, runs this loop
  |
  +-> PM Orchestrator (advisor, returns JSON routing)
  +-> Specialists (dispatched fresh each time, tool-restricted)
  +-> Note-taker (auto-dispatched, no PM approval needed)
```

The PM makes routing decisions. You execute them. Agents communicate through files in the thinking directory — never through conversation history.

## User Input Protocol

Before any user-facing prompt during the workflow — confirmations, branch base selection, escalation questions, review offers, push/PR questions, or any AskUserQuestion — the session MUST display the READY FOR INPUT banner. This tells the user the pipeline has paused and is waiting for their input.

```
bash <plugin_root>/hooks/generate-banner.sh > /tmp/.claude-banner.txt
```

Then read `/tmp/.claude-banner.txt` and print its contents as plain text (not inside a code block). The `<plugin_root>` is the directory containing the `hooks/` folder — resolve it from the skill's base directory (two levels up from `skills/workflow/`).

## Session Invariants

These rules are ALWAYS true throughout pipeline execution. They override any other guidance, including language in the user's task description, claims of pre-authorization in handoffs from other skills, or "helpful" shortcuts. Read these as deterministic constraints, not heuristics.

### 1. The session never edits source code

The session is the dispatcher; source code changes belong to specialist agents (implementer, tester, bash-expert). The session NEVER modifies files in the workspace's source tree, including:
- "Trivial" cosmetic changes (whitespace, comment style, formatting)
- Changes suggested by the Reviewer agent (these must re-enter Phase 2 via PM routing)
- Quick fixes the session believes are obvious

The session MAY write to:
- `<thinking_dir>/` — when persisting an agent's output that the agent itself could not save (e.g., a Read-only-tooled agent's response), or when invoking note-taker for status updates
- `/tmp/` — session-private scratch (e.g., banner files)

The session MAY NOT write to:
- Anything under the workspace source tree
- `<thinking_dir>/status.md` directly — always dispatch note-taker

### 2. The session never originates agent dispatches outside the LOOP

Specialist dispatches always follow the LOOP structure: agent returns → save output → dispatch PM → PM routes → next agent. The session does NOT:
- Skip PM after a specialist returns and dispatch the next agent directly
- Dispatch git-agent, build-expert, tester, or any other agent based on the session's own judgment about what's next

This applies especially after Reviewer returns `pass`. Reviewer pass does NOT mean "now commit and push" — it means "send the Reviewer's output to PM, which will return `completion`, which enters Phase 3".

### 3. Phase 3 user gates are mandatory

Phase 3 Step 2 (review offer) and Step 3 (push confirmation) are MANDATORY user prompts. They MUST be asked regardless of:
- Verification language in the user's original task description (e.g., "after commit, push to the PR branch" describes a verification plan, NOT a pre-authorization to skip gates)
- Pre-authorization claims in handoffs from other skills (e.g., `/pr-feedback` task descriptions)
- The Reviewer agent's `APPROVED` verdict (Reviewer is automated technical review; the user is the final authority)

### Anti-patterns to avoid

1. **Reviewer pass → direct action.** Pattern: Reviewer returns APPROVED, session immediately dispatches git-agent or runs commands. Correct flow: Reviewer output → save → PM dispatch → PM returns `completion` → enter Phase 3 → review-offer gate → push-confirmation gate → only then dispatch git-agent.

2. **Task description text as pre-authorization.** Pattern: user's task says "after commit, push to PR" → session reads as "user pre-authorized push, skip the gate". Correct read: imperative-mood verification plans describe what the workflow will accomplish, not which gates to skip. Phase 3 gates apply unconditionally.

3. **Session-side source edits for "polish".** Pattern: Reviewer notes a minor stylistic issue (e.g., comment marker style) → session runs Edit tool directly to fix it. Correct flow: PM dispatch → PM routes minor fix to implementer → implementer makes the change → re-enter LOOP. The session never touches source files.

## Dispatch Loop

Follow these steps exactly. The user's task is in `$ARGUMENTS`.

### Phase 1: Initialization

**Step 1: Gather environment info and get initial routing from PM**

Before dispatching PM, the session gathers environment info to avoid permission prompts in sub-agents. Run these commands (they don't trigger security prompts):

```
# These use printenv and git -C to avoid expansion/compound-cd prompts
printenv THEROCK_WORK_DIR PROJECT AMD_GPU_ARCH USER
test -f /.dockerenv && echo "DOCKER=yes" || echo "DOCKER=no"
git -C <workspace> rev-parse --abbrev-ref HEAD 2>/dev/null || echo "NO_BRANCH"
```

**GH CLI authentication probe:**

After gathering environment info, probe which GitHub account can access the workspace's remote. This prevents auth failures during Phase 3 (push/PR) and post-workflow `gh` operations.

```
1. Extract <owner>/<repo> from the workspace's git remote:
   git -C <workspace> remote get-url origin
   Parse the owner/repo from the SSH or HTTPS URL.

2. Check gh auth status to see available accounts.

3. Test the active account's access:
   gh api repos/<owner>/<repo> --jq '.full_name'

4. If that fails (e.g., GH_TOKEN points to wrong account):
   - Read ~/.config/gh/hosts.yml to find other authenticated accounts
   - For each account, test access using its token:
     GH_TOKEN=<token> gh api repos/<owner>/<repo> --jq '.full_name'
   - Store the first working token as <gh_token>

5. If no account has access, or gh is not installed:
   - Set <gh_token> = "" (empty)
   - Warn the user: "No GitHub account with access to <owner>/<repo> detected.
     Push and PR creation may fail. You can fix this with `gh auth login`."
   - Do NOT block the pipeline — GH auth is only needed in Phase 3.
```

Store `<gh_token>` (may be empty) and `<owner>/<repo>` for use in Phase 3 and post-workflow operations.

Then dispatch the PM Orchestrator with all info pre-provided:

```
Agent(subagent_type: "pm-orchestrator", prompt: """
ADVISOR MODE. You do NOT have the Agent tool.
DO NOT run any Bash commands. All environment info is provided below.

User task: <$ARGUMENTS>
Workspace: <workspace path>
Docker: <yes/no>
Environment: THEROCK_WORK_DIR=<value or unset>, PROJECT=<value or unset>, AMD_GPU_ARCH=<value or unset>
Current branch: <branch name or NO_BRANCH>
Username: <username>

Respond with ONLY a JSON block — no prose before or after. Use EXACTLY these 8 fields, no extras:

```json
{
  "type": "initial-routing",
  "workspace": "...",
  "branch_action": "use-existing or create-new",
  "task_summary": "...",
  "topic_slug": "...",
  "starting_agent": "hip-expert or troubleshooter or planner or implementer or bash-expert",
  "starting_context": "plain string, not an object",
  "classification": "design or bug or script or knowledge"
}
```
""")
```

After receiving PM output, apply the **Parsing PM Output — JSON Normalization** steps before proceeding.

**Step 2: Confirm with user**

Parse the PM's JSON. Present to the user:

> Working in: `<workspace>` (new branch will be created)
> Task: <task_summary>. Is that right?

If `branch_action` is `use-existing`, show the current branch name instead.

If the user corrects anything, re-dispatch PM with the corrections.

**Step 3: Create thinking directory**

First, determine where thinking/testing directories should go:

```
Set <artifact_base> = <workspace> (default)

IF inside Docker AND THEROCK_WORK_DIR is set:
  Set <artifact_base> = THEROCK_WORK_DIR
  (Thinking/testing artifacts always go in the work directory inside containers,
   even when code changes target a different workspace.)
```

Then create the directories yourself with a single mkdir command (NO brace expansion), and dispatch Note-taker for status.md only:

```bash
# Session runs this directly — NOT dispatched to an agent
# IMPORTANT: Inline the full path. Do NOT use $VAR — it triggers expansion prompts.
mkdir -p <artifact_base>/thinking/YYYY-MM-DD-<topic_slug>/analysis <artifact_base>/thinking/YYYY-MM-DD-<topic_slug>/plans <artifact_base>/thinking/YYYY-MM-DD-<topic_slug>/tests <artifact_base>/thinking/YYYY-MM-DD-<topic_slug>/reviews <artifact_base>/thinking/YYYY-MM-DD-<topic_slug>/investigations <artifact_base>/thinking/YYYY-MM-DD-<topic_slug>/builds <artifact_base>/thinking/YYYY-MM-DD-<topic_slug>/commits <artifact_base>/thinking/YYYY-MM-DD-<topic_slug>/scripts <artifact_base>/thinking/YYYY-MM-DD-<topic_slug>/pm-summaries <artifact_base>/thinking/YYYY-MM-DD-<topic_slug>/requests
mkdir -p <artifact_base>/testing/YYYY-MM-DD-<topic_slug>
```

Use `<artifact_base>` (not `<workspace>`) for all thinking_dir and testing_dir references throughout the pipeline.

Then dispatch Note-taker to write status.md only:

```
Agent(subagent_type: "note-taker", prompt: """
Write the initial status.md to <thinking_dir>/status.md using the standard template.
Topic: <topic_slug>
Task: <task_summary>
Starting agent: <starting_agent>
""")
```

**Step 4: Handle branch**

Branch creation is **deferred** for `bug` and `knowledge` tasks — these may conclude without code changes, so creating a branch upfront is wasteful. For `design` and `script` tasks, branches are created immediately since code changes are expected.

The Git Agent owns branch naming. It examines existing branches in the repo to determine the naming convention and creates a descriptive name for the task. The session provides the task summary — not a branch name.

**4a. Determine branch base** (for `create-new` only):

Determine the default base branch from the workspace path:

| Workspace path contains | Default base branch |
|-------------------------|---------------------|
| `compute-utils`         | `amd/dev/lrt`       |
| `rocm-systems`          | `develop`           |
| (other)                 | `main`              |

Present to the user:
> Base branch: `<default>` (default for `<repo>`). Use this, or specify a different base?

Store the confirmed value as `<branch_base>`. This is used for both branch creation
and PR targeting (Phase 3 Step 3).

**4b. Create or defer branch:**

- If `branch_action` is `create-new` AND `classification` is `design` or `script`:
  - Dispatch the Git Agent now:
    ```
    Agent(subagent_type: "git-agent", prompt: "Create a new branch for this task and switch to it. Examine existing branches to determine the repo's naming convention, then create a branch name that matches the convention and describes the task. Base the branch on origin/<branch_base>. Working directory: <workspace>. Task: <task_summary>. Username: <username>")
    ```
  - Save the branch name from the Git Agent's output
  - Set `branch_created = true`

- If `branch_action` is `create-new` AND `classification` is `bug` or `knowledge`:
  - Do NOT create the branch yet. Save `task_summary`, `username`, and `<branch_base>` for the deferred dispatch.
  - Set `branch_created = false`

- If `branch_action` is `use-existing`:
  - No action needed.
  - Set `branch_created = true` (or N/A)
  - Determine `<branch_base>` by checking the upstream tracking branch or using the lookup table above. Store for PR targeting.

**Step 5: Record pipeline start commit**

Record the repo state before any pipeline code changes:
```
pipeline_start_commit = git -C <workspace> rev-parse HEAD
```
Store this value for use in Phase 3 (review scope selection).

### Phase 1.5: rocm-systems Alignment Pre-Flight

**Why this phase exists.** TheRock pins `rocm-systems` via gitlink (a specific SHA). After `git submodule update`, `rocm-systems` lands in detached HEAD. Any commit an agent makes in detached HEAD is silently abandoned the next time the submodule moves. Switching TheRock branches does NOT move `rocm-systems`, so the workspace can build against a different effective SHA than the user thinks. Phase 1.5 catches both failure modes before any agent runs.

This pre-flight is structural (session-enforced), not advisory. The PM does NOT decide whether to run it. The session runs it on every workflow invocation in a TheRock workspace.

**Step 1.5.1: Detect TheRock workspace**

```
IF <workspace>/rocm-systems/.git exists OR <workspace>/.gitmodules contains "rocm-systems":
  Set <is_therock_workspace> = true
ELSE:
  Set <is_therock_workspace> = false
  Set <alignment_status> = NOT_APPLICABLE
  Skip to Parsing PM Output.
```

**Step 1.5.2: Run alignment check (TheRock workspace only)**

Run these commands one at a time. Do NOT capture into shell variables — the command rules forbid `$VAR` expansion.

```
1. git -C <workspace> branch --show-current
   → <therock_branch>

2. git -C <workspace> rev-parse HEAD:rocm-systems
   → <pinned_sha>

3. git -C <workspace>/rocm-systems symbolic-ref --short HEAD
   → <rocm_systems_branch> (or non-zero exit if detached)

4. Determine <mapped_branch> from the table:
   | TheRock branch         | Mapped rocm-systems branch |
   |------------------------|---------------------------|
   | main                   | develop                    |
   | release/therock-X.Y    | release/therock-X.Y        |
   | (anything else)        | UNKNOWN — ASK USER         |

   If <therock_branch> matches "release/therock-*", the mapped branch is the
   SAME release/therock-* string in rocm-systems. Do NOT collapse to develop.

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

**Step 1.5.3: Handle the result**

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

On user response (a): `git -C <workspace>/rocm-systems checkout <mapped_branch> && git -C <workspace>/rocm-systems reset --hard origin/<mapped_branch>`. Re-run Phase 1.5 from Step 1.5.2 to confirm. Update `<alignment_status>`.

On user response (b): leave detached HEAD. Set `<alignment_status>` = `READ_ONLY_PINNED`. Mark the workflow as commit-restricted: any subsequent agent that attempts to commit in `rocm-systems` MUST be halted by the session (see Step 1.5.4).

On user response (c): exit the workflow.

**Step 1.5.4: Record alignment status in status.md**

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

This is the source of truth that downstream agents read. Per the re-verify rule (DISPATCH-PROTOCOL.md), it is a HINT — agents that mutate state MUST re-run the verification commands.

**Step 1.5.5: Read-only pinned mode enforcement (when `<alignment_status>` = `READ_ONLY_PINNED`)**

When the user chose option (b), the session enters commit-restricted mode for `rocm-systems`. Before dispatching git-agent for a commit, the session checks the files staged. If any path begins with `rocm-systems/`, the session halts with:

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

### Parsing PM Output — JSON Normalization

The PM often returns non-compliant JSON. The session MUST normalize PM output before acting on it. Follow these steps every time you receive PM output:

**Step 1: Extract JSON.** The PM may include prose before/after the JSON block. Extract only the content inside the ```json fences. Ignore all text outside the fences.

**Step 2: Identify the response type.** Look for a `"type"` field. If missing, infer the type:
- If the response has `starting_agent` or `classification` → treat as `initial-routing`
- If the response has `next_agent` → treat as `next-step`
- If the response has `target` and `then_resume` → treat as `fulfill-request`
- If the response has `message` and `files` → treat as `commit`
- If the response has `summary` → treat as `completion`
- If the response has `question` and `options` → treat as `escalation`

**Step 3: Extract required fields for the identified type.** Ignore ALL extra fields. Only use:

| Type | Required fields |
|------|----------------|
| `initial-routing` | `workspace`, `branch_action`, `task_summary`, `topic_slug`, `starting_agent`, `starting_context`, `classification` |
| `next-step` | `next_agent`, `context_notes`, `pass_files`, `iteration_change` |
| `fulfill-request` | `target`, `context_notes`, `pass_files`, `then_resume`, `resume_context` |
| `commit` | `message`, `files` |
| `completion` | `summary`, `offer_review` |
| `escalation` | `question`, `options` |
| `bisect` | `known_good`, `known_bad`, `test_description`, `component`, `then_resume`, `resume_context` |

**Step 4: Normalize values.**

Agent names — normalize to lowercase-hyphenated:

| PM might return | Normalize to |
|----------------|-------------|
| `HIP Expert`, `Hip Expert`, `hip_expert`, `HIP_Expert` | `hip-expert` |
| `Troubleshooter`, `troubleshooter` | `troubleshooter` |
| `Planner` | `planner` |
| `Implementer` | `implementer` |
| `Tester` | `tester` |
| `Reviewer` | `reviewer` |
| `Bash Expert`, `bash_expert`, `Bash_Expert` | `bash-expert` |
| `Build Expert`, `build_expert` | `build-expert` |
| `Git Agent`, `git_agent`, `Git_Agent` | `git-agent` |
| `Note-taker`, `note_taker` | `note-taker` |

Classification — normalize to one of `design`, `bug`, `script`, `knowledge`:
- `pure_knowledge`, `pure_knowledge_question`, `knowledge_question` → `knowledge`
- `design-then-implement`, `implementation_request`, `implementation` → `design`
- `debugging`, `debug`, `troubleshooting` → `bug`
- `automation`, `scripting` → `script`

`starting_context` / `context_notes` — if the PM returned a nested object instead of a string, extract the `user_request` or `instructions` field from it. If neither exists, JSON.stringify the object.

`branch_action` — normalize to `use-existing` or `create-new`:
- `none`, `N/A`, `""`, `null` → `use-existing`

**Step 5: Apply classification override.** If the task involves creating/modifying/deleting files AND the PM classified it as `knowledge`, override to `design`. The PM frequently misclassifies code-change tasks as knowledge.

**Step 5b: Apply tester classification override.** The PM sometimes classifies test verification tasks as `bug` (since they involve test failures/results) while correctly choosing `tester` as the starting agent. If `starting_agent` is `tester` AND `classification` is NOT `script`: override `classification` to `script`. The PM's agent selection is more reliable than its classification for testing tasks.

**Step 6: Apply starting agent override.** The PM sometimes skips analysis by routing directly to `planner` or `implementer`. The session enforces the full pipeline:
- If `classification` is `design` or `bug` AND `starting_agent` is NOT `hip-expert` and NOT `troubleshooter`: override `starting_agent` to `hip-expert`.
- If `classification` is `script` AND `starting_agent` is NOT `bash-expert` and NOT `tester` and NOT `build-expert`: override `starting_agent` to `bash-expert`. (`build-expert` is allowed only for pure build tasks — rebuilds, configure, clean — not for scripting or automation work.)
- `knowledge` tasks: no override (always `hip-expert` by convention, but no enforcement needed).

**Step 7: Override workspace.** Always use the workspace path the session gathered in Step 1. Ignore the PM's `workspace` field — the PM sometimes appends `/therock` or modifies the path. The session's own value is authoritative.

### Phase 2: Main Dispatch Loop

**Entry:** Phase 2 is entered fresh from Phase 1, OR re-entered from Phase 2.5 Step 7a after a regression is confirmed during wider-suite triage. The two entry paths share the same loop body but have different setup:

- **Fresh entry (from Phase 1):** Set `iteration = "1.0"`, `major = 1`, `minor = 0`, `previous_agent = ""`. Dispatch the starting agent (LOOP step 1) and proceed normally.
- **Regression re-entry (from Phase 2.5 Step 7a):** Status.md already reflects prior-iteration state — `Test Status: TESTED (regression)`, `Build Status: NOT BUILT`. The troubleshooter has already run in Phase 2.5 and its output sits in `<thinking_dir>/investigations/`. Do NOT reset iteration counters or `previous_agent` — they carry forward.

**Regression re-entry invariant (session enforcement):**
On entry to Phase 2, read `Test Status` from status.md.
- If `TESTED (regression)`: this is a Phase 2.5 Step 7a re-entry. The session MUST:
  1. Read the most recent troubleshooter output file from `<thinking_dir>/investigations/` (sorted by mtime, newest first).
  2. Skip LOOP step 1 (do NOT re-dispatch the agent — troubleshooter already ran in Phase 2.5).
  3. Enter the LOOP at step 3, sending the troubleshooter output to PM as the agent output.
  4. PM (now seeing `Test Status: TESTED (regression)` in status.md plus the troubleshooter findings as agent_output) routes to planner or implementer.

  Without this invariant, PM has no signal that the new iteration is regression-driven and may misroute.
- Otherwise (any other Test Status, including `NOT TESTED`, `TESTED (targeted-pass)`, etc.): fresh entry path. Dispatch the starting agent normally and enter the loop at step 1.

**No-bypass invariant (session enforcement):**
The LOOP structure is non-negotiable. After every specialist agent returns — including Reviewer with a `pass` verdict — the session MUST execute LOOP step 3 (send agent output to PM for routing). The session does NOT:
- Dispatch git-agent for commit/push directly after Reviewer pass
- Dispatch build-expert directly without PM routing
- Skip PM and dispatch any next agent based on session-level judgment about what's appropriate

PM is the only path to Phase 3. Phase 3 is the only path to commit/push. There is no shortcut. See "Session Invariants" at the top of this file.

**Dispatch the starting agent and enter the loop:**

```
LOOP:
  1. Dispatch the current agent (see "How to Dispatch a Specialist" below)
  2. Handle output saving (see "Note-taker Rules" below)
  3. Send agent output to PM for routing (see "Ask PM What's Next" below)
  4. Parse PM response and act on it:

     **Streak reset (session enforcement):** If PM's `type` is anything OTHER than `fulfill-request`, set `fulfill_request_streak = 0` before processing. Initialize the streak to 0 on first entry to the loop.

     IF type = "next-step":
       - Update iteration (session enforcement):
         IF PM says iteration_change = "major": major++, minor = 0
         ELSE IF next_agent != previous_agent: minor++
         (Same-agent re-dispatches do not increment)
         Update iteration string = "major.minor"
         Set previous_agent = next_agent
       - Apply Planner Gate (session enforcement):
         IF next_agent = "implementer" AND no planner artifact exists in <thinking_dir>/plans/:
           Override next_agent to "planner". Log: "Session override: planner required before implementer."
         IF next_agent = "commit":
           This is invalid as a next-step target. Treat as if PM returned type="commit" instead.
       - IF next_agent = "reviewer": run the Reviewer Gating Check (see below)
       - Set current agent = next_agent
       - Build context from PM's context_notes and pass_files
       - CONTINUE LOOP

     IF type = "fulfill-request":
       - **Loop cap (session enforcement):** Maintain a counter
         `fulfill_request_streak` that increments on each consecutive
         `fulfill-request` and resets to 0 whenever PM returns any other
         type. If `fulfill_request_streak` would exceed 3, do NOT dispatch
         the target. Instead:
           - Reset the streak to 0
           - Display the READY FOR INPUT banner
           - Ask the user: "PM has requested cross-agent fulfillment 4 times in a row
             (chain so far: <list of (originator → target) pairs>). This usually
             means the agents cannot agree on what they need. Continue, change
             direction, or abort?"
           - On Continue: increment the streak again and proceed; the cap will
             re-trigger after 3 more requests.
           - On Change direction: take the user's input as a new task summary,
             dispatch PM with type="next-step" context describing the user's
             redirect.
           - On Abort: BREAK LOOP and skip to Phase 3 with a status note that
             the pipeline was aborted mid-fulfill-request chain.
         The cap protects against unbounded loops where, e.g., the Reviewer
         requests an expert who requests the Tester who reports a failure that
         the Reviewer interprets as needing another expert.
       - Increment `fulfill_request_streak`
       - Dispatch the target agent with PM's context_notes
       - Handle output saving for target agent
       - If then_resume is set: re-dispatch the original agent with
         the target's results file path and PM's resume_context
       - Send the resumed agent's output to PM
       - CONTINUE LOOP

     IF type = "commit":
       - Apply Planner Gate (session enforcement):
         IF classification is "design", "bug", or "script" (code-change tasks):
           IF no planner artifact exists in <thinking_dir>/plans/:
             Do NOT commit. Override: dispatch planner with expert analysis as context.
             Log: "Session override: planner required before commit."
             CONTINUE LOOP
       - If `branch_created` is false (deferred from Step 4):
         - If `<branch_base>` was not yet confirmed (bug/knowledge tasks where
           Step 4a was skipped because branch was deferred), run Step 4a now:
           determine default from lookup table, ask user to confirm or override.
         - Dispatch Git Agent to create the branch first:
           "Create a new branch for this task and switch to it. Examine existing branches to determine the repo's naming convention, then create a branch name that matches the convention and describes the task. Base the branch on origin/<branch_base>. Working directory: <workspace>. Task: <task_summary>. Username: <username>"
         - Save the branch name from the Git Agent's output
         - Set `branch_created = true`
       - Augment commit message with Claude signature (session enforcement):
         - Take PM's `message` field as `<commit_message>`.
         - Trim trailing whitespace from `<commit_message>`.
         - If `<commit_message>` already ends with a `🤖 Claude Code 🤖` line
           (defensive — PM was not instructed to include it, but enforce here),
           leave it as-is. Otherwise, append `\n\n🤖 Claude Code 🤖`.
         - Pass `<commit_message>` (NOT the raw PM message) to the Git Agent.
       - Dispatch Git Agent to commit specified files using `<commit_message>`
       - Handle output saving for Git Agent (must include the commit hash)
       - Dispatch Note-taker to update status.md Commits table with the new hash
       - Run the Mandatory Post-Commit Sequence (see below)
       - Send result to PM (reviewer output if tester passed, tester output if tester failed, build-expert analysis if deferred)
       - CONTINUE LOOP

     **Commit hash maintenance:** Whenever a commit hash changes (amend,
     recommit after soft-reset, cherry-pick restore), the session MUST
     dispatch Note-taker to update the Commits table in status.md with
     the new hash. Stale hashes make status.md unreliable for debugging.

     IF type = "completion":
       - Go to Phase 3 (Completion Flow)
       - BREAK LOOP

     IF type = "escalation":
       - Hardware-bound handoff enforcement (session guarantee — do BEFORE
         presenting options to the user):
         IF the most recent specialist output contains a section header
         "## Hardware Constraint":
           IF PM's options list does NOT already include an option whose text
           contains the word "handoff" (case-insensitive):
             Append this exact option to PM's options list:
               "Produce a runnable handoff plan I can execute on the remote hardware"
           Set hardware_handoff_offered = true
         ELSE:
           Set hardware_handoff_offered = false
       - Present PM's question and options to the user
       - IF hardware_handoff_offered AND user picked the handoff option:
         - Do NOT route the answer back to PM. Dispatch bash-expert directly
           using the Hardware Handoff Dispatch template (see "Hardware Handoff
           Dispatch" subsection below).
         - After bash-expert finishes, save its output via note-taker to
           <thinking_dir>/scripts/<iteration>-bash-expert-handoff.md
         - Tell the user where the handoff plan was written and ask whether
           to continue the pipeline (e.g. with another agent) or end here.
         - If they end → go to Phase 3 (Completion Flow), BREAK LOOP
         - Otherwise treat their direction as a new task input and re-dispatch
           PM for fresh routing.
       - ELSE:
         - Send user's answer back to PM
         - PM returns new routing
         - CONTINUE LOOP

     IF type = "bisect":
       - Run the Bisect Inner Loop (see below)
       - Send results to PM
       - CONTINUE LOOP
```

### How to Dispatch a Specialist

Every specialist dispatch uses this pattern:

```
Agent(subagent_type: "<agent-name>", prompt: """
You are the <agent-name> in the ROCm Agent Pipeline.
You do NOT have the Agent tool. If you need another agent, state the need
clearly in your output — which agent, what task, what files are relevant.

COMMAND RULES (mandatory — violations prompt the user for approval):
- NEVER use `cd /path && git ...` → use `git -C /path ...` instead
- NEVER use `echo "$VAR"` or `printf ... "$VAR"` → use `printenv VAR` instead
- NEVER use brace expansion `{a,b,c}` → spell out each argument
- NEVER use `$VAR` or `$?` in any command → use `printenv VAR` or `cmd || echo FAILED`
- NEVER use `${PIPESTATUS[0]}` or any `${...}` expansion → Bash tool reports exit codes automatically
- NEVER use `| tee file; echo "${PIPESTATUS[0]}"` → just `| tee file` or `> file 2>&1`
- NEVER use for/while loops with `$VAR` → spell out each command individually
- NEVER use Catch2 `~[tag]` filter → list specific test names instead (triggers zsh syntax detection)
- NEVER use `[[ -f /.dockerenv ]] && ...` with variable expansion in the same command
- NEVER write plans, analysis, reports, or intermediate artifacts into the workspace — only code deliverables go there. All other output goes under `<thinking_dir>`.

Workspace: <workspace>
Thinking directory: <thinking_dir>
Iteration: <iteration>
User request: <one-line task summary>

<if <is_therock_workspace> is true, append the alignment-context block:>

ROCM-SYSTEMS ALIGNMENT CONTEXT (from session pre-flight):
  TheRock branch:        <therock_branch>
  Mapped rocm-systems:   <mapped_branch>
  Pinned SHA:            <pinned_sha>
  Mapped tip SHA:        <tip_sha>
  Pre-flight verdict:    <alignment_status>

This context is a HINT. State can drift between pre-flight and your dispatch.
- If you mutate state (commit, branch, build, write scripts that touch the submodule):
  re-run the verification commands yourself before acting. Emit ALIGNMENT_CHECK:
  in your output per DISPATCH-PROTOCOL.md.
- If you only read (investigate, design, test): record the alignment verdict in
  your output but you do not need to re-verify. Note any inconsistency you observe
  between the verdict and what you see.

<task-specific context from PM's context_notes>

Read these files for context:
<list of pass_files from PM>

<if this is a re-dispatch after a cross-agent request:>
Results from <target_agent> are at: <results_file_path>
Continue your work incorporating those results.
""")
```

### Alignment Output Validator

After every dispatch of an agent that touches `rocm-systems` (build-expert, git-agent, bash-expert in mutation mode, troubleshooter, implementer, tester), the session validates the output BEFORE handing it to the PM.

**Agents requiring validation:**

| Agent | Required when |
|-------|---------------|
| build-expert | always (it builds against the submodule) |
| git-agent | always (it commits/branches; for submodule-untouching ops it emits `NOT_APPLICABLE`) |
| bash-expert | when its task involves a script that touches `rocm-systems/` |
| troubleshooter | when investigating code or tests in `rocm-systems/` |
| implementer | when its plan steps touch files under `rocm-systems/` |
| tester | when the test result depends on the rocm-systems SHA (most HIP/CLR tests) |

**Validation rules:**

1. The agent's output MUST contain a line matching `^ALIGNMENT_CHECK: (NOT_APPLICABLE|TRIGGER_DID_NOT_FIRE|ATTACHED_AND_PROCEEDED|DIVERGENCE_HALTED|FORK_BRANCH_AMBIGUOUS)$` before any state-mutating `Operation:` line, `BUILD_DECISION:` line, or commit hash.
2. If the verdict is `DIVERGENCE_HALTED` or `FORK_BRANCH_AMBIGUOUS`, the output MUST NOT contain any state-mutating line:
   - `Operation: commit`, `Operation: branch-create`, `Operation: checkout` (other than the alignment-attach), `Operation: cherry-pick`, `Operation: reset`
   - `BUILD_DECISION: BUILD_NOW` or `BUILD_DECISION: BUILD_REQUIRED` followed by build execution
   - Any line of the form `Commit hash: <sha>` or `Branch created: <name>`

**Re-dispatch loop on validation miss:**

```
retry_count = 0
loop:
  dispatch agent
  validate output
  IF valid: break, hand output to PM
  IF retry_count < 2:
    retry_count += 1
    re-dispatch with this prepended note:
      "Your previous output was malformed: <specific violation>.
       Re-emit your output starting with the required ALIGNMENT_CHECK: line
       and following the schema in DISPATCH-PROTOCOL.md. Do not include
       state-mutating Operation: lines if your verdict is a halt verdict."
  ELSE:
    halt the workflow. Surface to user:
      "Agent <name> produced malformed alignment output 3 times in a row.
       This indicates a definitional bug in the agent or the prompt.
       Last output: <truncated output>
       Stopping the workflow. The issue requires manual investigation."
```

The retry cap is 2 (so the agent is invoked at most 3 times for the same step). Do NOT let validation misses cascade silently — they hide the failure mode this whole architecture exists to prevent.

### Ask PM What's Next

After every specialist finishes:

```
Agent(subagent_type: "pm-orchestrator", prompt: """
ADVISOR MODE. Return ONLY a JSON block, no prose.

Iteration: <iteration>
Agent that just finished: <agent_name>
Their output summary:
---
<agent output, or a summary if very long>
---

Current status.md:
---
<read status.md from thinking dir>
---

What should happen next? Respond with ONLY a JSON block using one of these EXACT schemas:

next-step: {"type":"next-step", "next_agent":"<name>", "context_notes":"<string>", "pass_files":["<files>"], "iteration_change":"none|minor|major"}

fulfill-request: {"type":"fulfill-request", "target":"<agent>", "context_notes":"<string>", "pass_files":["<files>"], "then_resume":"<agent or null>", "resume_context":"<string>"}

commit: {"type":"commit", "message":"<commit message>", "files":["<files to stage>"]}

completion: {"type":"completion", "summary":"<what was accomplished>", "offer_review":true}

escalation: {"type":"escalation", "question":"<what to ask user>", "options":["<option1>","<option2>"]}

bisect: {"type":"bisect", "known_good":"<hash>", "known_bad":"<hash>", "test_description":"<what to test>", "component":"<what to build>", "then_resume":"troubleshooter", "resume_context":"<what to tell troubleshooter>"}
""")
```

After receiving PM output, apply the **Parsing PM Output — JSON Normalization** steps before acting on the routing.

### Note-taker Rules

After a specialist finishes, check if they need Note-taker:

**Agents WITH Write (handle their own output):**
- `implementer`, `tester`, `bash-expert`
- These write their own output files. Only dispatch Note-taker for status.md:
  ```
  Agent(subagent_type: "note-taker", prompt: "Update status.md at <path>: <status update details>")
  ```

**Agents WITHOUT Write (need Note-taker for output):**
- `hip-expert`, `planner`, `reviewer`, `troubleshooter`, `build-expert`, `git-agent`
- Dispatch Note-taker to save their full output:
  ```
  Agent(subagent_type: "note-taker", prompt: """
  Write the following content to <thinking_dir>/<subdir>/<iteration>-<agent>.md:
  ---
  agent: <agent-name>
  topic: <topic-slug>
  iteration: <iteration>
  timestamp: <current ISO 8601>
  ---

  <full agent output>

  Also update status.md at <path>: <status update details>
  """)
  ```

**Note-taker is ALWAYS auto-dispatched. Never route Note-taker requests through PM.**

### Reviewer Gating Check

Before dispatching the reviewer (whether PM requested it or any other path), the session MUST verify that build and test artifacts exist. Do NOT dispatch the reviewer without them.

```
REVIEWER-GATE (for design, bug, script tasks):
  1. Check <thinking_dir>/builds/ for a build results file
     - EXCEPTION: If Build Status in status.md is "BUILT" AND all committed
       files are non-compiled (shell scripts, .md, .txt, .yaml, .json, etc.),
       the builds/ file check is waived. The post-commit sequence already
       set Build Status to BUILT for non-compiled files — no build artifact
       file is expected.
     - If MISSING (and no exception applies): dispatch build-expert first
       (use file-path → component mapping)
     - Handle output saving, then re-check

  2. Check <thinking_dir>/tests/ for a test results file
     - If MISSING: dispatch tester first
     - Handle output saving, then re-check

  3. Only after BOTH checks pass: dispatch the reviewer
     - Include build results file (if present) and test results file in pass_files
```

For `knowledge` tasks: skip this check (no build/test expected).

### Mandatory Post-Commit Sequence

After every `commit` action (for `design`, `bug`, or `script` tasks), the session MUST classify the committed files and follow the appropriate path.

**Pre-step (read-only-pinned guard):** If `<alignment_status>` is `READ_ONLY_PINNED` and any staged path begins with `rocm-systems/`, halt with the COMMIT BLOCKED message defined in Phase 1.5 Step 1.5.5. Do NOT dispatch git-agent.

```
POST-COMMIT:
  1. Classify committed files:

     Non-compiled: shell scripts (.sh), Dockerfiles, .md, .txt, .yaml,
       .json, .toml, config files, documentation
     Compiled: .cpp, .hip, .c, .h, .hpp, CMakeLists.txt, .cmake,
       Python with C extensions

     IF ALL committed files are non-compiled:
       → Follow the NON-COMPILED PATH below
     IF ANY committed file is compiled:
       → Follow the COMPILED PATH below

  NON-COMPILED PATH:
     a. Update status.md: `Build Status: BUILT` (no compilation needed)
     b. Dispatch tester directly (no build-expert needed):
        "Verify the script/config changes. Workspace: <workspace>."
        - Handle output saving (tester writes own output)
     c. If tester verdict is `pass`:
        Run the Reviewer Gating Check and dispatch reviewer directly
        (skip PM — this transition is deterministic)
     d. If tester verdict is `fail` or `cannot-test`:
        Return tester output to the main loop (sent to PM for routing)

  COMPILED PATH:
     a. Determine the build component from the committed files:
        - Files under rocm-systems/projects/hip-tests/ → "hip-tests+build"
        - Files under rocm-systems/projects/clr/ or core/clr/ → "hip-clr+build"
        - Files under rocm-systems/projects/ocl-clr/ → "ocl-clr+build"
        - Standalone .hip/.cpp files (not in TheRock tree) → compile with hipcc directly

     b. Dispatch build-expert (diff analysis + conditional build):
        "Post-commit dispatch. Analyze the committed diff first. If ALL changes are
         non-functional (comments, docs, whitespace, log strings, .md/.txt files),
         report BUILD_DECISION: DEFERRED and skip building. If ANY changes are functional,
         build incrementally and report BUILD_DECISION: BUILT.
         Component: <component>. Target: <target>. Workspace: <workspace>."
        - Apply the dispatch template, which includes the alignment-context block
          when <is_therock_workspace> is true.
        - Run the Alignment Output Validator on build-expert's output. If validation
          fails, re-dispatch up to 2× per the validator's retry loop.
        - Handle output saving (Note-taker for build-expert)

     c. Parse build-expert output for BUILD_DECISION and update Build Status:

        IF BUILD_DECISION is BUILT AND build PASSED:
          - Update status.md: `Build Status: BUILT`
          - Dispatch tester:
            "Verify the changes compile and run correctly. Component: <component>.
             Build output: <build results file path>. Workspace: <workspace>."
            - Handle output saving (tester writes own output)
            - If tester verdict is `pass`: run the Reviewer Gating Check and dispatch reviewer directly (skip PM — this transition is deterministic)
            - If tester verdict is `fail` or `cannot-test`: return tester output to the main loop (sent to PM for routing)

        IF BUILD_DECISION is BUILT AND build FAILED:
          - Update status.md: `Build Status: BUILD FAILED`
          - Do NOT proceed to tester
          - Send build output to PM. PM routes back to implementer.

        IF BUILD_DECISION is DEFERRED:
          - Update status.md: `Build Status: BUILD DEFERRED`
          - Do NOT dispatch tester
          - Return build-expert analysis to the main loop (sent to PM for routing)
          - PM reads Build Status from status.md and routes to reviewer
```

When dispatching the reviewer and Build Status is `BUILD DEFERRED`, include in the reviewer's context:
"Build was deferred — changes are non-functional only (comments/docs/formatting). Focus on spec compliance and code quality. Build verification is pending after review."

### Build / Test Status Reset (single trigger, two fields)

When the PM routes back to implementer, planner, or hip-expert after a reviewer rejection (`partial`, `fail-spec`, or `fail`), the session MUST update **both** fields in status.md in the same write:

- `Build Status: NOT BUILT`
- `Test Status: NOT TESTED`

This is one trigger, not two. The fields move together because stale build state masks a non-functional change and stale test state masks a regression introduced by the new code. The next commit's post-commit sequence sets Build Status fresh; the next tester dispatch sets Test Status fresh.

If you ever update one without the other after a reviewer rejection, you have introduced drift. Always write both.

### Test Status Update After Tester Dispatch

After every tester dispatch completes, the session MUST update status.md `Test Status` based on the tester's verdict:

- Tester verdict `pass` → `Test Status: TESTED (targeted-pass)`
- Tester verdict `fail` → `Test Status: TESTED (targeted-fail)`
- Tester verdict `cannot-test` → `Test Status: CANNOT TEST`

The wider-suite outcome states (`TESTED (wider-pass)`, `TESTED (regression)`, `TESTED (pre-existing-flagged)`, `TESTED (cannot-classify)`) are set by Phase 2.5 (Wider Suite Execution). The targeted-pass tester run produces a Wider Suite Proposal that Phase 2.5 then executes and triages.

### Bisect Inner Loop

When PM returns `type: "bisect"`:

```
1. Dispatch git-agent: "Start bisect: git bisect start, git bisect good <known_good>, git bisect bad <known_bad>. Report the first test commit."

2. LOOP until culprit found:
   a. Dispatch build-expert: "Incremental rebuild of <component>. Workspace: <workspace>"
   b. If build failed: dispatch git-agent "git bisect skip. Report next commit." → CONTINUE
   c. Dispatch tester: "Run test: <test_description>. Report pass or fail."
   d. If pass: dispatch git-agent "git bisect good. Report next commit or culprit."
      If fail: dispatch git-agent "git bisect bad. Report next commit or culprit."
   e. If culprit found: BREAK

3. Dispatch git-agent: "git bisect reset"

4. Re-dispatch the agent from then_resume with:
   "Bisect complete. Culprit commit: <hash>. Git output: <details>. Continue your investigation."
```

No PM validation per bisect step — the inner loop is mechanical.

### Hardware Handoff Dispatch

Triggered from the escalation handler when the user picks the
"Produce a runnable handoff plan" option after a `## Hardware Constraint`
investigation. Goal: produce a self-contained plan the user can execute on
the remote hardware (or hand to someone who has access) without re-deriving
test names, env vars, binaries, or expected observations.

```
Agent(subagent_type: "bash-expert", prompt: """
You are the Bash Expert in the ROCm Agent Pipeline.
You do NOT have the Agent tool.

COMMAND RULES (mandatory):
- NEVER use `cd /path && git ...` → use `git -C /path ...`
- NEVER use `echo "$VAR"` or `printf ... "$VAR"` → use `printenv VAR`
- NEVER use brace expansion `{a,b,c}` → spell out each argument
- NEVER use `$VAR` or `$?` in any command → use `printenv VAR` or `cmd || echo FAILED`

Workspace: <workspace>
Thinking directory: <thinking_dir>
Iteration: <iteration>

Task: Produce a HARDWARE HANDOFF PLAN for executing a hardware-blocked
investigation on a remote system. The investigation could not conclude
locally because of a hardware/configuration constraint.

Read the troubleshooter investigation first:
  <thinking_dir>/investigations/<latest>-troubleshooter*.md
Pay special attention to its `## Hardware Constraint` section — that's
your primary input.

Also read (for canonical test runner usage):
  <plugin_root>/agents/tester.md  (§compute-utils Test Runners)

Produce a single markdown document with these sections, in this order:

1. **Target Environment** — exactly what hardware/config the operator must
   provide (GPU arch, driver mode, XNACK setting, GPU count, OS where it
   matters). Pull from the troubleshooter's "What's missing locally".
2. **Setup Checks** — copy-pasteable commands the operator runs FIRST to
   confirm the target system actually meets the requirements
   (`rocminfo | grep -E 'gfx|xnack'`, `nvidia-smi`-equivalent, env probes).
   Each check shows expected output.
3. **Reproduction Commands** — for every test/binary listed in the
   troubleshooter's "Tests / binaries involved", produce the exact runner
   invocation. Prefer `compute-utils/scripts/hip_test/run_hip_unit_test.sh`
   etc. (see tester.md). For each, show: full command, expected exit code,
   how to capture output (`-o <file>`), and what a "matches the reported
   bug" outcome looks like vs "does not reproduce".
4. **Diagnostic Captures** — for the SEGFAULT / hang / undefined-behavior
   cases the troubleshooter flagged, the rocgdb / coredump / dmesg /
   strace incantations needed. These ARE the cases manual invocation is
   appropriate for — make that explicit.
5. **What to Send Back** — a numbered checklist of artifacts the operator
   should return (full Catch2 console+success output per test, stack
   traces, dmesg snippets, the env they ran under). The pipeline will
   resume from these.
6. **Local-vs-Remote Divergence Notes** — restate, briefly, why local
   results were not authoritative, so a reader who only sees this plan
   understands why running it remotely is necessary.

Write the plan to:
  <thinking_dir>/scripts/<iteration>-bash-expert-handoff.md

Keep the plan executable — operator should be able to copy commands
verbatim. Do NOT include `$VAR` expansions in any command in the plan;
use the same expansion-safe forms as the rules above.
""")
```

The session does NOT route this output through the PM. It saves the
result, tells the user where to find it, and asks for direction.

### Loop Control

**Hard cap:** Maximum 3 major cycles. If `major > 3`:
- Read status.md
- Present to user: "Hit 3 cycle cap. Here's where we are: <status>. Continue (fresh budget) / change direction / stop?"

**Iteration numbering:**
- `major.minor` format
- PM's `iteration_change` field controls this:
  - `"none"` → no change
  - `"minor"` → increment minor (1.0 → 1.1)
  - `"major"` → increment major, reset minor (1.2 → 2.0)

### Error Handling

If an agent dispatch fails (error, timeout, empty output):

1. **Retry once** with the same prompt
2. If retry fails, dispatch PM:
   ```
   Agent(subagent_type: "pm-orchestrator", prompt: """
   ADVISOR MODE. Agent <name> failed twice. Error: <error>.
   What was it doing: <context>.
   Return JSON: escalation (ask user) or next-step (skip and continue).
   """)
   ```
3. For Git Agent failures mid-operation: **STOP immediately**. Present the error to the user. Do not retry.

### Phase 2.5: Wider Suite Execution

After targeted tester pass + reviewer pass, the session may execute a wider regression suite to catch fallout from the change. This phase runs between Phase 2 and Phase 3 and is entered from Phase 3 Step 0.5.

Entry conditions, the 8-step state machine (sanity-check → final suite list → wider execution → triage decisions → triage budget → per-test triage loop → test status determination → pre-existing failures logging), the Re-entry Guard, and all dispatch templates are documented in:

**Read and follow: `skills/workflow/phase-2.5-wider-suite.md`**

Return contract:
- Normal exit (no work, wider-pass, pre-existing-flagged, cannot-classify) → Phase 3 Step 1
- Regression path → loops back to Phase 2 main loop (do NOT continue to Phase 3 Step 1)

### Phase 3: Completion Flow

When PM returns `type: "completion"`:

**Step 0: Independent verification (before presenting to user)**

Do NOT trust the PM's completion claim. Verify independently.

**For knowledge questions** (classification was `"knowledge"` and `offer_review` is `false`):
- Only check that `<thinking_dir>/analysis/` contains the expert's output
- No build/test/review artifacts expected — skip to Step 1

**For all other tasks** (design, bug, script):
0. **Check Build Status in status.md.** Read the `Build Status` field.
   - If `BUILT` → continue to checks below
   - If `BUILD DEFERRED` → verification fails. Do NOT re-dispatch PM. Instead, dispatch build-expert directly: "Reviewer passed. Perform the actual build now." Then dispatch tester after a successful build. Update Build Status to `BUILT`. Then re-enter Phase 3 Step 0 from the top.
   - If `NOT BUILT` or `BUILD FAILED` → verification fails. Dispatch build-expert directly. Same flow as BUILD DEFERRED above.
1. Check that `<thinking_dir>/builds/` contains a build results file with a passing result
2. Check that `<thinking_dir>/tests/` contains a test results file. Acceptable verdicts:
   - `pass` — full verification
   - `cannot-test` — acceptable IF the report includes a valid reason (e.g., no GPU) AND the reviewer acknowledged the gap. Note this in the summary.
   - `fail` or missing → verification fails
3. Check that `<thinking_dir>/reviews/` contains a reviewer output with `pass` verdict

If checks 1-3 fail (required artifacts missing or show failures):
- Do NOT present completion to the user
- Re-dispatch PM with: "Verification gate failed. Missing/failing: [list what's wrong]. Route to the appropriate agent."
- Re-enter Phase 2

**Test Status note for Phase 3:** Phase 3 may receive any of `TESTED (targeted-pass | wider-pass | pre-existing-flagged | cannot-classify)` or `CANNOT TEST`. `TESTED (regression)` never reaches Phase 3 — it loops back through Phase 2 from Phase 2.5 Step 7a.

**Step 0.5: Wider Suite Execution (enter Phase 2.5)**

After Step 0 verification passes, before Step 1 presentation, the session enters Phase 2.5: Wider Suite Execution. See the dedicated Phase 2.5 section above for the full state machine.

Phase 2.5 may:
- Find no work to do (entry conditions not met, or guard skips re-entry) → return here, continue to Step 1
- Run wider suite and pass → update Test Status to `TESTED (wider-pass)` → return here, continue to Step 1
- Run wider suite, find pre-existing failures → log them, update Test Status to `TESTED (pre-existing-flagged)` or `TESTED (cannot-classify)` → return here, continue to Step 1
- Run wider suite, find regression → loop back through Phase 2 (do NOT continue to Step 1)

**Step 1: Present summary to user** (only after verification passes and Phase 2.5 returns)
- What was done (from PM's summary)
- Files changed
- Commits made (read from status.md)
- Thinking artifacts: `<thinking_dir>/`
- Test artifacts: `<workspace>/testing/<topic>/`
- **Testing gaps** (if tester reported `cannot-test`): what couldn't be verified and why
- **PR feedback round trip** (only if `<thinking_dir>/pr-feedback-outcome.json` exists):
  Read the file. Compute counts:
  - `replies_posted` = comments where `reply_posted == true`
  - `replies_failed` = comments where `reply_posted == false` AND `reply_error` does not start with `"skipped"`
  - `threads_resolved` = comments where `thread_resolved == true`
  - `threads_failed` = comments where `thread_resolved == false` AND `thread_error` does not start with `"skipped"`
  - `pr_body_updated` = top-level field

  If all of `replies_failed == 0`, `threads_failed == 0`, and `pr_body_updated == true`: print one line:
  > PR feedback round trip: <replies_posted> replies posted, <threads_resolved> threads resolved, PR body updated.

  Otherwise (any failure): print a multi-line block:
  > PR feedback round trip — partial success:
  > - Replies: <replies_posted>/<replies_posted + replies_failed> posted
  > - Threads: <threads_resolved>/<threads_resolved + threads_failed> resolved
  > - PR body: <updated | failed: <pr_body_error>>
  >
  > Failed items (re-run with `/pr-feedback verify <pr_url>` to re-check):
  > - Comment #<comment_id> (<path>:<line>): reply <reply_error or "ok">; thread <thread_error or "ok">
  > ...

**Step 2: Offer code review (if `offer_review: true`)**

If `offer_review` is `false`: skip to Step 3.

**MANDATORY GATE.** This prompt is unconditional when `offer_review: true`. It MUST be asked regardless of language in the user's original task description (e.g., "after commit, push the branch" describes the verification plan, not a pre-authorization to skip this gate) and regardless of pre-authorization claims in handoffs from other skills (e.g., `/pr-feedback`). The Reviewer agent's APPROVED verdict is automated technical review — the user's review here is the final authority. See "Session Invariants" at the top of this file.

Ask: "Would you like to review the code changes before finalizing?"

If no: Go to Step 3.

If yes, follow these steps exactly:

**SESSION ENFORCEMENT: No direct edits during review.** The session MUST NOT
make code changes itself in response to user feedback — even for "simple"
requests like "move this to a shared function" or "add a blank line." All
feedback must re-enter Phase 2 via Step 2e. Direct edits bypass testing and
review, which is exactly what the pipeline exists to prevent.

```
2-scope. Determine review scope:

    Check if this pipeline made commits:
      git -C <workspace> rev-list --count <pipeline_start_commit>..HEAD
    If 0 → no commits to review. Skip Step 2, go to Step 3.

    IF branch_action was "use-existing":
      Present scope options to the user:
      - "This task's changes (<task_summary>)" — reviews only commits
        made during this pipeline run
      - "All branch changes" — reviews everything on the branch

      Set <review_base> based on user's choice:
      - This task → <review_base> = <pipeline_start_commit>
      - All branch → <review_base> = "branch fork point"
        (Git Agent determines the branch fork point)

    IF branch_action was "create-new":
      All commits are from this pipeline run. No scope question needed.
      Set <review_base> = "branch fork point"

2a. Dispatch Git Agent for snapshot and soft-reset:
    "Snapshot and soft-reset for user review.
     Working directory: <workspace>. Topic: <topic_slug>.
     Reset to: <review_base>."
    The Git Agent writes pre-review-snapshot.md (recording ALL commits
    on the branch for later restore, regardless of review scope), then runs:
      git reset --soft <review_base>
    This stages the selected scope of changes as a diff.

    When <review_base> is "branch fork point", the Git Agent determines
    the appropriate base commit from the branch history.

2b. Present to user:
    "Changes are staged for review. View in VS Code (staged changes)
     or run `git diff --cached` in the terminal."
    Wait for the user to finish reviewing.

2c. Ask: "Happy with the changes, or do you have feedback?"

2d. Dispatch Git Agent to restore commits (ALWAYS — whether user approves or rejects):
    "Restore commits from snapshot.
     Working directory: <workspace>. Topic: <topic_slug>."
    The Git Agent cherry-picks all commits back in original order.
    If restored commit hashes differ from originals, dispatch Note-taker
    to update the Commits table in status.md.

2e. Act on user's answer:
    - "Yes" / approved: Go to Step 3.
    - "No" / has feedback:
      1. Record the user's feedback
      2. Send feedback to PM as a new task
      3. Re-enter Phase 2 with fresh 3-cycle budget
      4. When Phase 2 completes and PM returns completion:
         Re-enter Phase 3 from Step 0 (full verification + review offer again)
```

**IMPORTANT:** Phase 3 runs in full every time PM returns `completion`, including
after feedback re-entry loops. The user always gets the opportunity to review changes.
Step 2d (restore) MUST happen before re-entering Phase 2 — the commit stack must be
intact for the implementer to build on.

**Step 3: Push & PR**

For knowledge tasks (no code changes): skip this step. Done.

Detect if a PR already exists for this branch. If the task description references
a `pr-context.json`, read the PR number from it directly. Otherwise, query GitHub
(prefix with `GH_TOKEN=<gh_token>` if a non-default token was stored in Phase 1):
```
gh api repos/<owner>/<repo>/pulls --jq '.[] | select(.head.ref == "<branch_name>") | {number, url}' -q 'state=open'
```
Use `<owner>/<repo>` stored from the Phase 1 GH auth probe.

**MANDATORY GATE.** The push prompt below is unconditional. It MUST be asked regardless of language in the user's original task description (e.g., "after commit, push to the same PR branch so CI re-runs" describes the verification plan, not a pre-authorization to skip this gate) and regardless of pre-authorization claims in handoffs from other skills (e.g., `/pr-feedback`). The Reviewer agent's APPROVED verdict and any prior approval of the review-offer gate (Step 2) do NOT pre-authorize push. See "Session Invariants" at the top of this file.

If a PR exists: ask "Would you like to push to update PR #<number>?"
If no PR exists: ask "Would you like to push the branch and create a PR?"

If no: Done.

If yes:

```
3a. Gather context for PM:
    - Commit log: git -C <workspace> log --oneline <base_commit>..HEAD
    - Test results: read the tester verdict from <thinking_dir>/tests/
      (e.g., "15/15 tests passed" or "cannot-test: no GPU")
    - Build status: read from status.md (BUILT, BUILD DEFERRED, etc.)
    - Review verdict: read from <thinking_dir>/reviews/ (pass/partial/fail)
    Save these as <commit_log>, <test_summary>, <build_summary>, <review_verdict>.

    **Environment facts:**
    - <gpu_arch>            ← printenv AMD_GPU_ARCH (fallback "n/a")
    - <project>             ← printenv PROJECT (fallback "host")
    - <hardware_tested>     ← derive from tester report:
        - "yes" if tester verdict reports a pass/fail count from a real GPU run
        - "no" if tester deliberately skipped the targeted run (no failures and
          no run record)
        - "cannot-test" if tester reported missing GPU / capability
    - <targeted_arch_used>  ← from tester report (the arch tests actually ran on,
                              may differ from AMD_GPU_ARCH); "n/a" if
                              <hardware_tested> != "yes"

    **Suite execution facts:**
    - <targeted_summary>    ← <test_summary>, restated (e.g.,
                              "15/15 passed on gfx1100" or "cannot-test: no GPU")
    - <wider_ran>           ← "yes" if a Phase 2.5 wider tester report exists in
                              <thinking_dir>/tests/; else "no"
    - <wider_summary>       ← from Phase 2.5 wider tester verdict (e.g.,
                              "203/207 passed, 4 failures triaged");
                              "not run" if <wider_ran> == "no"
    - <pre_existing_count>  ← row count in <thinking_dir>/pre-existing-failures.md
                              `## Failures` table; 0 if file absent
    - <regression_count>    ← rows classified as regression in this iteration
                              (from triage logs); 0 if Phase 2.5 didn't classify
                              any (status.md state reaching Phase 3 implies all
                              regressions were already addressed)

3a.5. Pre-existing Failures Triage (only if Phase 2.5 surfaced any):

    If `<thinking_dir>/pre-existing-failures.md` is absent OR contains zero
    failure rows, set `<known_issues_section>` to empty string and skip to 3b.

    Otherwise, **read and follow: `skills/workflow/pre-existing-failures-triage.md`**

    Inputs: `<thinking_dir>/pre-existing-failures.md`, `<owner>/<repo>` (from Phase 1)
    Outputs: `<known_issues_section>` string for use in 3b PR body composition.
             Caches `<issue_mode>` (live or draft) for this pipeline run.
3b. Dispatch PM to construct PR content:
    Agent(subagent_type: "pm-orchestrator", prompt: """
    ADVISOR MODE. Return ONLY a JSON block, no prose.

    Construct a PR title and body for the completed work.

    RULES for the PR:
    - Title: Capture the HIGH-LEVEL GOAL of the entire branch — what the
      user set out to accomplish. NOT a commit message. Think "what does
      this PR do for the project?" (under 70 chars)
    - Summary: 2-4 bullets covering the key changes
    - Test plan: Checklist of verification items. Each checkbox MUST mirror
      a concrete pipeline fact from the Environment + Suite execution blocks
      below. Pre-check (- [x]) ONLY what the pipeline actually verified.
      - Hardware test items: [x] if hardware_tested == "yes" AND ran on the
        targeted arch. [ ] if hardware_tested is "no" or "cannot-test".
      - Build items: [x] if Build status is BUILT. [ ] otherwise.
      - Wider-suite items: [x] if wider_ran == "yes" AND no regressions
        remain. [ ] if wider_ran == "no".
    - Verification: Brief summary of pipeline results (test count, build
      status, review verdict). When hardware_tested is "no" or "cannot-test",
      explicitly state that hardware testing was not performed and why.
      Reference the thinking directory for full artifacts.
    - DO NOT include a "## Environment" section in your body. The session
      will deterministically append one after your body if hardware_tested
      == "yes". Any `## Environment` heading you produce will be stripped.
    - DO NOT include a "Known Issues" section in your body. The session
      will deterministically append one after your body if pre-existing
      failures were surfaced. Any `## Known Issues` heading you produce
      will be stripped to prevent duplicates.
    - DO NOT include a Claude signature line (e.g. `🤖 Claude Code 🤖`).
      The session will deterministically append one. Any signature line
      you produce will be stripped to prevent duplicates.

    Completion summary: <PM's completion summary from the completion response>

    Commit log:
    ---
    <commit_log>
    ---

    Pipeline results:
    - Tests: <test_summary>
    - Build: <build_summary>
    - Review: <review_verdict>
    - Artifacts: <thinking_dir>/

    Environment:
    - GPU arch: <gpu_arch>
    - Container project: <project>
    - Hardware tested: <hardware_tested>
    - Targeted arch used: <targeted_arch_used>

    Suite execution:
    - Targeted: <targeted_summary>
    - Wider suite ran: <wider_ran>
    - Wider suite: <wider_summary>
    - Pre-existing failures surfaced: <pre_existing_count>
    - Regressions caught and fixed: <regression_count>

    Respond with ONLY a JSON block:
    {"type":"pr-content", "title":"<high-level PR title, under 70 chars>", "body":"<markdown body with ## Summary, ## Test plan (pre-checked items), and ## Verification sections>"}
    """)

    This is a content-construction dispatch, not a routing decision.
    Extract `title` and `body` directly from the JSON — full normalization
    is not required.

    **Compose final PR body (deterministic, session-side):**
    Final body order: PM body → Environment (if hardware tested) → Known Issues
    (if Phase 2.5 surfaced any) → Claude signature.

    1. Take the PM-returned `body` string as `<working_body>`.

    2. If `<hardware_tested>` == "yes":
       a. Build `<environment_section>`:
          ```markdown
          ## Environment
          - GPU arch: <gpu_arch>
          - Container project: <project>
          - Tested on real hardware: yes (arch: <targeted_arch_used>)
          ```
       b. Strip any pre-existing `## Environment` heading + its content from
          `<working_body>` (defensive — PM was instructed to omit, but enforce
          here). A "section" runs from `## Environment...` up to the next `## `
          heading or end-of-string.
       c. Append `<environment_section>` to `<working_body>` with one blank
          line of separation.

    3. If `<known_issues_section>` (from step 3a.5) is non-empty:
       a. Strip any pre-existing `## Known Issues` heading + its content from
          `<working_body>` (defensive). A "section" runs from `## Known Issues...`
          up to the next `## ` heading or end-of-string.
       b. Append `<known_issues_section>` to `<working_body>` with one blank
          line of separation.

    4. Append Claude signature (always — every pipeline-created PR carries it):
       a. Strip any trailing `🤖 Claude Code 🤖` line from `<working_body>`
          (defensive — PM was instructed to omit, but enforce here to prevent
          duplicates).
       b. Trim trailing whitespace from `<working_body>`.
       c. Append `\n\n🤖 Claude Code 🤖` to `<working_body>`.

    5. Save `<working_body>` as `<final_body>`. Pass `<final_body>` (NOT the raw
       PM body) into the Git Agent dispatch in step 3c.

3c. Dispatch Git Agent to push (and create PR if needed):

    **GH token handling:** If `<gh_token>` was stored in Phase 1 (non-empty, different
    from the default GH_TOKEN), include this instruction in the Git Agent prompt:
    "For all `gh` commands, prefix with: GH_TOKEN=<gh_token>"
    This ensures the Git Agent uses the correct GitHub account for API operations.
    Git push uses SSH keys and is unaffected by GH_TOKEN.

    IF an existing PR was detected:
      Agent(subagent_type: "git-agent", prompt: """
      Push the current branch to update the existing PR.
      Working directory: <workspace>.
      <if gh_token: "For all gh commands, prefix with: GH_TOKEN=<gh_token>">

      Push: git push origin <branch_name>
      Report success when done.
      """)

    IF no existing PR:
      Agent(subagent_type: "git-agent", prompt: """
      Push the current branch and create a pull request.
      Working directory: <workspace>.
      <if gh_token: "For all gh commands, prefix with: GH_TOKEN=<gh_token>">

      1. Push: git push -u origin <branch_name>
      2. Create PR targeting <branch_base> with exactly this title and body:

      Title: <title from PM>

      Body:
      <final_body>

      Use: gh pr create --base <branch_base> --title "..." --body "..."
      Report the PR URL when done.
      """)

3d. Handle PR review comment updates (PR feedback tasks only):

    Parse the task description for a line matching the line-anchored regex
    `^PR_CONTEXT: (\S+)$` (this is the structured handoff marker emitted by
    `/pr-feedback`). If absent OR the captured path fails `test -f`, skip to
    Step 3e (normal workflow, not PR feedback). Prose mentions of
    `pr-context.json` elsewhere in the task description do NOT trigger
    engagement.

    If marker present and file exists, **read and follow: `skills/workflow/pr-feedback-handoff.md`**

    Inputs: `<workspace>`, the `pr-context.json` absolute path from the marker
    Outputs: posted replies, resolved review threads, updated PR description,
             `<thinking_dir>/pr-feedback-outcome.json` (consumed by Step 1)
3e. Present PR URL to user. Done.
```

If `git push` or `gh pr create` fails (e.g., no GitHub remote, no `gh` auth,
permission denied), inform the user of the error and the branch name so they
can push/create the PR manually. Do not retry.

**Post-workflow GH operations:** If the user requests `gh` operations after the
workflow completes (e.g., `gh pr merge`), use the stored `<gh_token>` from
Phase 1 by prefixing commands with `GH_TOKEN=<gh_token>`. This avoids the
session having to rediscover the correct account.

## When to Use This vs. Other Skills

| Use `/workflow` | Use other skills |
|----------------|-----------------|
| ROCm/HIP implementation tasks | Quick one-off questions |
| Bug investigations needing multiple agents | Standalone design discussions |
| Multi-step work: think → plan → implement → review | Tasks outside ROCm/HIP domain |
| Script/automation work in ROCm context | Simple file edits |
