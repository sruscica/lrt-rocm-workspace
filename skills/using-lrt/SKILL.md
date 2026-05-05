---
name: using-lrt
description: Reference for available skills — invoke skills when the user explicitly requests one via /skill-name, or when a skill is clearly the right tool for the job
---

<SUBAGENT-STOP>
If you were dispatched as a subagent to execute a specific task, skip this skill.
</SUBAGENT-STOP>

## Instruction Priority

User instructions always take precedence:

1. **User's explicit instructions** (CLAUDE.md, GEMINI.md, AGENTS.md, direct requests) — highest priority
2. **LRT skills** — available when invoked
3. **Default system prompt** — lowest priority

## How to Access Skills

**In Claude Code:** Use the `Skill` tool. When you invoke a skill, its content is loaded and presented to you—follow it directly. Never use the Read tool on skill files.

**In Copilot CLI:** Use the `skill` tool. Skills are auto-discovered from installed plugins.

**In Gemini CLI:** Skills activate via the `activate_skill` tool.

## When to Use Skills

- **User explicitly invokes a skill** via `/skill-name` — always honor this
- **A skill clearly matches the task** — e.g., `/workflow` for the ROCm pipeline, `/the-rock` for build instructions
- **Use your judgment** — skills are tools, not mandates. If the task is straightforward, just do it

Skills should help you work faster, not slow you down with ceremony.
