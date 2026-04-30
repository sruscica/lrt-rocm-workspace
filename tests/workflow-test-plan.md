# /workflow Skill Test Plan

Comprehensive test plan for the ROCm Agent Pipeline (`/workflow` skill).
Each test case is a mock prompt dispatched through the pipeline, with expected routing, agent behavior, and pass criteria.

**How to run:** Each test case lists a `/workflow` prompt and expected outcomes. Tests can be run as:
- **PM-only** (fast): dispatch PM Orchestrator, check JSON routing
- **Single-hop** (medium): dispatch PM + first specialist, check behavior
- **Full pipeline** (slow, ~$30-50): run the complete dispatch loop end-to-end

**Test IDs:** `W-{section}{number}` (e.g., W-C1 = Core Workflow #1)

---

## 1. Core Workflows

### 1.1 Implementing a New HIP API Feature

- [ ] **W-C1**: New API wrapper — full design pipeline
  - Prompt: `Add a hipStreamCreateWithFlags wrapper that combines hipStreamCreate and hipStreamSetFlags`
  - Expected classification: `design`
  - Expected starting agent: `hip-expert`
  - Expected pipeline: hip-expert → planner → implementer → commit → build-expert → tester → reviewer
  - Expected branch: `create-new` (immediate, design task)
  - Pass criteria: PM returns design/hip-expert, session creates branch immediately

- [ ] **W-C2**: New test cases for existing API
  - Prompt: `Add hipMemcpyPeer single-GPU test cases to the memory test suite`
  - Expected classification: `design`
  - Expected starting agent: `hip-expert`
  - Expected pipeline: hip-expert → planner → implementer → commit → build-expert → tester → reviewer
  - Pass criteria: hip-expert analyzes API semantics, planner identifies test file locations, implementer writes Catch2 tests

- [ ] **W-C3**: Feature with ambiguous scope — should escalate
  - Prompt: `Improve the memory management in HIP`
  - Expected classification: `design`
  - Expected starting agent: `hip-expert`
  - Pass criteria: hip-expert provides analysis but notes the scope is too broad; PM should escalate to user for clarification

- [ ] **W-C4**: Feature that already exists — should exit early
  - Prompt: `Add a thread-safe memory pool to HIP for async allocations`
  - Expected classification: `design`
  - Expected starting agent: `hip-expert`
  - Pass criteria: hip-expert identifies `hipMallocAsync`/`hipFreeAsync` already exist; PM returns completion (no code changes needed) or escalation to confirm

### 1.2 Fixing a Failing HIP/OCL Test

- [ ] **W-C5**: Known test failure with error code
  - Prompt: `hipMemcpyAsync returns hipErrorInvalidValue intermittently with large buffers`
  - Expected classification: `bug`
  - Expected starting agent: `troubleshooter`
  - Expected branch: `create-new` (deferred — bug task)
  - Pass criteria: troubleshooter traces error path in CLR source, identifies root cause

- [ ] **W-C6**: Test hang (no error, just stuck)
  - Prompt: `hipDeviceSynchronize hangs after launching a long-running kernel`
  - Expected classification: `bug`
  - Expected starting agent: `troubleshooter`
  - Pass criteria: troubleshooter examines synchronization path, lock ordering, signal/fence mechanisms

- [ ] **W-C7**: Test isolation failure
  - Prompt: `hipMemcpyPeer negative parameter tests pass individually but fail when run in batch`
  - Expected classification: `bug`
  - Expected starting agent: `troubleshooter`
  - Pass criteria: troubleshooter identifies sticky error state from HIP_CHECK_ERROR not draining hipGetLastError()

- [ ] **W-C8**: OCL test failure
  - Prompt: `OpenCL clEnqueueNDRangeKernel returns CL_INVALID_WORK_GROUP_SIZE on gfx1030`
  - Expected classification: `bug`
  - Expected starting agent: `troubleshooter`
  - Pass criteria: troubleshooter investigates OCL runtime path, checks wavefront size constraints for gfx1030

### 1.3 Adding a New Build Dependency

- [ ] **W-C9**: Third-party library dependency
  - Prompt: `Add libfmt as a dependency for the HIP runtime error messages`
  - Expected classification: `design`
  - Expected starting agent: `hip-expert`
  - Pass criteria: hip-expert analyzes impact on build system; planner references TheRock's third-party dependency process (docs/development/adding-third-party-dep.md)

- [ ] **W-C10**: Build system change — CMake modification
  - Prompt: `Enable link-time optimization (LTO) for the HIP runtime build`
  - Expected classification: `design`
  - Expected starting agent: `hip-expert`
  - Pass criteria: analysis covers CMake flag changes, performance vs build-time tradeoffs, compatibility concerns

### 1.4 Refactoring Existing Code

- [ ] **W-C11**: Internal refactor — no API change
  - Prompt: `Refactor hipStreamCreate to separate validation logic from stream initialization`
  - Expected classification: `design`
  - Expected starting agent: `hip-expert`
  - Pass criteria: hip-expert identifies current code structure, planner designs the split, reviewer verifies no behavioral change

- [ ] **W-C12**: API deprecation
  - Prompt: `Deprecate hipStreamCreate in favor of hipStreamCreateWithFlags with a default flag`
  - Expected classification: `design`
  - Expected starting agent: `hip-expert`
  - Pass criteria: hip-expert analyzes backward compatibility impact, identifies all call sites, recommends deprecation strategy

---

## 2. Build Scenarios

### 2.1 Full Rebuild vs Incremental

- [ ] **W-B1**: Full HIP runtime build
  - Prompt: `Do a clean HIP runtime build for gfx1030`
  - Expected classification: `script`
  - Expected starting agent: `bash-expert`
  - Expected pipeline: bash-expert (analysis) → planner → implementer → commit → tester → reviewer
  - Pass criteria: build-expert uses correct cmake flags, THEROCK_AMDGPU_TARGETS=gfx1030, full build targets
  - Permission check: no `${AMD_GPU_ARCH}` — literal `gfx1030`

- [ ] **W-B2**: Incremental rebuild after source change
  - Prompt: `I changed a file in rocm-systems/projects/clr/. Rebuild only what's needed.`
  - Expected classification: `script`
  - Expected starting agent: `bash-expert`
  - Expected pipeline: bash-expert (analysis) → planner → implementer → commit → tester → reviewer
  - Pass criteria: build-expert uses `ninja -C build hip-clr+build` (not full rebuild), source path → target mapping correct

- [ ] **W-B3**: Incremental rebuild of tests only
  - Prompt: `Rebuild hip-tests after modifying a test file`
  - Expected classification: `script`
  - Expected starting agent: `bash-expert`
  - Expected pipeline: bash-expert (analysis) → planner → implementer → commit → tester → reviewer
  - Pass criteria: uses `ninja -C build hip-tests+build`, does not rebuild clr or other components

### 2.2 Build Failures and Diagnostics

- [ ] **W-B4**: Compiler error diagnosis
  - Prompt: `Build failed with "error: no matching function for call to hipStreamCreate" in my new test`
  - Expected classification: `bug`
  - Expected starting agent: `troubleshooter`
  - Pass criteria: troubleshooter identifies API signature mismatch, checks header includes, suggests fix

- [ ] **W-B5**: Linker error diagnosis
  - Prompt: `Build fails with "undefined reference to hipStreamCreateWithPriority" during linking`
  - Expected classification: `bug`
  - Expected starting agent: `troubleshooter`
  - Pass criteria: troubleshooter checks library linking order, symbol visibility, ABI compatibility

- [ ] **W-B6**: CMake configuration error
  - Prompt: `cmake configure fails with "THEROCK_ENABLE_HIP_RUNTIME is not a valid option"`
  - Expected classification: `bug`
  - Expected starting agent: `troubleshooter`
  - Pass criteria: troubleshooter checks CMakeLists.txt, option names, TheRock version compatibility

### 2.3 Dependency Issues

- [ ] **W-B7**: Missing system dependency
  - Prompt: `Build fails because libelf-dev is not installed`
  - Expected classification: `bug`
  - Expected starting agent: `troubleshooter`
  - Pass criteria: troubleshooter identifies the missing package, suggests apt install command

- [ ] **W-B8**: Version mismatch
  - Prompt: `ROCr runtime build fails with "HSA_API_TABLE has different size" — possible ABI mismatch`
  - Expected classification: `bug`
  - Expected starting agent: `troubleshooter`
  - Pass criteria: troubleshooter traces the ABI issue to mismatched header/library versions in the stamp-file chain

---

## 3. Testing Workflows

### 3.1 Running Specific Tests

- [ ] **W-T1**: Run a specific test suite
  - Prompt: `Run the hipMemcpy test suite and report which tests pass`
  - Expected classification: `script` (after Step 5b override if PM says bug)
  - Expected starting agent: `tester`
  - Pass criteria: PM routes to tester, Step 5b/6 do not override, tester probes environment first
  - Permission check: tester uses `printenv`, `test -f`, inline LD_LIBRARY_PATH

- [ ] **W-T2**: Run a specific test category
  - Prompt: `Run all tests in the memory/ category on gfx1030`
  - Expected classification: `script`
  - Expected starting agent: `tester`
  - Pass criteria: tester discovers test binaries under memory/, runs each with explicit LD_LIBRARY_PATH

- [ ] **W-T3**: Verify specific test passes
  - Prompt: `Verify that hipStreamCreate tests pass on gfx1030`
  - Expected classification: `script`
  - Expected starting agent: `tester`
  - Pass criteria: tester runs targeted tests, reports pass/fail with evidence

- [ ] **W-T4**: Run with specific configuration
  - Prompt: `Run hipMemcpyPeer tests excluding multigpu-tagged tests`
  - Expected classification: `script`
  - Expected starting agent: `tester`
  - Pass criteria: tester lists specific test names (NOT `~[multigpu]` tag filter)
  - Permission check: no Catch2 `~[tag]` syntax

### 3.2 Debugging Test Failures

- [ ] **W-T5**: Test failure with specific error
  - Prompt: `hipMallocManaged test fails with hipErrorNotSupported on gfx1030`
  - Expected classification: `bug`
  - Expected starting agent: `troubleshooter`
  - Pass criteria: troubleshooter investigates managed memory support on gfx1030, checks GPU capabilities

- [ ] **W-T6**: Flaky test investigation
  - Prompt: `hipStreamSynchronize test passes 9/10 times but occasionally times out`
  - Expected classification: `bug`
  - Expected starting agent: `troubleshooter`
  - Pass criteria: troubleshooter investigates race conditions, timing dependencies, GPU clock behavior

- [ ] **W-T7**: Segfault in test
  - Prompt: `hipMemcpy test segfaults at line 142 of hipMemcpy.cc`
  - Expected classification: `bug`
  - Expected starting agent: `troubleshooter`
  - Pass criteria: troubleshooter examines the code at line 142, checks for null pointer dereference, buffer overrun, use-after-free

### 3.3 Adding New Tests

- [ ] **W-T8**: Add positive test cases
  - Prompt: `Add positive test cases for hipMemcpyPeerAsync with different stream types`
  - Expected classification: `design`
  - Expected starting agent: `hip-expert`
  - Pass criteria: full design pipeline; implementer writes Catch2 GENERATE() tests with stream type parameterization

- [ ] **W-T9**: Add negative parameter tests
  - Prompt: `Add negative parameter validation tests for hipStreamCreateWithPriority`
  - Expected classification: `design`
  - Expected starting agent: `hip-expert`
  - Pass criteria: hip-expert identifies error codes per HIP spec; implementer adds SECTION blocks for each error case; includes `(void)hipGetLastError()` drain

- [ ] **W-T10**: Add test to YAML registry
  - Prompt: `Register new hipMemcpyPeer tests in the memory.yaml test registry`
  - Expected classification: `design` (modifies files) or `script`
  - Expected starting agent: `hip-expert` or `bash-expert`
  - Pass criteria: agent locates memory.yaml, adds entries with correct tags (no multigpu tag for single-GPU tests)

---

## 4. Git & Review

### 4.1 Branch Management

- [ ] **W-G1**: Design task creates branch immediately
  - Prompt: `Add NULL parameter check to hipStreamCreate`
  - Expected: `branch_action: "create-new"`, branch created at Step 4 (not deferred)
  - Pass criteria: git-agent dispatched during initialization

- [ ] **W-G2**: Bug task defers branch creation
  - Prompt: `hipEventElapsedTime returns negative values`
  - Expected: `branch_action: "create-new"`, branch NOT created at Step 4
  - Pass criteria: branch_created=false after Step 4; branch only created at first commit

- [ ] **W-G3**: Knowledge task — no branch
  - Prompt: `Explain hipMalloc vs hipMallocManaged`
  - Expected: `branch_action: "use-existing"`, `branch_name: ""`
  - Pass criteria: no git-agent dispatched for branch, no branch created

- [ ] **W-G4**: Bug investigation concluding "not a bug" — no branch wasted
  - Prompt: `hipEventElapsedTime returns negative values between events on different streams`
  - Expected: bug → troubleshooter → analysis concludes "expected behavior per CUDA spec" → completion
  - Pass criteria: no branch created because no commit ever happened

### 4.2 Commit Workflows

- [ ] **W-G5**: Post-commit sequence fires automatically
  - Prompt: Any design task that reaches the commit step
  - Expected: after commit → build-expert → tester (mandatory, PM not consulted)
  - Pass criteria: session dispatches build-expert and tester without asking PM between commit and tester

- [ ] **W-G6**: Deferred branch created at commit time
  - Prompt: Bug task where troubleshooter finds a real bug → planner → implementer → commit
  - Expected: branch_created=false after Step 4; at commit time, git-agent creates branch THEN commits
  - Pass criteria: branch exists after commit; only one branch created (not during init)

- [ ] **W-G7**: Commit with correct message format
  - Prompt: Any implementation task
  - Expected: PM returns `type: "commit"` with structured message (feat/fix prefix, Changes: bullets)
  - Pass criteria: git-agent receives well-formed commit message

- [ ] **W-G7a**: Claude signature appended to commit messages and PR body
  - Prompt: Any implementation task that reaches commit + push + PR creation
  - Expected: session augments PM's commit message with `🤖 Claude Code 🤖`
    before dispatching git-agent; PR body compose step appends the same
    signature after Environment/Known Issues sections
  - Pass criteria:
    - `git log -1 --format=%B <commit>` ends with `🤖 Claude Code 🤖`
    - The created PR body ends with `🤖 Claude Code 🤖` on its own line
    - Idempotence: if PM's message/body already contains the signature,
      it appears exactly once (no duplicates)

### 4.3 Code Review Cycles

- [ ] **W-G8**: Reviewer pass → completion
  - Prompt: Design task where implementation is correct
  - Expected: reviewer verdict `pass` → PM returns `completion` → verification gate passes
  - Pass criteria: verification gate checks builds/, tests/, reviews/ artifacts before completing

- [ ] **W-G9**: Reviewer partial → implementer fix
  - Prompt: Design task where reviewer finds code quality issues (not spec issues)
  - Expected: reviewer verdict `partial` → PM routes back to implementer with iteration_change: "minor"
  - Pass criteria: implementer gets reviewer feedback, makes fixes, re-commits, re-builds, re-tests

- [ ] **W-G10**: Reviewer fail-spec → planner rethink
  - Prompt: Design task where implementation doesn't match requirements
  - Expected: reviewer verdict `fail-spec` → PM routes back to planner with iteration_change: "minor"
  - Pass criteria: planner revises plan based on reviewer feedback

- [ ] **W-G11**: Reviewer fail → hip-expert rethink (major iteration)
  - Prompt: Design task with fundamental approach problems
  - Expected: reviewer verdict `fail` → PM routes to hip-expert with iteration_change: "major"
  - Pass criteria: major version increments (1.x → 2.0), hip-expert re-analyzes from scratch

- [ ] **W-G12**: 3-cycle hard cap → escalation
  - Prompt: Design task that keeps failing review
  - Expected: after 3 major cycles, PM returns `escalation` instead of retrying
  - Pass criteria: user presented with status and options (continue/change direction/stop)

---

## 5. Edge Cases

### 5.1 Classification & Routing

- [ ] **W-E1**: PM misclassifies code change as knowledge → Step 5 overrides
  - Prompt: `Add a comment documenting hipStreamCreate parameters`
  - Expected: PM may return `knowledge`; Step 5 overrides to `design` (modifies files)
  - Pass criteria: classification is `design` after override

- [ ] **W-E2**: PM classifies test run as bug → Step 5b overrides
  - Prompt: `Run the hipMemcpy tests and tell me which pass`
  - Expected: PM may return `bug` with `tester`; Step 5b overrides classification to `script`
  - Pass criteria: classification is `script`, starting_agent is `tester` after override

- [ ] **W-E3**: PM routes design to planner → Step 6 overrides
  - Prompt: `Implement a simple helper function for hipStream validation`
  - Expected: PM may return `planner`; Step 6 overrides to `hip-expert`
  - Pass criteria: starting_agent is `hip-expert` after override

- [ ] **W-E4**: PM modifies workspace path → Step 7 overrides
  - Prompt: Any task with explicit workspace `/home/user/workspace`
  - Expected: PM may return workspace with `/therock` appended; Step 7 uses session's value
  - Pass criteria: workspace used by session matches Step 1's gathered value

- [ ] **W-E5**: PM returns non-normalized agent name
  - Prompt: Any task
  - Expected: PM returns `"HIP Expert"` or `"Bash Expert"` (capitalized, spaces)
  - Pass criteria: normalization step converts to `hip-expert`, `bash-expert`

- [ ] **W-E6**: PM returns extra JSON fields
  - Prompt: Any task
  - Expected: PM includes `reason`, `rationale`, `expected_pipeline`, etc.
  - Pass criteria: normalization step strips extra fields, only uses defined schema fields

### 5.2 Incomplete or Conflicting Specifications

- [ ] **W-E7**: Ambiguous task — PM should route normally, specialist should escalate
  - Prompt: `Fix the performance issue`
  - Expected: PM classifies as `bug`, routes to troubleshooter
  - Pass criteria: troubleshooter notes insufficient information, states need for escalation in output; PM returns `escalation` asking user for specifics

- [ ] **W-E8**: Task outside ROCm domain
  - Prompt: `Write a React component for the test dashboard`
  - Expected: PM classifies — likely `script` or `design`
  - Pass criteria: hip-expert or bash-expert notes this is outside ROCm/HIP domain; PM escalates

- [ ] **W-E9**: Contradictory requirements
  - Prompt: `Make hipMalloc both thread-safe and lock-free`
  - Expected: PM classifies as `design`
  - Pass criteria: hip-expert identifies the contradiction and explains trade-offs; PM escalates for clarification

### 5.3 Build/Test Environment Issues

- [ ] **W-E10**: No GPU available → cannot-test protocol
  - Prompt: Any design task, but `/dev/kfd` does not exist
  - Expected: tester probes environment, reports `cannot-test`
  - Pass criteria: tester reports specific reason ("No GPU device at /dev/kfd"), lists what CAN be verified (compilation, code logic), reviewer acknowledges gap

- [ ] **W-E11**: Missing ROCm runtime libraries
  - Prompt: Any task requiring test execution, but libamdhip64.so not found
  - Expected: tester's `ldd` check catches missing library
  - Pass criteria: tester reports `cannot-test` with specific missing library, PM escalates

- [ ] **W-E12**: Build directory doesn't exist yet
  - Prompt: `Run the hip memory tests` in a workspace with no build/ directory
  - Expected: tester discovers no build directory
  - Pass criteria: tester states need for build-expert in output; PM routes to build-expert via fulfill-request

- [ ] **W-E13**: Stale build — source changed but not rebuilt
  - Prompt: Test execution task after source modifications
  - Expected: tester or build-expert detects mismatch
  - Pass criteria: build-expert dispatched to rebuild before testing

- [ ] **W-E13b**: Hardware-bound investigation → handoff plan offered
  - Prompt: Bug investigation for a failure reported on a GPU arch the local system doesn't have (e.g. "reproduce ROCM-XXXXX failures reported on MI210" when local GPU is gfx1030)
  - Expected: troubleshooter cannot reproduce locally and emits `## Hardware Constraint` section in its output. PM returns `escalation`. Session detects the section and ensures the user's options include "Produce a runnable handoff plan I can execute on the remote hardware" (injecting it if PM omitted it).
  - Pass criteria:
    - Session presents the handoff option to the user without re-dispatching PM
    - If user picks the handoff option, bash-expert is dispatched directly (NOT routed through PM)
    - bash-expert output is saved to `<thinking_dir>/scripts/<iter>-bash-expert-handoff.md`
    - Saved plan contains: target environment, setup checks, reproduction commands using compute-utils runners, diagnostic captures, what-to-send-back checklist
    - troubleshooter report `cannot-test`-style verdicts are NOT used (this is investigation outcome, not post-impl test)

### 5.4 Agent Handoff and Pipeline Control

- [ ] **W-E14**: Cross-agent request — hip-expert needs tester
  - Prompt: Design task where hip-expert says "I need the Tester to run baseline tests before I can finalize"
  - Expected: PM returns `fulfill-request` with target=tester, then_resume=hip-expert
  - Pass criteria: tester dispatched, results saved, hip-expert re-dispatched with results file path

- [ ] **W-E15**: Agent failure — first failure retries
  - Prompt: Any task where the dispatched agent errors out
  - Expected: session retries once with the same prompt
  - Pass criteria: agent dispatched a second time; if it succeeds, pipeline continues normally

- [ ] **W-E16**: Agent failure — second failure on critical agent escalates
  - Prompt: Any task where hip-expert fails twice
  - Expected: PM returns `escalation` (hip-expert is critical)
  - Pass criteria: user sees the error and is asked how to proceed

- [ ] **W-E17**: Agent failure — second failure on non-critical agent skips
  - Prompt: Any task where note-taker fails twice
  - Expected: PM returns `next-step` skipping the agent, noting the gap
  - Pass criteria: pipeline continues without the agent's output, gap noted in context

- [ ] **W-E18**: Git Agent failure — immediate stop
  - Prompt: Any commit that fails due to git conflict
  - Expected: session stops immediately, presents error to user
  - Pass criteria: no retry, no PM consultation — user sees the git error directly

- [ ] **W-E19**: Reviewer gating check — missing build artifact
  - Prompt: Design task where PM routes to reviewer but no build results exist
  - Expected: session's reviewer gating check catches missing build
  - Pass criteria: build-expert dispatched before reviewer; reviewer only runs after build+test artifacts exist

- [ ] **W-E19b**: Reviewer gating check — shell script exception
  - Prompt: Script task where committed files are all shell scripts, Build Status is BUILT (from post-commit step 4)
  - Expected: reviewer gating waives the builds/ file check since non-compiled files don't produce build artifacts
  - Pass criteria: reviewer dispatched without a build results file; test results file still required

- [ ] **W-E19c**: Review scope selection — use-existing branch with pre-existing commits
  - Prompt: Script task on an existing branch that already has commits from a prior pipeline run
  - Expected: Phase 3 Step 2-scope presents scope options ("This task's changes" vs "All branch changes") before dispatching Git Agent for soft-reset. Git Agent receives explicit review_base.
  - Pass criteria: (1) session records pipeline_start_commit in Phase 1, (2) scope question is presented when branch_action is use-existing, (3) Git Agent soft-resets to the user's chosen base (pipeline_start_commit for task-scope, branch fork point for all-branch), (4) snapshot still records ALL commits for restore regardless of scope

- [ ] **W-E19d**: Review scope selection — create-new branch (no scope question)
  - Prompt: Design task that creates a new branch
  - Expected: Phase 3 Step 2 does NOT ask scope question — all commits are from this run. Proceeds directly to soft-reset with branch fork point as base.
  - Pass criteria: no scope question asked; review stages all commits

- [ ] **W-E19e**: Post-commit non-compiled path — skips build-expert
  - Prompt: Script task that commits only shell scripts and Dockerfiles
  - Expected: Post-commit sequence classifies files as non-compiled, follows NON-COMPILED PATH (sets Build Status BUILT, dispatches tester directly, then reviewer on pass). Build-expert is NOT dispatched.
  - Pass criteria: no build-expert dispatch in agent activity log; Build Status is BUILT (not BUILD DEFERRED); tester and reviewer both dispatched

- [ ] **W-E19f**: Review feedback routes through pipeline (no direct edits)
  - Prompt: Any task where user provides feedback during Phase 3 Step 2 review (e.g., "move this to a shared function")
  - Expected: Session does NOT make direct edits. Feedback is sent to PM as a new task, Phase 2 re-entered, implementer makes changes, full post-commit sequence runs again.
  - Pass criteria: no session-level Edit/Write tool calls between user feedback and Phase 2 re-entry; implementer is dispatched for the change

- [ ] **W-E19g**: Branch base confirmation — compute-utils defaults to amd/dev/lrt
  - Prompt: Script task in compute-utils workspace
  - Expected: Session presents "Base branch: `amd/dev/lrt` (default for compute-utils). Use this, or specify a different base?" before dispatching Git Agent. Git Agent dispatch includes "Base the branch on origin/amd/dev/lrt".
  - Pass criteria: user prompted with correct default; Git Agent creates branch from amd/dev/lrt

- [ ] **W-E19h**: Branch base override — user specifies release branch
  - Prompt: Script task where user responds to base branch prompt with "release/therock-7.12"
  - Expected: Session stores `release/therock-7.12` as branch_base. Git Agent dispatch includes "Base the branch on origin/release/therock-7.12". PR creation uses `--base release/therock-7.12`.
  - Pass criteria: override is respected in both branch creation and PR targeting

- [ ] **W-E19i**: PR targets correct base branch and has quality content
  - Prompt: Any completed task going through Phase 3 Step 3
  - Expected: PR created with `--base <branch_base>`, title reflects high-level goal (not commit message), test plan items pre-checked for pipeline-verified items, verification section present
  - Pass criteria: gh pr create includes --base flag; PR body has [x] checked items; verification section references test results

- [ ] **W-E20**: Phase 2.5 entry — wider suite proposed, targeted passed
  - Setup: Tester report has `### Wider Suite Proposal` with at least one suite; Build Status is BUILT; Test Status is TESTED (targeted-pass)
  - Expected: Phase 3 Step 0.5 enters Phase 2.5 — dispatches expert sanity-check (HIP or Bash by file extension), then computes final suite list (subtracting PR-modified test files), then dispatches tester with `MODE: wider-execution` and sub-step `<major>.<minor>-tester-wider`
  - Pass criteria: expert sanity-check dispatched first; tester dispatched in wider-execution mode; suite list excludes PR-modified test files

- [ ] **W-E20b**: Phase 2.5 re-entry guard — skip if already executed in this major iteration
  - Setup: Wider suite already executed once this major iteration (Test Status updated to wider-pass | regression | pre-existing-flagged | cannot-classify); Phase 3 re-entered (e.g., reviewer pass after fixup)
  - Expected: Phase 3 Step 0.5 detects the existing wider-suite outcome and skips Phase 2.5
  - Pass criteria: no second wider tester dispatch; pipeline proceeds directly to Phase 3 user presentation

- [ ] **W-E20c**: Phase 2.5 triage — regression classification
  - Setup: Wider tester returns failing tests; per-test triage loop runs (stash source → rebuild → triage rerun N=3 → restore → rebuild back → classify); test passes 3/3 without source changes
  - Expected: Test classified as `regression-candidate`; Test Status set to `TESTED (regression)`; troubleshooter dispatched same iteration with sub-step `<major>.<minor>-troubleshooter`
  - Pass criteria: git-agent stash/restore both invoked; build-expert invoked twice (rebuild + cleanup rebuild); troubleshooter dispatched in same major iteration

- [ ] **W-E20k**: Phase 2.5 regression path → Phase 2 re-entry includes troubleshooter output in PM dispatch
  - Setup: Phase 2.5 triage classifies a wider-suite test as `regression-candidate` and Step 7a dispatches the troubleshooter, which writes its output to `<thinking_dir>/investigations/<major>.<minor>-troubleshooter.md`. Status.md now has `Test Status: TESTED (regression)`, `Build Status: NOT BUILT`. Session re-enters Phase 2.
  - Expected: The Regression re-entry invariant in Phase 2 fires. The session reads the most recent file from `<thinking_dir>/investigations/`, skips LOOP step 1 (no agent dispatch), and enters the LOOP at step 3 with the troubleshooter output as agent_output sent to PM. Major iteration is NOT incremented. PM routes to planner or implementer.
  - Pass criteria: PM dispatch on re-entry includes the troubleshooter output as agent_output (not omitted, not replaced with a generic "regression detected" string); no specialist dispatch occurs between Phase 2.5 Step 7a and the PM dispatch; iteration counters carry forward unchanged.

- [ ] **W-E20d**: Phase 2.5 triage — pre-existing classification
  - Setup: Wider tester returns failing test; triage rerun shows test fails 3/3 without source changes
  - Expected: Test classified as `pre-existing-candidate`; logged to `pre-existing-failures.md` with classification PRE-EXISTING and to status.md Pre-existing Failures section; Test Status set to `TESTED (pre-existing-flagged)`; pipeline continues to Phase 3
  - Pass criteria: pre-existing-failures.md row written by note-taker; status.md Pre-existing Failures section updated; no troubleshooter dispatch; pipeline proceeds

- [ ] **W-E20e**: Phase 2.5 triage budget — over budget marks UNTRIAGED-CANNOT-CLASSIFY
  - Setup: Wider tester returns more failures than the per-iteration triage budget (>2)
  - Expected: Session skips triage for the over-budget tests; logs them as UNTRIAGED-CANNOT-CLASSIFY in pre-existing-failures.md and status.md; Test Status set to `TESTED (cannot-classify)`
  - Pass criteria: no triage dispatches for over-budget tests; correct classification recorded; pipeline proceeds without troubleshooter

- [ ] **W-E20f**: Phase 3 Step 3a.5 — entry skipped when triage file absent or empty
  - Setup: Pipeline completes Phase 2.5 with NO pre-existing failures (or skipped Phase 2.5 entirely); `<thinking_dir>/pre-existing-failures.md` does not exist or has zero data rows
  - Expected: Step 3a.5 short-circuits — no `gh issue list` calls, no AskUserQuestion prompts; `<known_issues_section>` set to empty string; PR body equals raw PM body unchanged
  - Pass criteria: no gh CLI calls for issue search/create; no Known Issues heading appears in final PR body

- [ ] **W-E20g**: Phase 3 Step 3a.5 — Live mode + create new issue
  - Setup: pre-existing-failures.md has 1 PRE-EXISTING failure with full Reproduction Context; user picks "Create issues live" then "Create new" for the failure
  - Expected: Session runs `gh issue list --search "<test> <suite> flaky OR failing"`, then runs `gh issue create` with title `[PRE-EXISTING] <test> failing in <suite>` and body containing Reproduction (workspace HEAD, base HEAD, GPU arch, project, submodule status, test command pattern), Investigation Hints, and Cross-references sections; created issue URL appears in PR body's `### New issues filed` table
  - Pass criteria: gh issue create called with correct title and body containing all required sections; PR body has Known Issues section with new-issues table row; no draft section emitted

- [ ] **W-E20h**: Phase 3 Step 3a.5 — Draft mode emits suggested-issues block
  - Setup: pre-existing-failures.md has 1 CANNOT-CLASSIFY failure; user picks "Draft only (manual)" then "Create new" for the failure
  - Expected: Session does NOT call `gh issue create`; final PR body Known Issues section contains a `### Suggested issues (please file manually)` subsection with a `<details>` block containing the rendered title and body
  - Pass criteria: zero `gh issue create` calls; PR body contains `<details><summary>CANNOT-CLASSIFY: ...` and full body in fenced block; user can copy-paste

- [ ] **W-E20i**: Phase 3 Step 3a.5 — Link to existing issue
  - Setup: pre-existing-failures.md has 1 PRE-EXISTING failure; `gh issue list` returns issue #4242; user picks "Link to existing #4242"
  - Expected: No issue created (live mode) or drafted (draft mode); PR body Known Issues section contains `### Linked to existing issues` table with row referencing #4242
  - Pass criteria: no `gh issue create` call; no draft block; linked-issues table row present with correct issue number

- [ ] **W-E20j**: Phase 3 Step 3a.5 — Mixed categories use batched per-category prompts + duplicate-heading strip
  - Setup: pre-existing-failures.md has 2 PRE-EXISTING and 1 UNTRIAGED-CANNOT-CLASSIFY failures; PM returned a body that erroneously contains its own `## Known Issues` heading
  - Expected: Two AskUserQuestion calls (one per non-empty group, multiSelect: true); session strips PM's `## Known Issues` heading and content (up to next `## ` heading) from body before appending session-composed Known Issues section; final PR body contains exactly ONE `## Known Issues Surfaced During This PR` heading
  - Pass criteria: exactly two AskUserQuestion dispatches in step 3a.5; PM's spurious heading removed; final body has single Known Issues section

- [ ] **W-E22**: Phase 3 Step 3a + 3b + body composition — hardware-tested case appends Environment section
  - Setup: hardware_tested=yes, gpu_arch=gfx1100, targeted_arch_used=gfx1100, targeted_summary="15/15 passed on gfx1100", no Phase 2.5 wider run
  - Expected: 3a captures all environment + suite_execution facts; PM 3b prompt receives both blocks; PM body has hardware-test items pre-checked `[x]`; session appends `## Environment` section with GPU arch, project, "Tested on real hardware: yes (arch: gfx1100)" line; final body has exactly ONE `## Environment` heading
  - Pass criteria: PM prompt contains Environment + Suite execution sections; final body's hardware-test checkboxes are `[x]`; final body contains the appended Environment section; no Known Issues section

- [ ] **W-E22b**: Phase 3 — cannot-test case omits Environment section, leaves hardware boxes unchecked
  - Setup: hardware_tested=cannot-test, targeted_summary="cannot-test: no GPU detected", AMD_GPU_ARCH unset (resolves to "n/a")
  - Expected: PM 3b prompt receives `Hardware tested: cannot-test`; PM body has hardware-test items unchecked `[ ]` and Verification text explicitly states hardware testing did not occur; session does NOT append `## Environment` section
  - Pass criteria: final body's hardware-test checkboxes are `[ ]`; no `## Environment` heading anywhere in final body; Verification mentions hardware testing was not performed

- [ ] **W-E22c**: Phase 3 body composition — strip duplicate Environment heading from PM body
  - Setup: hardware_tested=yes; PM returned body containing a spurious `## Environment\nfoo bar\n## Verification\n...verification stuff...`
  - Expected: Session strips PM's `## Environment` section (heading through next `## ` or EOS) before appending session-composed Environment section; `## Verification` content is preserved
  - Pass criteria: final body contains exactly ONE `## Environment` heading; Verification section content survives the strip

- [ ] **W-E22d**: Phase 3 body composition — both Environment and Known Issues append in correct order
  - Setup: hardware_tested=yes AND pre-existing-failures.md has 1 PRE-EXISTING failure that user marks as "Link to existing #4242"
  - Expected: Final body order is PM body → `## Environment` → `## Known Issues Surfaced During This PR`; each section appears exactly once
  - Pass criteria: scanning the final body, the `## Environment` heading occurs after the last PM-body `## ` heading and before `## Known Issues Surfaced During This PR`; both sections present exactly once

- [ ] **W-E22e**: Phase 3 — wider_ran=no leaves wider-suite Test plan items unchecked
  - Setup: wider_ran=no (no Phase 2.5 wider tester report exists), hardware_tested=yes, targeted_summary="15/15 passed on gfx1100"; PM body Test plan includes a wider-suite verification item
  - Expected: PM body's wider-suite Test plan items are unchecked `[ ]`; hardware-test items are `[x]`; Environment section appended
  - Pass criteria: final body's wider-suite checkboxes are `[ ]`; final body's hardware-test checkboxes are `[x]`; Environment section present

- [ ] **W-E25**: PR-feedback task language does not bypass Phase 3 gates
  - Setup: `/workflow` invoked with a task description from `/pr-feedback` containing imperative verification language such as "After commit, push to the same PR branch (`users/foo/bar`) so the PR updates and CI re-runs." Pipeline reaches Phase 3 with `offer_review: true` and an existing PR.
  - Expected: Phase 3 Step 2 (review offer) and Step 3 (push confirmation) are BOTH presented to the user as AskUserQuestion prompts. Verification language in the task description is treated as a description of the verification plan, NOT as pre-authorization to skip gates. Banner is displayed before each gate.
  - Pass criteria: At least one AskUserQuestion call for the review offer; at least one AskUserQuestion call for the push confirmation; banner generation invoked before each. Zero direct `git push` calls before user approval.

- [ ] **W-E26**: Reviewer pass + minor polish suggestion → session does not edit source
  - Setup: Reviewer agent returns `pass` verdict but mentions a trivial cosmetic suggestion (e.g., "could switch `//!<` trailing markers to `//!` leading markers for consistency"). Reviewer's verdict is APPROVED.
  - Expected: Session does NOT invoke the Edit tool on any source file. The Reviewer output is sent to PM via LOOP step 3. PM either returns `completion` (treating the polish as optional) or routes to implementer for the polish change. The session never patches source files itself.
  - Pass criteria: Zero Edit/Write tool calls by the session against workspace source paths between Reviewer return and Phase 3 entry. PM is dispatched after Reviewer return.

- [ ] **W-E27**: Reviewer pass → session dispatches PM, not git-agent directly
  - Setup: Reviewer agent returns `pass`. Code changes have been committed by an earlier git-agent run as part of the iteration; the task involves an existing PR. The session has the option (incorrectly) to interpret "reviewer passed → next is push" and dispatch git-agent directly with both commit and push pre-authorized.
  - Expected: Session executes LOOP step 3 — sends Reviewer output to PM. PM returns `completion` (or escalation). Only after `completion` does the session enter Phase 3 and present the Step 2 review-offer gate, then the Step 3 push gate. Git-agent for push is dispatched only after the user approves Step 3.
  - Pass criteria: Trace shows PM dispatch immediately after Reviewer return; git-agent push dispatch (if any) occurs only after AskUserQuestion for Step 3 returned an affirmative answer. No "pre-authorized" language in the git-agent push prompt.

### 5.5 PR Feedback Skill

- [ ] **W-F1**: PR feedback expert assessment — correct classification
  - Setup: Dispatch hip-expert with 3 mock PR review comments: one bug (actionable), one praise (informational), one design question (discussion)
  - Expected: Expert classifies each correctly with reasoning and suggested fix for actionable items
  - Pass criteria: Bug comment → actionable with fix suggestion; praise → informational; design question → discussion

- [ ] **W-F2**: PR feedback → workflow transition
  - Setup: After expert assessment with actionable items, user says "yes" to addressing them
  - Expected: pr-feedback skill constructs task description from actionable items and invokes `/workflow` via Skill tool
  - Pass criteria: Task description includes file paths, line numbers, and fix summaries; workflow skill is invoked with the constructed prompt

- [ ] **W-F3**: PR feedback expert selection — bash-expert for shell scripts
  - Setup: PR comments on `.sh` files and Dockerfiles only
  - Expected: Session selects bash-expert instead of hip-expert for assessment
  - Pass criteria: bash-expert is dispatched (not hip-expert)

- [ ] **W-F4**: PR feedback — no comments found
  - Setup: PR with no review comments (both gh api calls return empty arrays)
  - Expected: Skill reports "No review comments found" and stops
  - Pass criteria: No expert dispatch; user sees informational message

- [ ] **W-F5**: PR feedback — pr-context.json written with correct structure
  - Setup: pr-feedback fetches 3 comments, expert classifies 2 as actionable and 1 as informational
  - Expected: `pr-context.json` written to thinking dir with owner, repo, pr_number, and comments array. Each comment has id, node_id, path, line, classification, and fix_summary (null for non-actionable)
  - Pass criteria: File is valid JSON; actionable comments have non-null fix_summary; informational comment has null fix_summary; all GitHub IDs are present

- [ ] **W-F6**: PR feedback — post-push comment replies and thread resolution
  - Setup: Workflow completes PR feedback task, pushes to existing PR branch, pr-context.json exists with 2 actionable comments
  - Expected: Phase 3 Step 3d replies to both actionable comments with commit hash and fix summary, resolves both threads via GraphQL, appends "Review feedback addressed" section to PR body
  - Pass criteria: Two `gh api` reply calls made (one per actionable comment); two GraphQL resolve mutations; PR body updated with feedback table; no pipeline failure if any API call errors

- [ ] **W-F7**: PR feedback — skipped for non-feedback workflows
  - Setup: Normal `/workflow` task (not from pr-feedback). Run two variants:
    (a) task description has no mention of `pr-context.json`.
    (b) task description mentions `pr-context.json` in prose (e.g.,
        "fix bug in the pr-context.json writer") but has NO `^PR_CONTEXT: `
        marker line.
  - Expected: In BOTH variants, Phase 3 Step 3d is skipped entirely. Prose
    mentions do not trigger engagement — only the line-anchored marker does.
  - Pass criteria: No gh api calls for comment replies; no GraphQL calls; pipeline proceeds normally to Step 3e

- [ ] **W-F8**: PR feedback — existing PR detection
  - Setup: Workflow on a branch that already has an open PR
  - Expected: Phase 3 Step 3 asks "push to update PR #N?" instead of "push and create a PR?"
  - Pass criteria: Session detects existing PR via `gh pr view`; user prompt reflects "update" not "create"

- [ ] **W-F9**: PR feedback — verify mode partial-success drift detection
  - Setup: Prior `/pr-feedback` → `/workflow` round trip completed with `pr-feedback-outcome.json` showing 3 actionable comments where 2 succeeded and 1 had a thread-resolve failure (rate-limited). User invokes `/pr-feedback verify <pr_url>`.
  - Expected: Verify mode resolves the cached `pr-context.json`, queries live PR state read-only, presents a per-comment table marking the 1 unresolved thread as ❌, prints "Round trip: 3 actionable comments, 2 fully addressed, 1 with drift", and suggests re-running `/workflow` or fixing manually.
  - Pass criteria: zero mutating gh calls in the dispatch transcript (no `gh pr edit`, no `gh pr comment`, no GraphQL `mutation`); per-comment table renders correctly; drift summary line cites accurate counts; suggested next steps are presented when M > 0.

- [ ] **W-F11**: PR feedback — marker present and file exists triggers Step 3d engagement
  - Setup: Task description from `/pr-feedback` ending with `PR_CONTEXT: /abs/path/to/pr-context.json`; the file exists.
  - Expected: Phase 3 Step 3d parses the marker, validates the file via `test -f`, reads `pr-context.json`, and proceeds with the reply/resolve/PR-body-update sequence.
  - Pass criteria: Step 3d engages; gh api comment-reply calls fire for actionable comments; outcome file is written.

- [ ] **W-F12**: PR feedback — marker absent skips Step 3d (even with prose mention)
  - Setup: Task description includes the prose phrase "fix bug in the pr-context.json writer" but contains NO `^PR_CONTEXT: ` marker line.
  - Expected: Phase 3 Step 3d skips to Step 3e. Prose mention is ignored.
  - Pass criteria: Zero gh api comment calls; pipeline proceeds normally.

- [ ] **W-F13**: PR feedback — marker present but file missing skips Step 3d with warning
  - Setup: Task description has `PR_CONTEXT: /tmp/missing.json` but the file does not exist (e.g., it was deleted between pr-feedback running and workflow being invoked, or the user manually constructed the task description with a wrong path).
  - Expected: Phase 3 Step 3d logs a warning ("PR_CONTEXT marker present but file missing at /tmp/missing.json — skipping PR feedback handoff") and skips to Step 3e. Pipeline does NOT block.
  - Pass criteria: Warning logged to user; zero gh api comment calls; pipeline proceeds normally; no errors raised.

- [ ] **W-F10**: PR feedback — Step 3d outcome file written on partial failure
  - Setup: Phase 3 Step 3d runs with 2 actionable comments; the second comment's `resolveReviewThread` GraphQL call fails with a permissions error.
  - Expected: Both reply attempts complete (first succeeds, second succeeds); first thread resolves; second thread fails. Step 3d writes `pr-feedback-outcome.json` with both records — first showing all `true`, second showing `reply_posted: true, thread_resolved: false, thread_error: "<perm error>"`. Phase 3 Step 1 reads the file and prints the multi-line "PR feedback round trip — partial success" block citing comment 2's failure.
  - Pass criteria: outcome file exists at `<thinking_dir>/pr-feedback-outcome.json` with the documented schema; user-facing summary contains the failure block, not the success one-liner.

- [ ] **W-E20**: Verification gate — PM claims completion but artifacts missing
  - Prompt: Design task where PM returns `completion` but tests/ directory is empty
  - Expected: Phase 3 Step 0 verification fails
  - Pass criteria: session re-dispatches PM with "Verification gate failed. Missing: test results." — does NOT present completion to user

### 5.6 Permission Prompt Compliance

- [ ] **W-E21**: Tester uses no forbidden bash patterns
  - Prompt: Any test execution task
  - Expected: tester output contains zero instances of `echo "$VAR"`, `${PIPESTATUS}`, `[[ ]]`, `~[tag]`, `cd && git`, `$THEROCK_WORK_DIR`
  - Pass criteria: grep tester's bash commands for forbidden patterns — zero matches

- [ ] **W-E22**: Build-expert uses no forbidden bash patterns
  - Prompt: Any build task
  - Expected: build-expert output contains zero instances of `${AMD_GPU_ARCH}`, `echo "$VAR"`, brace expansion
  - Pass criteria: grep build-expert's bash commands for forbidden patterns — zero matches

- [ ] **W-E23**: Git-agent uses no forbidden bash patterns
  - Prompt: Any commit task
  - Expected: git-agent uses `git -C /path` (not `cd /path && git`), no `echo "$VAR"`
  - Pass criteria: all git commands use `-C` flag

- [ ] **W-E24**: PM makes zero tool calls during initial routing
  - Prompt: Any task with pre-provided environment info
  - Expected: PM responds with JSON only, tool_uses=0
  - Pass criteria: PM dispatch returns with 0 tool_uses in usage stats

### Section 5.1: rocm-systems Alignment (Phase 1.5 + per-agent re-verify)

- [ ] **W-A1**: Phase 1.5 detects TheRock workspace
  - Prompt (paper trace): SKILL.md Phase 1.5 Step 1.5.1 against a workspace containing `rocm-systems/.git`
  - Expected: `<is_therock_workspace>` = true; pre-flight runs Step 1.5.2
  - Pass criteria: state-transition table shows correct branch on detection

- [ ] **W-A2**: Phase 1.5 — TRIGGER_DID_NOT_FIRE path
  - Prompt (paper trace): rocm-systems on `develop`, TheRock on `main`
  - Expected: `<alignment_status>` = TRIGGER_DID_NOT_FIRE, proceed to Parsing PM Output
  - Pass criteria: no halt, no checkout, status.md records TRIGGER_DID_NOT_FIRE

- [ ] **W-A3**: Phase 1.5 — ATTACHED_AND_PROCEEDED path
  - Prompt (paper trace): rocm-systems detached at SHA = origin/develop tip; TheRock on `main`
  - Expected: session runs `git -C <workspace>/rocm-systems checkout develop`, `<alignment_status>` = ATTACHED_AND_PROCEEDED
  - Pass criteria: status.md records ATTACHED_AND_PROCEEDED, workflow proceeds

- [ ] **W-A4**: Phase 1.5 — DIVERGENCE_HALTED path
  - Prompt (paper trace): rocm-systems detached at pinned SHA, develop tip is 5 commits ahead; TheRock on `main`
  - Expected: divergence report presented to user, NO agent dispatched, workflow halts
  - Pass criteria: report includes (a)/(b)/(c) options, status.md records DIVERGENCE_HALTED

- [ ] **W-A5**: Phase 1.5 — release branch maps to release/therock-X.Y NOT develop
  - Prompt (paper trace): TheRock on `release/therock-7.0`
  - Expected: `<mapped_branch>` = `release/therock-7.0` (NOT `develop`)
  - Pass criteria: mapping table lookup produces release/therock-7.0; build/test/commit operate on the correct release line

- [ ] **W-A6**: Phase 1.5 — FORK_BRANCH_AMBIGUOUS path
  - Prompt (paper trace): TheRock on `users/<user>/topic-branch`
  - Expected: `<alignment_status>` = FORK_BRANCH_AMBIGUOUS, user prompted to choose mapping, NO agent dispatched
  - Pass criteria: candidate mapped branches listed; workflow halts

- [ ] **W-A7**: Phase 1.5 — READ_ONLY_PINNED enforcement
  - Prompt (paper trace): user chose option (b) at divergence prompt; later commit attempts to stage `rocm-systems/clr/foo.cpp`
  - Expected: post-commit pre-step blocks the commit with COMMIT BLOCKED message
  - Pass criteria: git-agent NOT dispatched; user surfaced (a)/(b) recovery options

- [ ] **W-A8**: build-expert re-verifies even when dispatch context says ATTACHED
  - Prompt (agent dispatch): build-expert dispatched with `ROCM-SYSTEMS ALIGNMENT CONTEXT` block claiming ATTACHED_AND_PROCEEDED, but actual rocm-systems state has drifted to detached at a different SHA since pre-flight
  - Expected: build-expert runs verification commands itself, observes drift, reports the new verdict, flags discrepancy with the dispatch context
  - Pass criteria: output's `ALIGNMENT_CHECK:` reflects re-verify result, not the stale context

- [ ] **W-A9**: git-agent re-verifies even when dispatch context says aligned
  - Prompt (agent dispatch): git-agent dispatched to commit; dispatch context claims TRIGGER_DID_NOT_FIRE; actual state has drifted to detached
  - Expected: git-agent runs verification, refuses commit, surfaces alignment check
  - Pass criteria: NO commit made; output's `ALIGNMENT_CHECK:` reflects observed state

- [ ] **W-A10**: Output validator catches missing ALIGNMENT_CHECK line
  - Prompt (paper trace): build-expert returns output starting with `BUILD_DECISION: BUILT` and no `ALIGNMENT_CHECK:` line
  - Expected: session detects missing line, re-dispatches with correction note (retry 1 of 2)
  - Pass criteria: validator state-transition produces re-dispatch, not silent acceptance

- [ ] **W-A11**: Output validator catches forbidden combo (DIVERGENCE_HALTED + BUILD_DECISION)
  - Prompt (paper trace): build-expert returns `ALIGNMENT_CHECK: DIVERGENCE_HALTED` followed by `BUILD_DECISION: BUILT`
  - Expected: session detects forbidden combo, re-dispatches with correction note
  - Pass criteria: workflow does not advance to PM with this output

- [ ] **W-A12**: Output validator halts after 3 misses
  - Prompt (paper trace): agent fails validation 3 times in a row
  - Expected: session halts workflow, surfaces violation to user
  - Pass criteria: retry_count cap = 2 enforced; user receives "definitional bug" message

- [ ] **W-A13**: troubleshooter records SHA in investigation context
  - Prompt (agent dispatch): troubleshooter investigates a bug in `rocm-systems/projects/clr/`
  - Expected: output includes `## rocm-systems Investigation Context` section with SHA, ref state, TheRock branch, mapped branch
  - Pass criteria: section present even when no divergence; investigation reproducibility preserved

- [ ] **W-A14**: implementer surfaces plan-vs-release conflict
  - Prompt (agent dispatch): implementer dispatched with plan that uses develop-only API; workspace on `release/therock-7.0`
  - Expected: implementer halts editing, outputs PLAN-VS-RELEASE CONFLICT block
  - Pass criteria: NO files written; PM re-routing requested

- [ ] **W-A15**: tester records SHA context in test report
  - Prompt (agent dispatch): tester runs HIP unit tests against rocm-systems
  - Expected: output's `### rocm-systems SHA Context` section populated with SHA, ref state, TheRock+mapped branch, verdict
  - Pass criteria: section present; test result is comparable to other runs at the same SHA

- [ ] **W-A16**: bash-expert release example in 7-step template
  - Prompt (paper trace): bash-expert specs a script for a `release/therock-7.0` workspace
  - Expected: spec's step-4 mapping resolves to `release/therock-7.0` not `develop`; outside-pipeline note included
  - Pass criteria: script's alignment check defaults are release-aware; user-runnable script does not silently corrupt release work

---

## Test Execution Priority

Run tests in this order to catch blocking issues early:

1. **PM routing tests** (W-E1 through W-E6, W-E24) — fast, PM-only dispatches
2. **Permission compliance** (W-E21 through W-E23) — single-hop specialist dispatches
3. **Core workflow happy paths** (W-C1, W-C5, W-T1, W-G1) — one per classification type
4. **Branch/commit logic** (W-G1 through W-G7) — verify deferred creation works
5. **Error handling** (W-E14 through W-E20) — requires simulated failures
6. **Full pipeline end-to-end** (W-C2, W-C7) — expensive, run last

## Appendix: Tested and Verified (from eval runs)

These test cases have already been verified during the 10-eval run and the subsequent verification tests:

| Test | Equivalent Eval | Status |
|------|----------------|--------|
| W-C1 | Eval 2 (hipStreamCreateWithPriority) | Verified |
| W-C2 | Eval 10 (hipMemcpyPeer single-GPU tests) | Verified |
| W-C4 | Eval 7 (thread-safe memory pool) | Verified |
| W-C5 | Eval 8 (hipEventElapsedTime) | Verified |
| W-C6 | Eval 3 (hipDeviceSynchronize hang) | Verified |
| W-T1 | Eval 5 (hipMemcpy suite) + verification T2.1 | Verified |
| W-G3 | Eval 1, 9 (knowledge queries) + verification T3.2 | Verified |
| W-E1 | Verification T5.1 | Verified |
| W-E2 | Verification T2.1/T2.2 + Step 5b fix | Verified |
| W-E4 | Verification T1.1/T1.2 | Verified |
| W-E24 | All PM dispatches — 0 tool_uses | Verified |
