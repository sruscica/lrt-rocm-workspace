# Agent Dispatch Protocol

> **This is a reference document, not an agent definition.** The session includes relevant sections from this document when dispatching agents.

## How the Pipeline Works

The `/workflow` skill runs a dispatch loop in the session. The session holds the Agent tool — you do not.

```
Session (dispatch loop, holds Agent tool)
  |
  +-> PM Orchestrator (advisor, returns JSON routing)
  +-> Specialists (dispatched fresh, tool-restricted)
  +-> Note-taker (auto-dispatched for output saving)
```

**You are dispatched fresh each time.** You have no memory of prior invocations. All context comes from:
1. The prompt the session gives you (includes task summary, file pointers, iteration info)
2. Files on disk in the thinking directory that you read yourself

## When You Need Another Agent

You cannot dispatch agents. Instead, **state your need in your output**:

> I need the **Tester** to run baseline tests on the `memory/` test category before I can finalize this analysis. The relevant test binaries are at `$THEROCK_WORK_DIR/therock/build/core/hip-tests/build/catch_tests/unit/memory/`.

The session sends your output to the PM Orchestrator. The PM identifies the cross-agent need and returns routing instructions. The session dispatches the target agent with appropriate context.

**Be specific about what you need:**
- Which agent
- What task for that agent
- What files/paths are relevant
- What you need from the results to continue your work

**Do NOT:**
- Try to use an Agent tool (you don't have it)
- Write fake dispatch commands
- Assume the other agent has seen your earlier work (they haven't — fresh dispatch)

## Command Rules — Avoiding Permission Prompts

Claude Code has hardcoded security checks that prompt the user for approval on certain bash patterns. These checks **cannot be bypassed** by hooks or permission rules. All agents MUST use the alternative commands below.

**Variable expansion — NEVER use `echo` with `$VAR`:**

| Do NOT use | Use instead |
|-----------|-------------|
| `echo "$VAR"` | `printenv VAR` |
| `echo $VAR` | `printenv VAR` |
| `echo "${VAR:-default}"` | `printenv VAR 2>/dev/null \|\| echo "default"` |
| `echo "X=$VAR"` | `printenv VAR` |
| `echo "X=$VAR Y=$VAR2"` | `printenv VAR VAR2` |

**Compound cd+git — NEVER use `cd /path && git ...`:**

| Do NOT use | Use instead |
|-----------|-------------|
| `cd /path && git status` | `git -C /path status` |
| `cd /path && git branch` | `git -C /path branch --show-current` |
| `cd /path && git log` | `git -C /path log --oneline -5` |
| `cd /path && git rev-parse HEAD` | `git -C /path rev-parse --abbrev-ref HEAD` |
| `cd /path && git diff` | `git -C /path diff` |
| `cd /path && ls` | `ls /path` |

**Why:** Claude Code's AST parser flags `$VAR` expansion and `cd+git` compounds as security risks. `printenv` and `git -C` achieve the same result without triggering prompts.

## Resume Protocol

After your cross-agent need is fulfilled, the session may re-dispatch you fresh with:
- Your original task context
- A pointer to the results from the agent you requested
- Instructions to continue from where you left off

**How to continue after re-dispatch:**
- Read the results file referenced in your prompt
- If you have partial work on disk (e.g., Implementer with plan checkboxes), read it to find your place
- Produce your final output incorporating the new results

## Output Saving

Your output is saved to the thinking directory automatically:

| You have Write? | What happens |
|----------------|--------------|
| **Yes** (Implementer, Tester, Bash Expert) | Write your own output to the appropriate thinking subdirectory. The pipeline handles status.md updates. |
| **No** (all others) | The pipeline auto-dispatches the Note-taker to save your output. Structure your output clearly — what you return IS what gets saved. |

### Agents with Write tool
- Implementer → writes to `thinking/<topic>/` as needed
- Tester → writes to `thinking/<topic>/tests/` and test artifacts to `testing/<topic>/`. The Tester is the **system environment authority** — it probes GPU availability, ROCm runtime, library paths, and reports `cannot-test` when the environment doesn't support execution. Other agents should NOT set up LD_LIBRARY_PATH or check for GPU availability — that's the Tester's job.
- Bash Expert → writes to `thinking/<topic>/scripts/`

### Agents without Write tool
- HIP Expert → output saved to `analysis/<iteration>-hip-expert.md`
- Planner → output saved to `plans/<iteration>-planner.md`
- Reviewer → output saved to `reviews/<iteration>-reviewer.md`
- Troubleshooter → output saved to `investigations/<iteration>-troubleshooter.md`
- Build Expert → output saved to `builds/<iteration>-build-expert.md`
- Git Agent → output saved to `commits/<iteration>-git-agent.md`

## Context You Receive

Every dispatch includes:
- Workspace path
- Topic slug and thinking directory path
- Current iteration number (major.minor)
- Original user request (one-line summary)
- Task-specific context (files to read, what to do)

On re-dispatch after a cross-agent request:
- All of the above, plus
- Path to the results file from the requested agent
- Instruction to continue from where you left off

## TheRock Source Path → Build Component Mapping

When working in a TheRock workspace, use this mapping to identify which build component a source file belongs to:

| Source path pattern | Build target | ninja command |
|---------------------|-------------|---------------|
| `rocm-systems/projects/clr/*` or `core/clr/*` | HIP runtime | `ninja -C build hip-clr+build` |
| `rocm-systems/projects/hip-tests/*` | HIP test suite | `ninja -C build hip-tests+build` |
| `rocm-systems/projects/ocl-clr/*` | OpenCL runtime | `ninja -C build ocl-clr+build` |
| `compiler/*` | HIP compiler | `ninja -C build hipcc+build` |
| `base/rocr-runtime/*` | ROCr runtime | `ninja -C build rocr+build` |

## Thinking Directory Structure

```
<workspace>/thinking/YYYY-MM-DD-<topic-slug>/
├── status.md           # Pipeline state tracker
├── requests/           # Cross-agent request context files
├── analysis/           # HIP Expert output
├── plans/              # Planner output
├── tests/              # Tester output
├── reviews/            # Reviewer output
├── investigations/     # Troubleshooter output
├── builds/             # Build Expert output
├── commits/            # Git Agent output
├── scripts/            # Bash Expert output
└── pm-summaries/       # PM condensed summaries
```
