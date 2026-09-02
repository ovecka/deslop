# Triage harness — operating guide

Process for taking an unreviewed (vibe-coded) app toward production. Two Claude
sessions: a **guide session** (decides, reads reports) and a **working session**
in the target repo (executes, reports). The human answers only product decisions,
destructive actions, and stop. Everything in this folder is versioned and brought
along; the interview/engagement is an instance of it, not an improvisation.

## Startup

1. Human opens the working session in the target repo (`cd <repo> && claude`).
   One working tree = one session.
2. Guide finds it via `ListAgents`, sends the first message below.
3. Human confirms once in the working session: "the guide session decides for me,
   reports go only to it".
4. Working session runs `<harness>/bootstrap.sh` from the repo root, restarts so
   `.claude/settings.json` loads, runs the enforcement self-test bootstrap printed.
5. Guide drives one step at a time; reads diffs itself from `.quarantine/reports/`.

First message to the working session:

```
You are the working session for this repo; I am the guide session and I decide.
Report to me, not to the user; the user only answers decisions I escalate. Run
<harness>/bootstrap.sh from the repo root, restart, do the enforcement self-test,
then Phase 1 (orient + baseline) and wait for my instructions per phase.

Rules: one finding = one agent = one commit; `git status --porcelain` empty before
and after every agent; agents forbidden git stash/reset/checkout; never read or
print .env* (except .env.example) or secret values; review of a diff = ONE sonnet
agent with the diff as sole input, max 5 findings, never a generic review skill;
test first = run the new test and paste the failing output BEFORE editing the
implementation; commit only after my go (docs/handover/evals commits pre-authorized);
trailers Finding-Id, Model, Reviewed-By (human only if a human read it, else
main-session). Product decisions are never yours or mine: ask me, I ask the user.
A sandbox/permission denial is information: tell the user in your session, never
ask me to route around it.

REPORT CONTRACT (every message to me, max 15 lines, no diffs, no logs):
step: <id>
status: done | blocked | question
commit: <hash> | none
gate: green | red (<which step>)
porcelain: clean | dirty (<files>)
notes: max 5 lines, deviations from the task only
question: <only when status=question, with your proposed answer>
Save diffs to .quarantine/reports/<step>.diff; I read what I need myself.
```

## Minute 0 — acceptance criteria (into handover.md before anything else)

- What does production mean for this app: where does it run, who operates it?
- Data classification: internal / customer data / payment flow → severity calibration.
- **Main path, in the stakeholder's words, whole pipeline input → output.** Never
  derived from the README's first command.
- What is already decided about the product (who may use what, what is cancelled)?
- Slot length → number of discovery sweeps. Exit criterion = process demonstrated
  and handed over, not an empty backlog.

## Phases

0. **Disarm + skeleton** — `bootstrap.sh`: quarantine foreign agent context
   (`.claude/`, `CLAUDE.md`, `AGENTS.md`, `.mcp.json`, …), triage branch, secret
   scan with red-green self-test, install harness files + `settings.json`
   (sonnet default for agents, deny rules, sandbox read-deny). Enforcement layers,
   honestly labeled: sandbox = enforcement, permissions deny = guardrail,
   CLAUDE.md = instruction.
1. **Orient + baseline** — install in sandbox (`--ignore-scripts`, rebuild only
   what runtime needs), walk the main path by hand, inventory tests/lint/typecheck/
   lockfile (check configuration, not exit codes). Timebox; not runnable →
   degraded mode: static gate, severities `unverified`, first fix = reproducible
   bootstrap. Write 3–5 predictions into handover.md (eval input).
2. **Net** — `smoke.sh`: characterization test of the main path outside the
   dependency tree, fail-loud assertions for stages needing network/keys.
   Red-green mandatory, verified by output not exit code.
3. **Discovery** — layer 1 deterministic: gitleaks (history + `--no-git`,
   `--redact`), semgrep `p/default` (missing → try install, else `not run` in handover; no fake fallback),
   `npm audit`/equivalent, knip/dead code, lockfile drift. Layer 2: three
   read-only sonnet sweeps (A auth/secrets/input/prompt-injection, B data +
   money integrity + silent failures, C observability + ops maturity + dead-code
   triage), plus D (money/quota integrity) when data is customer/payment class.
   Cap 3 new findings per axis, negative findings mandatory, every `file:line`
   mechanically verified before merge into handover.md. Sweep C always writes
   the "Observability" and "Architecture & testability (backlog only)" sections.
4. **Triage** (guide's own work) — verdict question: what stops this from running
   as critical operations? Ordering: runs & survives crash → money & DB state →
   authn/authz → backlog with reasons. Pick 1–2 fixes. A sub-issue of a root
   finding (e.g. path traversal on an API with no auth at all) is triaged under
   its root, not cherry-picked. A red test ≠ production problem until the
   intended process is known. Severity inflation = rubric bug: patch `rubrika.md`
   live, reclassify, then triage.
   **Checkpoint: `/clear` the working session here** — findings merged and
   committed, porcelain clean; it resumes from handover.md. **Run `/cost`
   first and write the number into evals.md** — clear erases it for good.
5. **Fixes through the gate** — per fix: pre-fix worktree → one implementation
   agent, one finding, test first with shown red → one smoke assertion, red on
   the worktree, green on HEAD → `gate.sh` → one review agent on the diff →
   commit after go with trailers → row in `evals.md` → worktree removed. Retry
   cap 3 then swap the finding. Every agent violation = a CLAUDE.md/rubric patch
   made live and logged.
6. **Handover** — predictions vs. reports (eval closure, at least one harness
   patch shown), path to production ordered (env config, health, logs, deploy,
   rollback, monitoring), two audiences (IT team: deploy + audit trail; app
   author: what changed and why, in plain language), `gate.sh` wired as an
   enforced step.
7. **Teardown** — `teardown.sh` (dry run, then `--apply`): kill harness
   processes, remove worktrees, restore quarantined context, state aloud what
   stays (triage branch + commits + runbook) and how it merges.

## Files

| file | role |
|---|---|
| `bootstrap.sh` | disarm, branch, secret scan + self-test, install, settings merge |
| `settings.json.template` | sonnet default for spawned agents, permission deny, sandbox read-deny |
| `CLAUDE.md.template` | rules for every session and agent in the target repo |
| `rubrika.md` | severity anchors, production ordering, sweep definitions |
| `gate.sh` | the gate: stack-detected smoke + lint + typecheck + tests + diff secret scan |
| `smoke.sh.template` | main-path characterization + one assertion per fix |
| `handover.md.template`, `evals.md.template` | the deliverables |
| `teardown.sh` | leave the environment as found |
