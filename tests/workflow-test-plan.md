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

- [ ] **W-E20**: Verification gate — PM claims completion but artifacts missing
  - Prompt: Design task where PM returns `completion` but tests/ directory is empty
  - Expected: Phase 3 Step 0 verification fails
  - Pass criteria: session re-dispatches PM with "Verification gate failed. Missing: test results." — does NOT present completion to user

### 5.5 Permission Prompt Compliance

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
