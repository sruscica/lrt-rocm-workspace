---
name: improve-workflow
description: Use when improving the workflow skill, agent definitions, or pipeline behavior — structured loop with understanding, options, planning, implementation, and verified testing
---

# Improve Workflow

Structured process for making changes to the ROCm agent pipeline — the workflow skill (`skills/workflow/SKILL.md`), agent definitions (`agents/*.md`), and supporting files (`agents/DISPATCH-PROTOCOL.md`).

> **You are improving the workflow itself, not doing ROCm development.** Do not invoke `/workflow`. Changes to files in this repo are live immediately via symlink.

## Before Starting

Read these files for architectural context:
- `CLAUDE.md` — architecture, testing approach, common pitfalls
- The specific files relevant to the user's request

## The Loop

```
┌─ UNDERSTAND ◄──────────────────────────────────┐
│  OPTIONS                                        │
│  PLAN ◄──────────┐                              │
│  TEST PLAN       │                              │
│  IMPLEMENT       │                              │
│  TEST            │                              │
│  ├─ fail (≤3) ──►┘ (back to PLAN with findings) │
│  ├─ fail (>3) ──► ASK USER FOR GUIDANCE         │
│  └─ pass ──► SUMMARY                           │
│              └─ more? ──────────────────────────┘
└─ done
```

Track the plan-implement-test loop count. Reset to 0 when entering UNDERSTAND.

---

### Step 1: UNDERSTAND

Summarize the user's request in your own words:
- **What** they want changed (which behavior, which agent, which pipeline step)
- **Why** (what's broken, what's missing, what's suboptimal)
- **What success looks like** (expected behavior after the change)

Present this summary and ask: "Is this right, or should I adjust my understanding?"

If the user disagrees or provides corrections:
1. Acknowledge what changed in their feedback
2. Revise the What / Why / What success looks like based on their input
3. Re-present the **full updated summary** (not just the delta)
4. Ask again: "Is this right, or should I adjust my understanding?"

Repeat until the user explicitly confirms. Do not proceed to OPTIONS until they agree.

### Step 2: OPTIONS

Present exactly two implementation options. For each:
- **Approach** — one sentence describing the strategy
- **Files changed** — which files would be modified
- **Trade-off** — what's better and worse about this approach

Options must represent genuinely different architectural approaches — not minor variations of the same idea. If both options do the same thing with a small tweak, they aren't different enough. Differentiate on *where* (which file/layer), *who* (which agent owns the behavior), or *how* (session enforcement vs PM guidance vs agent instruction).

The user has three choices:
1. Pick option A
2. Pick option B
3. Provide their own input — blend, redirect, or something entirely different

If the user picks option 3 → go back to **Step 1: UNDERSTAND** with the new input.

### Step 3: PLAN

Create an ordered implementation plan for the chosen approach. For each change:
- **File** — path
- **Section** — which section of the file
- **Current behavior** — what it does now
- **New behavior** — what it should do after the change
- **Risk** — what could break

Review the plan against CLAUDE.md pitfalls:
- Adding complex conditional logic to PM instructions? → unreliable, consider session enforcement
- Removing an override that looks redundant? → it probably prevents a regression
- Change affects routing, classification, or pipeline flow? → MUST read `tests/workflow-test-plan.md` and identify existing test cases that cover the changed behavior

### Step 4: TEST PLAN

Determine which test type(s) are needed based on the files being changed:

| Files changed | Test type | Method |
|---|---|---|
| `agents/pm-orchestrator.md` | PM routing | Dispatch PM 3 times with varied prompts testing the same objective |
| `agents/<specialist>.md` | Specialist behavior | Dispatch the specialist with a mock task exercising the changed behavior |
| `skills/workflow/SKILL.md` | Session logic | Read the spec and verify assertions; note if full pipeline test is needed |
| `agents/DISPATCH-PROTOCOL.md` | Specialist behavior | Test any agent affected by the protocol change |
| Multiple files | Combined | Run all applicable test types |

**Dispatch template testing (critical).** When a SKILL.md change adds or modifies an agent dispatch template (a PM prompt schema, a specialist dispatch format), you MUST test that template with an actual agent dispatch — even though the file changed is SKILL.md. Re-reading your own edits is proofreading, not testing. Specifically:
- New PM dispatch format → dispatch PM 3 times with varied inputs, verify JSON output matches the expected schema
- New specialist dispatch format → dispatch the specialist with a mock scenario, verify it produces the expected behavior
- Modified dispatch format → test that existing dispatches still work with the updated format

**For PM routing tests:** Write 3 different prompts that test the same objective but phrase the request differently — real users don't use identical wording. Define the expected JSON output fields and values for each.

**For specialist behavior tests:** Write a mock dispatch prompt that puts the agent in the scenario where the changed behavior matters. Define what the agent's output should contain (or not contain).

**For session logic tests:** List the logical assertions to verify by reading SKILL.md. Note when a full pipeline test is warranted — tell the user to run `/workflow <test task>` manually after this process completes.

Check `tests/workflow-test-plan.md` for existing test cases that cover the changed behavior. Reuse those rather than inventing new ones when applicable.

Present the test plan to the user and wait for explicit approval before proceeding to IMPLEMENT. The test plan is a separate approval from the implementation plan — do not combine them into a single "shall I proceed?" question.

### Step 5: IMPLEMENT

Execute the implementation plan from Step 3:

1. Read each file to be changed — verify current state matches the plan
2. Make the edits
3. Re-read each changed file to verify correctness
4. If the change adds a new feature or behavior to SKILL.md, add a corresponding test case to `tests/workflow-test-plan.md` with prompt, expected behavior, and pass criteria
5. WIP commit the changes:
   ```
   git -C <workspace> add <changed files>
   git -C <workspace> commit -m "wip: <short description>"
   ```

### Step 6: TEST

Execute the test plan from Step 4.

**PM routing test template:**
```
Agent(subagent_type: "pm-orchestrator", prompt: """
ADVISOR MODE. You do NOT have the Agent tool.
DO NOT run any Bash commands. All environment info is provided below.

User task: <varied mock task — same objective, different phrasing>
Workspace: /mock/workspace
Docker: yes
Environment: THEROCK_WORK_DIR=/mock/workspace/therock, PROJECT=default, AMD_GPU_ARCH=gfx1100
Current branch: users/testuser/test-branch
Username: testuser

Respond with ONLY a JSON block — no prose before or after.
<appropriate JSON schema>
""")
```

Run all 3 prompt variations. Record each: prompt used, output received, pass/fail against criteria.

**Specialist behavior test template:**
```
Agent(subagent_type: "<specialist>", prompt: """
You are the <specialist> in the ROCm Agent Pipeline.
You do NOT have the Agent tool.

COMMAND RULES (mandatory):
- NEVER use `cd /path && git ...` → use `git -C /path ...`
- NEVER use `echo "$VAR"` → use `printenv VAR`
- NEVER use brace expansion `{a,b,c}` → spell out each argument
- NEVER use `$VAR` in any command → use `printenv VAR`

Workspace: /mock/workspace
Thinking directory: /mock/workspace/thinking/test
Iteration: 1.0
User request: <mock task>

<scenario-specific context that exercises the changed behavior>
""")
```

Record: prompt used, output received, pass/fail against criteria.

### Step 7: EVALUATE

**All tests pass** → go to **Step 8: SUMMARY**

**Any test fails (loop count ≤ 3):**
- Record what failed and why — the failing test output is critical context
- Increment loop count
- Go back to **Step 3: PLAN** — revise the plan incorporating what was learned from the failure

**Any test fails (loop count > 3):**
- Present to the user:
  - What was attempted across all iterations
  - What specifically keeps failing
  - Your best theory on why
- Ask the user for guidance before continuing

### Step 8: SUMMARY

Present:
- **Changes made** — files modified and what changed in each
- **Test results** — all test runs with prompts, outputs, and pass/fail
- **Commits** — WIP commits made

Then ask: "Is there more to do on this, or a related improvement?"

- **Yes** → go back to **Step 1: UNDERSTAND**
- **No** → done

---

## Tips

- **Read before editing.** Agent definitions accumulate specific fixes. A line that looks unnecessary may prevent a regression.
- **Prefer session enforcement over PM instructions** for critical invariants. PM is probabilistic; session is deterministic.
- **Test the unhappy paths.** Most bugs are in edge cases — reviewer rejects, builds fail, agents time out.
- **Small changes compound.** One change, test it, commit it. Don't batch unrelated changes.
