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

Respond with ONLY a JSON block — no prose before or after. Use EXACTLY these 9 fields, no extras:

```json
{
  "type": "initial-routing",
  "workspace": "...",
  "branch_action": "use-existing or create-new",
  "branch_name": "...",
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

> Working in: `<workspace>` on branch `<branch>`
> Task: <task_summary>. Is that right?

If the user corrects anything, re-dispatch PM with the corrections.

**Step 3: Create thinking directory**

Create the directories yourself with a single mkdir command (NO brace expansion), then dispatch Note-taker for status.md only:

```bash
# Session runs this directly — NOT dispatched to an agent
# IMPORTANT: Inline the full path. Do NOT use $VAR — it triggers expansion prompts.
mkdir -p <workspace>/thinking/YYYY-MM-DD-<topic_slug>/analysis <workspace>/thinking/YYYY-MM-DD-<topic_slug>/plans <workspace>/thinking/YYYY-MM-DD-<topic_slug>/tests <workspace>/thinking/YYYY-MM-DD-<topic_slug>/reviews <workspace>/thinking/YYYY-MM-DD-<topic_slug>/investigations <workspace>/thinking/YYYY-MM-DD-<topic_slug>/builds <workspace>/thinking/YYYY-MM-DD-<topic_slug>/commits <workspace>/thinking/YYYY-MM-DD-<topic_slug>/scripts <workspace>/thinking/YYYY-MM-DD-<topic_slug>/pm-summaries <workspace>/thinking/YYYY-MM-DD-<topic_slug>/requests
mkdir -p <workspace>/testing/YYYY-MM-DD-<topic_slug>
```

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

- If `branch_action` is `create-new` AND `classification` is `design` or `script`:
  - Dispatch the Git Agent now:
    ```
    Agent(subagent_type: "git-agent", prompt: "Create and switch to branch <branch_name>. Working directory: <workspace>")
    ```
  - Set `branch_created = true`

- If `branch_action` is `create-new` AND `classification` is `bug` or `knowledge`:
  - Do NOT create the branch yet. Save `branch_name` for later.
  - Set `branch_created = false`

- If `branch_action` is `use-existing`:
  - No action needed.
  - Set `branch_created = true` (or N/A)

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
| `initial-routing` | `workspace`, `branch_action`, `branch_name`, `task_summary`, `topic_slug`, `starting_agent`, `starting_context`, `classification` |
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

Set `iteration = "1.0"`, `major = 1`, `minor = 0`.

**Dispatch the starting agent and enter the loop:**

```
LOOP:
  1. Dispatch the current agent (see "How to Dispatch a Specialist" below)
  2. Handle output saving (see "Note-taker Rules" below)
  3. Send agent output to PM for routing (see "Ask PM What's Next" below)
  4. Parse PM response and act on it:

     IF type = "next-step":
       - Update iteration if PM says to (minor++ or major++)
       - IF next_agent = "reviewer": run the Reviewer Gating Check (see below)
       - Set current agent = next_agent
       - Build context from PM's context_notes and pass_files
       - CONTINUE LOOP

     IF type = "fulfill-request":
       - Dispatch the target agent with PM's context_notes
       - Handle output saving for target agent
       - If then_resume is set: re-dispatch the original agent with
         the target's results file path and PM's resume_context
       - Send the resumed agent's output to PM
       - CONTINUE LOOP

     IF type = "commit":
       - If `branch_created` is false (deferred from Step 4):
         - Dispatch Git Agent to create the branch first:
           "Create and switch to branch <branch_name>. Working directory: <workspace>"
         - Set `branch_created = true`
       - Dispatch Git Agent to commit specified files
       - Handle output saving for Git Agent
       - Run the Mandatory Post-Commit Sequence (see below)
       - Send result to PM (tester output if built, build-expert analysis if deferred)
       - CONTINUE LOOP

     IF type = "completion":
       - Go to Phase 3 (Completion Flow)
       - BREAK LOOP

     IF type = "escalation":
       - Present PM's question and options to the user
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

Workspace: <workspace>
Thinking directory: <thinking_dir>
Iteration: <iteration>
User request: <one-line task summary>

<task-specific context from PM's context_notes>

Read these files for context:
<list of pass_files from PM>

<if this is a re-dispatch after a cross-agent request:>
Results from <target_agent> are at: <results_file_path>
Continue your work incorporating those results.
""")
```

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
     - If MISSING: dispatch build-expert first (use file-path → component mapping)
     - Handle output saving, then re-check

  2. Check <thinking_dir>/tests/ for a test results file
     - If MISSING: dispatch tester first
     - Handle output saving, then re-check

  3. Only after BOTH exist: dispatch the reviewer
     - Include build results file and test results file in pass_files
```

For `knowledge` tasks: skip this check (no build/test expected).

### Mandatory Post-Commit Sequence

After every `commit` action (for `design`, `bug`, or `script` tasks), the session MUST run the build-expert for diff analysis. The build-expert decides whether to build immediately or defer the build until after the reviewer passes.

```
POST-COMMIT:
  1. Determine the build component from the committed files:
     - Files under rocm-systems/projects/hip-tests/ → "hip-tests+build"
     - Files under rocm-systems/projects/clr/ or core/clr/ → "hip-clr+build"
     - Files under rocm-systems/projects/ocl-clr/ → "ocl-clr+build"
     - Standalone .hip/.cpp files (not in TheRock tree) → compile with hipcc directly
     - Shell scripts or non-compiled files → SKIP build-expert entirely, go to step 4

  2. Dispatch build-expert (diff analysis + conditional build):
     "Post-commit dispatch. Analyze the committed diff first. If ALL changes are
      non-functional (comments, docs, whitespace, log strings, .md/.txt files),
      report BUILD_DECISION: DEFERRED and skip building. If ANY changes are functional,
      build incrementally and report BUILD_DECISION: BUILT.
      Component: <component>. Target: <target>. Workspace: <workspace>."
     - Handle output saving (Note-taker for build-expert)

  3. Parse build-expert output for BUILD_DECISION and update Build Status in status.md:

     IF BUILD_DECISION is BUILT AND build PASSED:
       - Update status.md: `Build Status: BUILT`
       - Dispatch tester:
         "Verify the changes compile and run correctly. Component: <component>.
          Build output: <build results file path>. Workspace: <workspace>."
         - Handle output saving (tester writes own output)
         - Return tester output to the main loop (sent to PM for routing)

     IF BUILD_DECISION is BUILT AND build FAILED:
       - Update status.md: `Build Status: BUILD FAILED`
       - Do NOT proceed to tester
       - Send build output to PM. PM routes back to implementer.

     IF BUILD_DECISION is DEFERRED:
       - Update status.md: `Build Status: BUILD DEFERRED`
       - Do NOT dispatch tester
       - Return build-expert analysis to the main loop (sent to PM for routing)
       - PM reads Build Status from status.md and routes to reviewer

  4. (Shell scripts / non-compiled files only) Skip build, dispatch tester directly,
     update status.md: `Build Status: BUILT` (no compilation needed for scripts)
```

When dispatching the reviewer and Build Status is `BUILD DEFERRED`, include in the reviewer's context:
"Build was deferred — changes are non-functional only (comments/docs/formatting). Focus on spec compliance and code quality. Build verification is pending after review."

### Build Status Reset

When the PM routes back to implementer, planner, or hip-expert after a reviewer rejection (partial/fail-spec/fail), the session MUST update status.md: `Build Status: NOT BUILT`. This ensures stale build state from a prior iteration cannot leak into the next one. The next commit triggers the post-commit sequence, which sets Build Status fresh.

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

### Phase 3: Completion Flow

When PM returns `type: "completion"`:

**Step 0: Independent verification (before presenting to user)**

Do NOT trust the PM's completion claim. Verify independently.

**For knowledge questions** (classification was `"knowledge"` and `offer_review` is `false`):
- Only check that `<thinking_dir>/analysis/` contains the expert's output
- No build/test/review artifacts expected — skip to Step 1

**For all other tasks** (design, bug, script):
1. Check that `<thinking_dir>/builds/` contains a build results file with a passing result
2. Check that `<thinking_dir>/tests/` contains a test results file. Acceptable verdicts:
   - `pass` — full verification
   - `cannot-test` — acceptable IF the report includes a valid reason (e.g., no GPU) AND the reviewer acknowledged the gap. Note this in the summary.
   - `fail` or missing → verification fails
3. Check that `<thinking_dir>/reviews/` contains a reviewer output with `pass` verdict

If ANY required artifacts are missing or show failures:
- Do NOT present completion to the user
- Re-dispatch PM with: "Verification gate failed. Missing/failing: [list what's wrong]. Route to the appropriate agent."
- Re-enter Phase 2

**Step 1: Present summary to user** (only after verification passes)
- What was done (from PM's summary)
- Files changed
- Commits made (read from status.md)
- Thinking artifacts: `<thinking_dir>/`
- Test artifacts: `<workspace>/testing/<topic>/`
- **Testing gaps** (if tester reported `cannot-test`): what couldn't be verified and why

**Step 2: Offer code review (if `offer_review: true`)**

Ask: "Would you like to review the code changes before finalizing?"

If yes:
1. Dispatch Git Agent to snapshot and soft-reset (per its User Review Flow instructions)
2. User reviews the staged diff
3. Ask: "Happy with the changes?"
   - **Yes:** Dispatch Git Agent to restore commits. Done.
   - **No:** Get feedback. Dispatch Git Agent to restore. Send feedback to PM as a new task. Re-enter Phase 2 with fresh 3-cycle budget.

If no: Done. Commits stay as-is.

## When to Use This vs. Other Skills

| Use `/workflow` | Use other skills |
|----------------|-----------------|
| ROCm/HIP implementation tasks | Quick one-off questions |
| Bug investigations needing multiple agents | Standalone design discussions |
| Multi-step work: think → plan → implement → review | Tasks outside ROCm/HIP domain |
| Script/automation work in ROCm context | Simple file edits |
