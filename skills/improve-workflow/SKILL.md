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

## Analysis Mode (Optional Entry Path)

Use this mode **only** when the user explicitly asks to analyze or review how a prior use of the workflow skill went (e.g., "analyze the last workflow run", "review how that pipeline went", "what went wrong in that workflow session"). If the user has a specific improvement in mind without needing to analyze a prior run, skip directly to **The Loop**.

### Step A1: CONTEXT GATHERING

Determine how to access the prior workflow run's artifacts:

**Same session** (the workflow skill was used earlier in this Claude Code conversation):
- You already have conversation context from the run — use it alongside the thinking directory artifacts
- Read the thinking directory contents: `status.md`, and files in `analysis/`, `plans/`, `builds/`, `tests/`, `reviews/`, `investigations/`, `commits/`, `scripts/`
- Read test artifacts from the sibling `testing/` directory if it exists (e.g., `<artifact_base>/testing/YYYY-MM-DD-<topic-slug>/`)

**Fresh or isolated session** (no workflow run in this conversation):
- Look for thinking directories:
  - Inside Docker with `THEROCK_WORK_DIR` set: list directories under `<THEROCK_WORK_DIR>/thinking/`
  - Outside Docker: if the workspace path is apparent from context, use it; otherwise ask the user. Then list directories under `<workspace>/thinking/`
- Present the discovered directories (named `YYYY-MM-DD-<topic-slug>`) sorted by date, most recent first
- Ask the user which run to analyze
- Read the selected thinking directory's contents: `status.md`, and all files in subdirectories (`analysis/`, `plans/`, `builds/`, `tests/`, `reviews/`, `investigations/`, `commits/`, `scripts/`)
- Read test artifacts from the sibling `testing/` directory if it exists (e.g., `<artifact_base>/testing/YYYY-MM-DD-<topic-slug>/`)

In both cases, note any specific observations the user provided in their initial prompt — these are user-reported issues to be evaluated alongside the artifact analysis.

### Step A2: ANALYSIS

Review the run artifacts (and conversation context if same session). Classify findings into three categories:

- **Confirmed issues** — clearly wrong behavior with evidence in the artifacts (e.g., incorrect routing visible in status.md agent activity log, build failures on valid code, reviewer rejections citing wrong criteria, agents violating command rules, session enforcement gaps visible in the flow)
- **Suspected issues** — behavior that looks off but could be non-deterministic or context-dependent; needs testing via agent dispatch to verify (e.g., PM might consistently misroute a class of prompts, a session enforcement might be missing for an edge case)
- **Potential improvements** — not broken, but suboptimal (e.g., unnecessary agent hops, missing state in status.md, agent instructions that could be clearer)

**User-provided observations**: Evaluate each against the evidence in the artifacts. Classify as confirmed (evidence supports it), suspected (plausible but needs testing to verify), or improvement. Do not automatically treat user observations as confirmed — the user may be uncertain about the root cause or whether the behavior is actually a bug.

Present the full analysis with clear categorization. For each finding, reference the specific evidence (artifact file names, specific content from artifacts, conversation context).

### Step A3: TESTING DISCUSSION

If there are no suspected issues → skip to **Step A5**.

Present all suspected issues that would benefit from testing to confirm. For each:
- **What's suspected** — describe the behavior
- **Evidence** — what in the artifacts triggered the suspicion
- **Proposed test** — what agent dispatch would confirm or dismiss it (PM routing test, specialist behavior test, etc.)

This is an iterative discussion, not a simple approve/decline:
- The user can question why something is suspected and ask for more detail
- The user can provide additional context that confirms or dismisses a suspected issue without needing a test
- The user can disagree with the proposed test approach and suggest alternatives
- The user can approve testing for some items and not others
- Continue the conversation until the user is satisfied with the testing plan

If the user declines all testing → drop unconfirmed suspected issues and proceed to **Step A5** with only confirmed issues and improvements.

### Step A4: EXECUTE CONFIRMATION TESTS

Dispatch agents to reproduce the approved suspected issues, using the same test templates from Step 6: TEST in The Loop (PM routing tests, specialist behavior tests).

For each suspected issue:
- Run the test
- Record: test description, prompt used, output received, confirmed or dismissed
- Present results to the user

Issues confirmed by testing are added to the issue list. Issues dismissed by testing are dropped.

### Step A5: CONSOLIDATED ISSUE LIST

Combine all findings into a single numbered list:
- Issues confirmed from artifact analysis (Step A2)
- Issues confirmed by testing (Step A4)
- User observations that were confirmed (by evidence or testing)
- Potential improvements

For each item, note:
- **Issue/improvement** — what it is
- **Source** — how it was identified (artifact analysis, confirmation test, user-reported)
- **Related items** — other issues on the list that are related or dependent (fixing one may resolve another)

Present the list. This is an iterative discussion:
- The user can add, remove, reword, or re-prioritize items
- The user can ask questions about any item
- The user can identify additional relationships between items
- Do not proceed until the user explicitly approves the list

Once approved, enter **The Loop** for each approved issue (see **Entering The Loop from Analysis Mode** below).

---

## The Loop

```
Analysis Mode (optional — only when user asks to analyze a prior run):
  CONTEXT GATHERING → ANALYSIS → TESTING DISCUSSION
  → CONFIRMATION TESTS → ISSUE LIST → enters The Loop

The Loop (direct entry, or from Analysis Mode):
┌─ UNDERSTAND ◄──────────────────────────────────┐
│  OPTIONS                                        │
│  PLAN ◄──────────┐                              │
│  TEST PLAN       │                              │
│  IMPLEMENT       │                              │
│  TEST            │                              │
│  ├─ fail (≤3) ──►┘ (back to PLAN with findings) │
│  ├─ fail (>3) ──► ASK USER FOR GUIDANCE         │
│  └─ pass ──► SUMMARY                           │
│              ├─ more? (direct entry) ───────────┘
│              └─ next issue (analysis mode) ─────┘
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

First, consider the implementation approaches available. You must decide whether to present one recommendation or two options:

**Present a single recommendation** when any of these apply:
- One approach is the established/standard way to do it (e.g., session enforcement for invariants, PM instructions for routing hints)
- One approach strictly dominates — better on every trade-off axis with no meaningful downside
- Two approaches exist but differ only in minor details, not in architecture — picking the simpler one loses nothing

For a single recommendation, present:
- **Approach** — one sentence describing the strategy
- **Files changed** — which files would be modified
- **Why this over alternatives** — one sentence on what was considered and why it was ruled out

**Present two options** when there is a genuine architectural choice with meaningful trade-offs — the approaches differ in *where* (which file/layer), *who* (which agent owns the behavior), or *how* (session enforcement vs PM guidance vs agent instruction), and each has a real advantage the other lacks.

For two options, present each with:
- **Approach** — one sentence describing the strategy
- **Files changed** — which files would be modified
- **Trade-off** — what's better and worse about this approach

**User response:**
- For a single recommendation: the user can accept or redirect (redirect → go back to **Step 1: UNDERSTAND** with their input)
- For two options, the user has three choices:
  1. Pick option A
  2. Pick option B
  3. Provide their own input — blend, redirect, or something entirely different (→ go back to **Step 1: UNDERSTAND**)

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
| Cross-phase back-edge, state-transition rule, or session-enforced invariant in `skills/workflow/SKILL.md` (or its reference files) | State-machine | Trace transitions on paper; build state-transition table, reachability checklist, counter-trace |
| Multiple files | Combined | Run all applicable test types |

**Dispatch template testing (critical).** When a SKILL.md change adds or modifies an agent dispatch template (a PM prompt schema, a specialist dispatch format), you MUST test that template with an actual agent dispatch — even though the file changed is SKILL.md. Re-reading your own edits is proofreading, not testing. Specifically:
- New PM dispatch format → dispatch PM 3 times with varied inputs, verify JSON output matches the expected schema
- New specialist dispatch format → dispatch the specialist with a mock scenario, verify it produces the expected behavior
- Modified dispatch format → test that existing dispatches still work with the updated format

**State-machine / cross-phase invariant testing.** When a change adds or modifies a cross-phase back-edge (e.g., Phase 2.5 → Phase 2 regression path), a state-transition rule (e.g., a Test Status update), or a session-enforced invariant (e.g., a re-entry guard), trace the state machine on paper before committing. The test is analytical, not agent-dispatched. Write the three artifacts inline in your test plan:

1. **State-transition table** — list every `(from_state, trigger, to_state)` the change touches.

   ```
   | From | Trigger | To | Notes |
   |------|---------|-----|-------|
   | TESTED (targeted-pass) | wider-suite triage classifies REGRESSION | TESTED (regression) | Phase 2.5 Step 7a |
   | TESTED (regression)    | re-enter Phase 2 LOOP                     | (skip step 1, enter step 3) | session invariant |
   ```

2. **Reachability checklist** — for each touched state, name a path that reaches it AND a path that should NOT.

   - `TESTED (regression)` reached from: Phase 2.5 Step 7a after triage. Should NOT be reached from: targeted-tester pass, pre-existing-flagged, or cannot-classify.
   - LOOP step 3 entered without step 1 from: regression re-entry invariant when Test Status is `TESTED (regression)`. Should NOT be entered without step 1 from: any other Test Status.

3. **Counter-trace** — pick three plausible adversarial inputs and walk through what the session does. The invariant passes only if all three traces produce the documented behavior. Examples:

   - What if Test Status is `TESTED (regression)` but `<thinking_dir>/investigations/` is empty? → spec must define a fallback.
   - What if a major iteration increment occurs after regression detection? → invariant must clear (re-read SKILL.md to confirm).
   - What if the user re-runs `/workflow` from a fresh session? → status.md must be the source of truth (verify Test Status is read at Phase 2 entry, not assumed from in-memory state).

A worked example exists in `skills/workflow/SKILL.md` under the "Regression re-entry invariant" section (added when Phase 2.5's Step 7a back-edge was made explicit).

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

**Direct entry mode:**
Ask: "Is there more to do on this, or a related improvement?"
- **Yes** → go back to **Step 1: UNDERSTAND**
- **No** → done

**Analysis mode** (working through an approved issue list):
Check the approved issue list for remaining items.
- **Dependent issues** — if the next item was marked as related to the issue just fixed, re-test it first (dispatch an agent to reproduce the original suspected behavior). If the issue no longer reproduces, report that it was resolved by the prior fix and skip it. If it still reproduces, proceed normally.
- **Related issues** — batch related issues together into a single pass through The Loop when they affect the same files or the same behavior.
- **More items remain** → move to the next item on the list, entering **Step 1: UNDERSTAND** for that issue.
- **All items done** → present a final summary of all changes made across all issues, then done.

### Entering The Loop from Analysis Mode

When entering The Loop from Analysis Mode with an approved issue list:
- Process items in the approved order
- For each item (or batch of related items), enter at **Step 1: UNDERSTAND** — the issue description from the approved list provides the starting context, but UNDERSTAND still confirms the specific what/why/success-criteria with the user
- After each SUMMARY, check the list for the next item (see analysis mode behavior in Step 8 above)

---

## Tips

- **Read before editing.** Agent definitions accumulate specific fixes. A line that looks unnecessary may prevent a regression.
- **Prefer session enforcement over PM instructions** for critical invariants. PM is probabilistic; session is deterministic.
- **Test the unhappy paths.** Most bugs are in edge cases — reviewer rejects, builds fail, agents time out.
- **Small changes compound.** One change, test it, commit it. Don't batch unrelated changes.
