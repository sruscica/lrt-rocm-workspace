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

### Session as PM (SKILL.md)

The `/workflow` skill (`skills/workflow/SKILL.md`) is both the dispatch loop AND the project manager (PM). The session holds the Agent tool, makes routing decisions directly via a routing table, and tracks progress via Claude Code's `TaskCreate`/`TaskUpdate` tools. No sub-agent has the Agent tool.

```
Session (dispatch loop + PM — routes agents, tracks progress)
  |
  +-> PM Orchestrator (initial classification + PR content only — 2 dispatches total)
  +-> Specialists (dispatched fresh each time, no memory of prior runs)
  +-> Note-taker (auto-dispatched, writes to thinking directory)
```

The session evaluates agent output, applies a routing table to decide what's next, creates visible PM checkpoint tasks between agents, and enforces invariants. The PM Orchestrator sub-agent is only used twice: once for initial task classification (Phase 1) and once for PR body construction (Phase 3).

### Routing Table (Session-Level)

Inter-agent routing is deterministic. The session scans each agent's output for structured signals (verdicts, BUILD_DECISION lines, checkbox completion) and applies a 20-row routing table that maps `(previous_agent, output_signal) → (next_agent, iteration_change)`. This replaced the old model where a PM sub-agent was dispatched after every agent to decide what's next.

### PM Orchestrator — Scoped Down

The PM Orchestrator (`agents/pm-orchestrator.md`, ~136 lines) is a JSON-only advisor with exactly 2 response types:
- `initial-routing` — classifies the task, picks the starting agent and branch action
- `pr-content` — constructs PR title and body from pipeline results

It does NOT make inter-agent routing decisions. The session normalizes its output (Steps 1-7 in SKILL.md) and applies overrides for classification, starting agent, and workspace path.

### Progress Tracking

The session maintains a visible checklist using `TaskCreate`/`TaskUpdate`:
- Initial task list created after user confirms (Phase 1 Step 2)
- PM checkpoint tasks ("PM: Evaluate <agent> results") between agents
- Sub-tasks for complex agents (Reviewer: 4 sub-tasks, Implementer: per-plan-step, Tester: 3 sub-tasks)
- Iteration loop handling creates new tasks with "(iteration N)" suffix

### Shared State (status.md)

Agents communicate through files in the thinking directory, never through conversation history. `status.md` is the primary shared state file. Key fields:
- `Build Status` — `NOT BUILT`, `BUILT`, `BUILD DEFERRED`, `BUILD FAILED`
- `Test Status` — `NOT TESTED`, `TESTED (targeted-pass)`, `TESTED (wider-pass)`, `TESTED (regression)`, etc.
- Completed Stages, Current Stage, Blockers, Commits, Agent Activity Log

The session manages state transitions (writing to status.md via note-taker). Both Build Status and Test Status reset together on reviewer rejection.

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
| `skills/workflow/SKILL.md` | Dispatch loop + PM — the session follows this | ~1630 lines. Phase 1 (init), normalization steps 1-7, Phase 1.5 (rocm-systems alignment), Phase 2 (main loop with routing table), post-commit sequence, Phase 2.5 (wider suite), Phase 3 (completion). |
| `skills/workflow/phase-2.5-wider-suite.md` | Wider suite execution state machine | 8-step triage: sanity-check → execution → per-test stash/rebuild/rerun → classification. |
| `skills/workflow/pre-existing-failures-triage.md` | Pre-existing failures PR integration | GitHub issue search, user triage prompt, issue creation (live/draft). |
| `skills/workflow/pr-feedback-handoff.md` | PR review comment round-trip | Reply to actionable comments, resolve threads, update PR body. |
| `agents/pm-orchestrator.md` | Initial classification + PR content | ~136 lines. 2 JSON response types only: initial-routing, pr-content. |
| `agents/DISPATCH-PROTOCOL.md` | Reference doc for all agents | Command rules (no `$VAR`, no `cd && git`, no brace expansion), cross-agent communication, thinking directory structure. |

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

**PM classification tests (fast, seconds each):**
Dispatch PM as a sub-agent with a mock prompt. Check the JSON output for correct classification and starting agent. The PM is only used for initial routing now — inter-agent routing is session-side.

```
Agent(subagent_type: "pm-orchestrator", prompt: "ADVISOR MODE. ...")
```

**Specialist behavior tests (medium, 30-90s each):**
Dispatch a specialist agent with a mock task in a real workspace. Check its output for correct behavior, command compliance, and BUILD_DECISION.

**Session routing tests (analysis only):**
Verify SKILL.md routing table logic by reading the specification — e.g., "does reviewer pass route to completion?", "does build failure route to implementer with minor iteration?" These don't need agent dispatches.

**Full pipeline tests (expensive, minutes):**
Run `/workflow` with a real task. Only do this for final validation, not iterative development.

### Commit Discipline

Every change to this repo should be committed before moving on. This repo tracks the workflow's evolution — uncommitted changes get lost across sessions. Use descriptive commit messages:
- `fix:` for correcting broken behavior
- `feat:` for new capabilities
- `docs:` for documentation-only changes

### Common Pitfalls

- **Don't confuse "PM" (session role) with "PM Orchestrator" (sub-agent).** The session IS the PM for routing decisions. The PM Orchestrator sub-agent only handles initial classification and PR content.
- **Don't remove JSON normalization overrides (Steps 5, 5b, 6, 7).** These exist because the PM Orchestrator's initial classification is non-deterministic. The overrides are the actual mechanism; PM instructions are guidance.
- **Don't use `$VAR` expansion in agent definitions or dispatch templates.** Claude Code's AST parser flags these as security risks and prompts the user for approval. Use `printenv VAR`, `git -C /path`, and inline values instead. See DISPATCH-PROTOCOL.md for the full list.
- **Don't add routing logic outside the routing table.** The routing table in SKILL.md is the single source of truth for inter-agent routing. Adding ad-hoc "if agent X returns Y, then do Z" logic elsewhere creates divergence.
- **Don't forget progress tracking at dispatch points.** Sub-task creation for Reviewer, Implementer, and Tester is defined in the Progress Tracking section. Every dispatch of these agents must create the corresponding sub-tasks.

## Improvement Philosophy

### What Makes a Good Improvement

The best improvements to this workflow fall into categories:

1. **Routing table clarity** — The session routing table is the core decision engine. Additions or changes to routing should be explicit rows, not prose.
2. **Agent instruction clarity** — Rewrite agent instructions to be more specific about what to do vs. what not to do. Agents follow clear, concrete rules better than vague guidelines.
3. **Pipeline simplification** — Remove unnecessary steps, combine redundant dispatches, eliminate agent hops that don't add value. Fewer steps = fewer places for things to go wrong.
4. **Progress tracking fidelity** — Task creation and sub-tasks should match what the session actually dispatches. Gaps between the progress tracking section and the dispatch flow cause silent tracking failures.

### What to Avoid

- **Over-specifying PM behavior** — The PM is only used for initial classification now. It has ~136 lines of instructions. Adding more conditional branches has diminishing returns.
- **Premature abstraction** — Don't create "reusable" patterns for things that happen once. The pipeline is already complex enough.
- **Optimizing for the happy path** — Most bugs are in edge cases (reviewer rejects, builds fail, agents time out). Test the unhappy paths.
- **Inconsistent terminology** — After the PM merge refactor, "PM" means two things: the session's PM role (routing, checkpoints) and the PM Orchestrator sub-agent (classification, PR content). Be explicit about which one you mean.

### How to Evaluate Whether a Change Worked

Run the relevant test cases from `tests/workflow-test-plan.md`. For PM classification changes, run at least 3 dispatches with the same prompt to account for non-determinism. For routing table changes, trace the state machine on paper (the routing table is deterministic — if it's right in the spec, it's right in execution).

## Known Issues and Improvement Areas

### Open Issues

These are minor issues from the old PM routing model. With the session routing table, the PM's inter-agent routing behavior no longer matters — only its initial classification does.

| Issue | Priority | Description |
|-------|----------|-------------|
| PM initial classification non-determinism | Low | PM sometimes classifies the same task differently across runs. Session overrides (Steps 5, 5b, 6) catch the common misclassifications. |

### Potential Improvement Areas

- **Agent output structure enforcement** — Agents sometimes return free-form text instead of the structured sections their definitions specify. A validation step could catch this.
- **Progress tracking automation** — Sub-task completion for the implementer currently relies on the session parsing checkbox output. A more structured signal from the implementer would be more reliable.
