# lrt-rocm Plugin Development

This is the source repository for the `lrt-rocm` Claude Code plugin — a multi-agent orchestration system for ROCm/HIP development. When working here, you are improving **the workflow itself**, not doing ROCm development. Do not invoke the `/workflow` skill; that skill is the product, not the tool.

## Development Setup

This repo is symlinked into Claude Code's plugin cache:

```
~/.claude/plugins/cache/lrt-marketplace/lrt-rocm/2.0.0 → /home/sruscica/lrt-rocm-workspace/
```

**Edits are immediately live.** There is no build, install, or deploy step. When you edit a file in this repo, the next agent dispatch or skill invocation uses the updated version. This means:
- You can iterate rapidly — edit an agent definition, dispatch it, observe behavior, adjust
- You can also break things instantly — a syntax error in SKILL.md affects the next `/workflow` invocation
- Always commit working states before experimental changes

The symlink was created manually. If it breaks (e.g., after a plugin reinstall), recreate it:
```bash
ln -sfn /home/sruscica/lrt-rocm-workspace ~/.claude/plugins/cache/lrt-marketplace/lrt-rocm/2.0.0
```

## Architecture

### The Core Problem

This system orchestrates multiple AI agents to perform complex ROCm development tasks. The fundamental tension is: **AI agents are probabilistic, but pipeline correctness requires deterministic guarantees.** Every design decision flows from managing this tension.

### Dispatch Loop (SKILL.md)

The `/workflow` skill (`skills/workflow/SKILL.md`) is the session-level dispatch loop. It holds the Agent tool — no sub-agent does. It follows a strict state machine:

```
Session (you, the dispatch loop — deterministic)
  |
  +-> PM Orchestrator (advisor — returns routing JSON, probabilistic)
  +-> Specialists (dispatched fresh each time, no memory of prior runs)
  +-> Note-taker (auto-dispatched, writes to thinking directory)
```

The session gathers environment info, dispatches PM for routing, normalizes PM output, dispatches specialists, manages state, and enforces invariants. The PM advises; the session decides.

### PM as Stateless Advisor

The PM Orchestrator (`agents/pm-orchestrator.md`) is a JSON-only advisor. It receives context (task description, agent output, status.md) and returns structured routing decisions. It has **no memory between invocations** — every dispatch is fresh. It sees only what's in the prompt.

Key implication: **the PM cannot reliably enforce complex conditional logic.** It reads instructions once, but "if X AND Y then Z instead of W" competes with simpler patterns. When the PM returns `completion` but Build Status is `BUILD DEFERRED`, it's not being defiant — it just weighted "reviewer passed → completion" higher than the conditional check.

### Session-Level Enforcement (The Reliable Pattern)

When something must always happen, put it in SKILL.md, not in PM instructions. The session is deterministic code that Claude follows step-by-step. This pattern is proven across multiple fixes:

| What | PM guidance | Session enforcement |
|------|------------|-------------------|
| Classification override | PM instructions say knowledge tasks that modify files should be design | Step 5 checks and overrides |
| Tester routing | PM instructions say test tasks should be script classification | Step 5b checks and overrides |
| Starting agent | PM instructions list which agents start which task types | Step 6 checks and overrides |
| Workspace path | PM instructions say use the provided path exactly | Step 7 always uses session's value |
| Build completion gate | PM instructions say check Build Status before completion | Phase 3 Step 0 checks Build Status and dispatches build-expert if not BUILT |

**The pattern: PM guides (best-effort), session enforces (guaranteed).** PM instructions still matter — they produce correct routing most of the time, reducing how often the session needs to override. But critical invariants must have session-level enforcement.

### Shared State (status.md)

Agents communicate through files in the thinking directory, never through conversation history. `status.md` is the primary shared state file. Key fields:
- `build_status` — `NOT BUILT`, `BUILT`, `BUILD DEFERRED`, `BUILD FAILED`
- Completed Stages, Current Stage, Blockers, Commits, Agent Activity Log

The session manages state transitions (writing to status.md via note-taker). The PM reads status.md to make routing decisions. This separation — **session writes, PM reads** — keeps state consistent.

### Build Status State Machine

```
                          ┌─────────────────────┐
                          │     NOT BUILT        │ ← initial state
                          │                      │ ← reset on reviewer rejection
                          └──────────┬───────────┘
                                     │ post-commit: build-expert runs
                          ┌──────────┴───────────┐
                     ┌────┤   BUILD_DECISION?     ├────┐
                     │    └──────────────────────-─┘    │
                     ▼                                  ▼
          ┌──────────────────┐               ┌─────────────────┐
          │  BUILD DEFERRED  │               │      BUILT      │ ← can complete
          │  (non-functional)│               │  (build passed) │
          └────────┬─────────┘               └─────────────────┘
                   │ reviewer passes,                  ▲
                   │ session dispatches                │
                   │ build-expert (actual build)       │
                   └──────────────────────────────────-┘
                                              ┌─────────────────┐
                                              │  BUILD FAILED   │
                                              │ → implementer   │
                                              └─────────────────┘
```

## File Reference

### Pipeline Core

| File | Role | Key details |
|------|------|-------------|
| `skills/workflow/SKILL.md` | Dispatch loop — the session follows this | ~510 lines. Phase 1 (init), normalization steps 1-7, Phase 2 (main loop), post-commit sequence, Phase 3 (completion). Most heavily modified file. |
| `agents/pm-orchestrator.md` | Routing advisor — returns JSON | Stateless. Classification table, orchestration logic steps 1-10, verification gate, output format rules. |
| `agents/DISPATCH-PROTOCOL.md` | Reference doc for all agents | Command rules (no `$VAR`, no `cd && git`, no brace expansion), cross-agent communication, thinking directory structure. Not an agent — included in dispatch prompts. |

### Specialist Agents

| File | Tools | Writes own output? | Notes |
|------|-------|-------------------|-------|
| `agents/hip-expert.md` | Read, Grep, Glob, WebFetch, WebSearch | No (note-taker) | Domain analysis. First agent for design/knowledge tasks. |
| `agents/troubleshooter.md` | Read, Grep, Glob, Bash, WebFetch, WebSearch | No (note-taker) | Bug investigation. First agent for bug tasks. |
| `agents/planner.md` | Read, Grep, Glob | No (note-taker) | Creates implementation plans from analysis. |
| `agents/implementer.md` | Read, Grep, Glob, Write, Edit, Bash | Yes | Executes plans. Writes code. |
| `agents/tester.md` | Read, Grep, Glob, Write, Edit, Bash | Yes | System environment authority. Probes GPU, runs tests. |
| `agents/build-expert.md` | Read, Grep, Glob, Bash | No (note-taker) | Diff analysis mode (post-commit) + actual builds. BUILD_DECISION output. |
| `agents/reviewer.md` | All tools | No (note-taker) | Two-pass review (spec compliance, code quality). Verdicts: pass/partial/fail-spec/fail. |
| `agents/bash-expert.md` | Read, Grep, Glob, Write, Edit, Bash | Yes | Script/automation tasks. Knows Bash tool vs .sh file distinction. |
| `agents/git-agent.md` | Read, Grep, Glob, Bash | No (note-taker) | Sole owner of git operations. Commit, branch, bisect, review flow. |
| `agents/note-taker.md` | Read, Write, Bash | Yes (that's its job) | Fast/lightweight. Writes agent output + status.md updates. Haiku model. |

### Supporting Files

| File | Purpose |
|------|---------|
| `tests/workflow-test-plan.md` | 66 test cases across 5 sections. Used for regression testing after changes. |
| `hooks/` | Session-start hooks, auto-update checks |
| `scripts/` | Helper scripts (rk.py for branch management, review.py for code review) |
| `templates/` | Workspace scaffolding (CLAUDE.md template, directory-map, etc.) |

## Making Changes

### Before You Change Anything

1. **Read the file you're changing.** Agent definitions and SKILL.md have accumulated specific fixes for specific failure modes. A line that looks unnecessary may be preventing a regression.
2. **Understand the scope.** Changes to SKILL.md affect every workflow invocation. Changes to an agent affect only that agent's behavior. Changes to PM orchestrator affect routing but are probabilistic.
3. **Check the test plan.** `tests/workflow-test-plan.md` has 66 test cases. If your change affects routing, classification, or pipeline flow, identify which tests cover it.

### How to Test Changes

**PM routing tests (fast, seconds each):**
Dispatch PM as a sub-agent with a mock prompt. Check the JSON output. These test classification, starting agent, and "what's next?" routing.

```
Agent(subagent_type: "pm-orchestrator", prompt: "ADVISOR MODE. ...")
```

**Specialist behavior tests (medium, 30-90s each):**
Dispatch a specialist agent with a mock task in a real workspace. Check its output for correct behavior, command compliance, and BUILD_DECISION.

**Session logic tests (analysis only):**
Some tests verify SKILL.md logic by reading the specification — e.g., "does the post-commit sequence reset Build Status on failure?" These don't need agent dispatches.

**Full pipeline tests (expensive, minutes):**
Run `/workflow` with a real task. Only do this for final validation, not iterative development.

### Commit Discipline

Every change to this repo should be committed before moving on. This repo tracks the workflow's evolution — uncommitted changes get lost across sessions. Use descriptive commit messages:
- `fix:` for correcting broken behavior
- `feat:` for new capabilities
- `docs:` for documentation-only changes

### Common Pitfalls

- **Don't add complex conditional logic to PM instructions expecting reliable execution.** If it must always work, add session-level enforcement in SKILL.md.
- **Don't remove "redundant" overrides.** Steps 5, 5b, 6, and 7 look like they duplicate PM instructions, but they exist because the PM doesn't follow those instructions reliably. The overrides are the actual mechanism; PM instructions are guidance.
- **Don't use `$VAR` expansion in agent definitions or dispatch templates.** Claude Code's AST parser flags these as security risks and prompts the user for approval. Use `printenv VAR`, `git -C /path`, and inline values instead. See DISPATCH-PROTOCOL.md for the full list.
- **Don't test with the same prompt twice expecting the same PM response.** The PM is non-deterministic. A prompt that returns `bug` once may return `design` next time. Test the session-level enforcement that handles both cases.

## Improvement Philosophy

### What Makes a Good Improvement

The best improvements to this workflow reduce the gap between what the PM advises and what the session needs. They fall into categories:

1. **State visibility** — Give the PM more explicit state to read (like Build Status in status.md). The PM makes better decisions when the relevant state is a labeled field rather than buried in prose.
2. **Session guardrails** — Add deterministic checks for invariants the PM sometimes violates. These are cheap (one `if` check) and eliminate entire classes of bugs.
3. **Agent instruction clarity** — Rewrite agent instructions to be more specific about what to do vs. what not to do. Agents follow clear, concrete rules better than vague guidelines.
4. **Pipeline simplification** — Remove unnecessary steps, combine redundant dispatches, eliminate agent hops that don't add value. Fewer steps = fewer places for things to go wrong.

### What to Avoid

- **Over-specifying PM behavior** — Adding more conditional branches to PM instructions has diminishing returns. After ~5 conditions, the PM stops reliably tracking them all.
- **Premature abstraction** — Don't create "reusable" patterns for things that happen once. The pipeline is already complex enough.
- **Optimizing for the happy path** — Most bugs are in edge cases (reviewer rejects, builds fail, agents time out). Test the unhappy paths.

### How to Evaluate Whether a Change Worked

Run the relevant test cases from `tests/workflow-test-plan.md`. For PM routing changes, run at least 3 dispatches with the same prompt to account for non-determinism. A change that passes 2/3 times is not reliable — add session-level enforcement.

## Known Issues and Improvement Areas

### Open Issues (from test plan execution)

| Issue | Priority | Description |
|-------|----------|-------------|
| PM routes `partial` to planner instead of implementer | Low | PM orchestrator spec says partial → implementer, but PM sends to planner. Extra hop is harmless. |
| PM uses `major` iteration for `fail-spec` | Low | Spec says minor. PM escalates. Cosmetic (numbering only). |
| PM tries to fix non-critical agent failure instead of skipping | Low | PM improvises a workaround instead of following skip rules. Arguably better. |

### Potential Improvement Areas

- **Test Status tracking** — Build Status works well. A similar `Test Status` field in status.md could give the PM better test-aware routing (NOT TESTED, TESTED (pass), TESTED (fail), CANNOT TEST).
- **PM context condensation** — As pipelines run longer, the PM prompt gets larger. A summary mechanism for earlier iterations could keep PM prompts focused.
- **Agent output structure enforcement** — Agents sometimes return free-form text instead of the structured sections their definitions specify. A validation step could catch this.
- **Iteration budget awareness** — The PM doesn't reliably track which major iteration it's on. Putting the iteration count prominently in status.md (like Build Status) could help.
