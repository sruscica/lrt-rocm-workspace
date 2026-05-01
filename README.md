# lrt-rocm

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) plugin for AMD's Runtime team. It encodes the team's development workflows, build knowledge, and engineering practices as reusable skills that Claude can invoke during coding sessions.

## Why this exists

Working on the ROCm stack (HIP, ROCr, OpenCL, TheRock) involves complex multi-step builds, specific contribution workflows, and institutional knowledge that's easy to forget or get wrong. Instead of keeping that knowledge in wikis that go stale, this plugin embeds it directly into the tool the team uses every day.

It also codifies general engineering discipline — TDD, structured debugging, code review rigor, verification before claiming success — so the AI assistant follows the same standards the team holds itself to.

## Claude Code installation for AMD users:
https://amd.atlassian.net/wiki/spaces/CLRT/pages/1451546255/Claude+Code+with+ROCm+Workspace

## Installation

```
/plugin marketplace add ethtrinh/lrt-rocm-workspace
/plugin install lrt-rocm@lrt-marketplace
/reload-plugins
```

Restart your Claude session if changes don't take effect.

## First-time setup

After installing, run the setup skill to configure your workspace:

```
/setup
```

This will:
- Find your TheRock and rocm-systems directories (or offer to clone them)
- Detect your GPU architecture
- Scaffold workspace files (CLAUDE.md, directory-map, task templates)
- Optionally configure VSCode MCP integration for code review

## Features

### Stop Notification

When Claude finishes responding, the Stop hook rings the terminal bell and sets the terminal title to "CLAUDE IS READY". This fires on every response via the harness-executed hook in `hooks/hooks.json`, which is deterministic — unlike LLM-instruction-based notifications that are unreliable during complex pipelines.

## Skills

### ROCm-specific

| Skill | Purpose |
|---|---|
| `setup` | First-time workspace setup and directory discovery |
| `hip-ocl-monorepo-build` | Build ROCr, HIP, and OpenCL from the rocm-systems monorepo |
| `regression-bisect-hip-ocl` | Git bisect for HIP/OCL test regressions |
| `the-rock` | Build HIP, and OpenCL from TheRock |

### Code review workflow

| Skill | Purpose |
|---|---|
| `stage-review` | Stage changes and open VSCode diffs for review |
| `process-review` | Find and address RVW review comments |
| `prep-pr` | Milestone review before PR |
| `vscode-diff` | Open git diffs in VSCode |
| `wip` | Quick WIP commit |
| `squash-prep` | Prepare commit stack for squash |
| `task` | Switch between active tasks |
| `vscode-mode` | Set VSCode integration mode (local/remote) |
| `nuke-vscode` | Kill stale VSCode remote server |

### Engineering workflow

| Skill | Purpose |
|---|---|
| `test-driven-development` | Write failing tests before implementation |
| `systematic-debugging` | Diagnose bugs methodically before fixing |
| `brainstorming` | Explore intent and requirements before building |
| `writing-plans` | Design implementation plans before coding |
| `executing-plans` | Execute plans step-by-step with checkpoints |
| `subagent-driven-development` | Parallelize independent tasks with subagents |
| `requesting-code-review` | Dispatch reviewer subagent |
| `receiving-code-review` | Evaluate review feedback with rigor |
| `verification-before-completion` | Prove work is done with evidence |
| `finishing-a-development-branch` | Merge, PR, or clean up completed work |
| `using-git-worktrees` | Isolate feature work in git worktrees |
| `dispatching-parallel-agents` | Run independent tasks concurrently |
| `writing-skills` | Create and test new skills for this plugin |

## Structure

```
skills/          each subfolder is a skill with a SKILL.md
agents/          named subagent definitions
hooks/           session-start bootstrap
scripts/         helper scripts (rk.py, review.py, etc.)
templates/       workspace scaffolding templates
vscode-plugins/  VSCode MCP extension for diff integration
```

## Included tools

- **rk.py** — Manages coordinated topic branches across TheRock superproject and submodules
- **review.py** — Code review workflow helper (staging, comments, diffs)
- **stella-ide-mcp** — VSCode extension for opening diffs and files via MCP

## Author

ethtrinh@amd.com
