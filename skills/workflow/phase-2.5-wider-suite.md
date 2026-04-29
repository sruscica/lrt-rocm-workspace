# Phase 2.5: Wider Suite Execution

> Invoked from Phase 3 Step 0.5 of `skills/workflow/SKILL.md`. Returns to Phase 3 Step 1, except the regression path which loops back to the Phase 2 main loop. The session reads this file when entering Phase 2.5 and follows the state machine below.

After targeted tester pass + reviewer pass, the session may execute a wider regression suite to catch fallout from the change. This phase runs between Phase 2 and Phase 3 and is entered from Phase 3 Step 0.5.

**Entry conditions (ALL must be true):**
1. The most recent tester report contains a `### Wider Suite Proposal` section with at least one proposed suite (not "No wider regression suite needed")
2. Build Status is `BUILT`
3. Test Status is `TESTED (targeted-pass)`
4. The Re-entry Guard below permits entry

**Re-entry Guard:** If Test Status is **currently** a wider-suite outcome (`TESTED (wider-pass | pre-existing-flagged | cannot-classify)`), skip Phase 2.5 — wider work is done for this code state. The guard clears when Test Status transitions back to `TESTED (targeted-pass)` (which happens after a fresh targeted tester run following any code change). `TESTED (regression)` never reaches Phase 3 (it loops back through Phase 2 from Step 7a) so it is not a guard state. Test Status Reset (on reviewer rejection) or major iteration increment also clears it by setting `NOT TESTED`.

If any entry condition fails OR the guard skips entry: Phase 2.5 does nothing. Return to Phase 3 Step 1.

## Step 1: Expert Sanity-Check Dispatch

Determine the expert from the majority of changed-file extensions:

| Changed file extensions (majority) | Expert |
|-----------------------------------|--------|
| `.cpp`, `.hip`, `.c`, `.h`, `.hpp`, `.cmake`, `CMakeLists.txt` | `hip-expert` |
| `.sh`, `.yaml`, `.json`, `.toml`, Dockerfile, config | `bash-expert` |
| Mixed or unclear | `hip-expert` (default) |

Increment the iteration minor for this sub-step. Dispatch the expert with `MODE: wider-suite-sanity-check` and the tester's Wider Suite Proposal:

```
Agent(subagent_type: "<expert>", prompt: """
You are the <expert> in the ROCm Agent Pipeline.
You do NOT have the Agent tool.

[standard COMMAND RULES block]

## Task: Sanity-check a wider regression suite proposal (no execution)

The Tester proposed a wider regression suite. Validate, refine, or amend the proposal — do NOT run anything.

### Changed files
<list from tester's proposal "Changed files" sub-field>

### Tester's proposed suites
<list from tester's proposal "Proposed test binaries / categories">

### Tester's rationale
<from tester's proposal>

### Tester's confidence
<from tester's proposal>

### Plan summary
<read latest plan from <thinking_dir>/plans/>

## Output (these EXACT sections)

### Amended Suite List
Bullet list of the FINAL suites/categories that should run. Mark each entry KEPT, ADDED, or REMOVED.

### Removed Suites
Suites struck from the tester's proposal, one per line, with one-sentence rationale each.

### Rationale
One paragraph explaining additions/removals.

### Confidence
`high`, `medium`, or `low` in the final amended list.
""")
```

Apply Note-taker Rules to save the expert's output to `<thinking_dir>/analysis/<major>.<minor>-<expert>-wider-sanity-check.md`.

## Step 2: Compute Final Suite List

Parse the expert's "Amended Suite List". Compute:

```
final_suite_list = expert_amended_list  -  (PR-modified test files)
```

Determine PR-modified test files by reading the Commits table in status.md and filtering paths matching `*test*`, `tests/`, `*_test.cpp`, `*Test*.cpp`, `*test*.cc`. The targeted tester run already covered these.

If `final_suite_list` is empty:
- Update status.md: `Test Status: TESTED (wider-pass)` (no-op pass)
- Note-taker logs in Agent Activity Log: "Phase 2.5 skipped — final suite list empty"
- Return to Phase 3 Step 1

## Step 3: Wider Tester Dispatch (execution mode)

Increment iteration minor. Re-dispatch the tester in `wider-execution` mode with the final suite list. Sub-step label: `<major>.<minor>-tester-wider`.

```
Agent(subagent_type: "tester", prompt: """
[standard agent dispatch template with COMMAND RULES]

Workspace: <workspace>
Thinking directory: <thinking_dir>
Iteration: <major>.<minor>

MODE: wider-execution

Run the following wider regression suites (do NOT propose, do NOT triage — just run):
<final suite list>

Write your report to <thinking_dir>/tests/<major>.<minor>-tester-wider.md.

Required sections:
- ### Environment (probe results)
- ### Wider Execution Results (per-suite pass/fail counts)
- ### Failing Tests (FLAT list of every individual failing test name across all suites — one line per failure, format: `<suite>::<test_name>`)
- ### Verdict (`pass`, `fail`, or `cannot-test`)
- ### Artifacts (per-suite log paths)

DO NOT include a Wider Suite Proposal section in this report — the session is gating on the failure list.
""")
```

Apply Note-taker Rules for status.md updates.

## Step 4: Decide on Triage

Read the wider tester report:

- **`pass`** (all suites all-pass): Update `Test Status: TESTED (wider-pass)`. Return to Phase 3 Step 1.
- **`cannot-test`**: Update `Test Status: CANNOT TEST`. Note reason in Agent Activity Log. Return to Phase 3 Step 1 (gap noted in completion summary).
- **`fail`**: Read `### Failing Tests` flat list. Continue to Step 5.

## Step 5: Triage Budget Check

The per-iteration triage budget is **2** failing tests.

If `failing_count > 2`:
- Skip per-test triage entirely
- Note-taker writes all failing tests to `<thinking_dir>/pre-existing-failures.md` with classification `UNTRIAGED-CANNOT-CLASSIFY` and rationale "exceeded triage budget (2) — not investigated"
- Update status.md `Test Status: TESTED (cannot-classify)` and add Pre-existing Failures section
- Return to Phase 3 Step 1 (do NOT block — Phase 3 PR step will surface in a later phase)

If `failing_count <= 2`: proceed to Step 6.

## Step 6: Per-Test Triage Loop

For each failing test (up to 2):

**6a. Stash source changes** — dispatch git-agent with explicit path lists (no heuristic):

```
Agent(subagent_type: "git-agent", prompt: """
[standard COMMAND RULES block]

Workspace: <workspace>

Phase 2.5 triage stash. Stash source-only changes; preserve test files.

Source paths to stash:
<list of source paths from PR commits>

Test paths to PRESERVE (do NOT stash):
<list of test paths from PR commits>

Run:
  git -C <workspace> stash push -m "phase-2.5-triage" -- <source paths, space-separated>

Report stash ref, files stashed, and verify test paths remain modified
(git -C <workspace> diff --name-only).
""")
```

If git-agent reports failure: mark this test `CANNOT-CLASSIFY` (reason "stash failed"). Restore is N/A. Continue to next test.

**6b. Rebuild without source changes** — dispatch build-expert:

```
Agent(subagent_type: "build-expert", prompt: """
[standard COMMAND RULES block]

Phase 2.5 triage rebuild. Source changes have been stashed; rebuild from current tree.
Component: <derived from failing test's suite>
Workspace: <workspace>

Run incremental rebuild. Report BUILD_DECISION: BUILT (with PASSED or FAILED).
""")
```

If BUILD FAILED: mark this test `CANNOT-CLASSIFY` (reason "rebuild without changes failed"). Run Step 6d (restore) and Step 6e (rebuild back). Continue to next test.

**6c. Triage re-run (N=3)** — dispatch tester in `triage-rerun` mode:

```
Agent(subagent_type: "tester", prompt: """
[standard agent dispatch template with COMMAND RULES]

Workspace: <workspace>
Thinking directory: <thinking_dir>
Iteration: <major>.<minor>

MODE: triage-rerun
N: 3

The build has been rebuilt WITHOUT source changes for triage purposes.
DO NOT build, DO NOT stash, DO NOT modify git state — environment is pre-prepared.

Failing test to re-run:
<failing test name, e.g., TextureTest::Pitch2D_normalizedCoords>

Run the test 3 times. Report:

### Triage Results
| Test | Pass count | Fail count | Notes |
|------|-----------|-----------|-------|
| <test name> | <0-3> | <0-3> | <flake notes if mixed> |

### Verdict
- `regression-candidate` if 3/3 pass without source changes
- `pre-existing-candidate` if 3/3 fail without source changes
- `flake` if mixed
""")
```

**6d. Restore stash** — dispatch git-agent:

```
Agent(subagent_type: "git-agent", prompt: """
[standard COMMAND RULES block]

Workspace: <workspace>

Phase 2.5 triage restore. Pop stash from triage:
  git -C <workspace> stash pop <stash ref>

Verify: git -C <workspace> status should show source files modified again.
Report success or any conflicts.
""")
```

If `stash pop` reports conflicts: STOP triage. Hard error — escalate to user via the standard escalation flow. Do NOT proceed without restoring source state.

**6e. Rebuild with changes** — dispatch build-expert again:

```
Agent(subagent_type: "build-expert", prompt: """
[standard COMMAND RULES block]

Phase 2.5 triage cleanup rebuild. Source changes have been restored from stash.
Rebuild incrementally to restore HEAD state.
Component: <same as 6b>
Workspace: <workspace>
""")
```

**6f. Classify based on triage results:**

| Triage verdict (Step 6c) | Classification |
|--------------------------|----------------|
| `regression-candidate` (3/3 pass without changes) | REGRESSION |
| `pre-existing-candidate` (3/3 fail without changes) | PRE-EXISTING |
| `flake` (mixed) | CANNOT-CLASSIFY |

Record per-test classification for Step 7.

## Step 7: Determine Test Status and Next Path

Aggregate classifications from Step 6 (and any UNTRIAGED-CANNOT-CLASSIFY from Step 5):

- **Any test classified REGRESSION** → REGRESSION PATH (Step 7a)
- **No REGRESSION, all PRE-EXISTING (or PRE-EXISTING + CANNOT-CLASSIFY)** → `Test Status: TESTED (pre-existing-flagged)` (Step 7b)
- **No REGRESSION, all CANNOT-CLASSIFY (no PRE-EXISTING)** → `Test Status: TESTED (cannot-classify)` (Step 7b)

**Step 7a: Regression Path**

Increment iteration minor. Dispatch troubleshooter in the SAME major iteration (do NOT increment major):

```
Agent(subagent_type: "troubleshooter", prompt: """
[standard agent dispatch template]

Iteration: <major>.<minor>

Wider-suite regression detected during Phase 2.5 triage. Investigate the
following confirmed regressions (each reproduced 3/3 only with source changes):

<list of REGRESSION-classified tests with suite::name>

Read for context:
- <thinking_dir>/tests/<wider-tester-report>
- <thinking_dir>/plans/<latest plan>
- <thinking_dir>/analysis/<latest expert sanity-check>

Determine root cause and recommend the next agent (typically planner or implementer).
""")
```

After dispatching troubleshooter:
- Update status.md `Test Status: TESTED (regression)`
- Reset Build Status to `NOT BUILT` (next code change will rebuild)
- Note-taker writes any PRE-EXISTING / CANNOT-CLASSIFY entries to `pre-existing-failures.md` (carry-forward to next iteration)
- Send troubleshooter output back to PM via "Ask PM What's Next" — return to main Phase 2 loop for next-step routing

The PM typically routes to planner or implementer to fix the regression. The loop continues until reviewer + targeted tester pass again. Phase 2.5 then re-enters (the Re-entry Guard was cleared by Test Status Reset on the reviewer-rejection-style cycle, OR is N/A if a major iteration increment occurred).

**Step 7b: Pre-existing / Cannot-classify Path**

- Update status.md `Test Status` per Step 7 rules
- Note-taker writes failures to `<thinking_dir>/pre-existing-failures.md` (Step 8 format) and adds Pre-existing Failures section in status.md
- Do NOT block completion — return to Phase 3 Step 1

(Phase 3 PR construction will use `pre-existing-failures.md` to surface these failures in the PR — that handling is added in a later phase.)

## Step 8: Pre-existing Failures Logging Format

**8a. Capture Reproduction Context (first write only).**

Before dispatching note-taker for the FIRST write to `pre-existing-failures.md` in this pipeline run, the session gathers reproduction context via Bash:

```
git -C <workspace> rev-parse HEAD                       → <workspace_head>
git -C <workspace> rev-parse origin/<branch_base>       → <base_head>  (fallback: "n/a (base unreachable)")
git -C <workspace> submodule status                     → <submodule_status>  (may be empty)
printenv AMD_GPU_ARCH                                   → <gpu_arch>  (fallback: "n/a")
printenv PROJECT                                        → <project>   (fallback: "host")
```

The test command pattern is the exact tester invocation used in the wider-execution dispatch (Step 3) — record it as `<test_command_pattern>`.

The session passes these values to note-taker on the first dispatch. Subsequent dispatches MUST NOT overwrite the Reproduction Context — they only append failure rows (note-taker enforces this; see `agents/note-taker.md`).

Limitation (documented): if the user rebases mid-pipeline-run, the captured hashes can stale. Triage results remain valid for the captured state; reproduce against `<workspace_head>` (which still exists in the reflog) rather than current HEAD.

**8b. File template — SESSION renders, note-taker writes verbatim.**

The session pre-renders the file content and passes it as a literal blob to
note-taker (note-taker is a literal writer, not a templater — see
`agents/note-taker.md`).

**First write — session renders this complete `<file_content>` string:**

```markdown
---
created: <ISO 8601>
iteration: <major>.<minor>
---

# Pre-existing Failures (Wider Suite Triage)

## Reproduction Context
- Workspace: <workspace>
- Workspace HEAD: <workspace_head>
- Base branch: <branch_base> @ <base_head>
- GPU arch: <gpu_arch>
- Container project: <project>
- Test command pattern: <test_command_pattern>
- Submodule state at triage time:
  ```
  <submodule_status>
  ```

## Failures

| Test | Suite | Classification | Evidence | Sub-step |
|------|-------|----------------|----------|----------|
| <first failure row, fully rendered with values> |
```

The session substitutes ALL placeholders before dispatching. Note-taker writes
the resulting blob verbatim (no edits, no normalization).

**Subsequent writes — session renders each new row, note-taker appends:**

The session formats each new failure as a complete pipe-delimited row:
```
| <test name> | <suite> | PRE-EXISTING | 3/3 fail without source changes | <major>.<minor>-tester-wider |
| <test name> | <suite> | CANNOT-CLASSIFY | flake (2 pass / 1 fail) without source changes | <major>.<minor>-tester-wider |
| <test name> | <suite> | UNTRIAGED-CANNOT-CLASSIFY | exceeded triage budget | <major>.<minor>-tester-wider |
```

Note-taker reads the existing file and appends each row to the `## Failures`
table without touching the Reproduction Context block.

**8c. status.md addendum.**

Note-taker also appends a Pre-existing Failures section to status.md:

```markdown
## Pre-existing Failures
| Test | Classification | Iteration |
|------|----------------|-----------|
| <test name> | PRE-EXISTING | <major>.<minor> |
```

These failures DO NOT block completion. Phase 3 Step 3a.5 reads `pre-existing-failures.md` (including the Reproduction Context block) when constructing the PR.
