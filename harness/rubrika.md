# Discovery rubric

## Output format (per finding)
`file:line | impact | minimal fix` (sweep) → `+ severity` added only at the verify step
Max ~3 findings per axis. Separate section: **Checked, OK** — what you examined
and found sound (mandatory; absence of findings is unreportable unless demanded).
Calibrate against the manually-walked main path — no HIGH on dead code.
Every cited file:line must exist (verified mechanically before triage).

## Severity decision procedure
Answer three questions, then anchor against the examples:
1. Reachable from the main path without authentication?
2. Does exploitation require existing privileges?
3. Blast radius: one record, or a whole table / money / identity?

| Severity | Anchor example |
|----------|----------------|
| HIGH | IDOR: change id in URL → other user's data. Hardcoded live API key. Unparameterized SQL on a public route. Missing transaction around money movement. |
| MEDIUM | Missing token expiry. N+1 on an authenticated route. Silent catch swallowing payment-provider errors. No pagination on a large table (authenticated). |
| LOW | console.log instead of structured logs. Missing health check. Stale dev dependency without a known CVE on a runtime path. |

Verdict question for every finding: **"what stops this from running as critical
production?"** — not "is it vulnerable?".

Production ordering for triage: (1) runs & survives failure (config via env,
crash behavior, health endpoint, deploy + rollback path), (2) money & DB state
integrity, (3) authn/authz, (4) everything else → backlog with reason.

## Sweep axes (checklist — one sweep covers several axes)
- **Sweep A:** authn/authz (BOLA/IDOR, token expiry, admin routes hidden by obscurity),
  input validation + injection (schema vs. trust, size limits, SQL/shell)
- **Sweep B:** data layer (transactions, indexes, N+1, migrations, pagination),
  error handling (empty catches, silent failures, timeouts/retry, partial ops without rollback)
- **Sweep C (equal weight with A/B — productionization is the assignment):**
  observability (structured logs, correlation IDs, health check),
  operational maturity (env config vs. hardcode, crash/restart behavior,
  deploy + rollback path, dep age, lockfile, CI),
  triage of deterministic tool output (gitleaks, semgrep, audit, knip dead code).
  Sweep C ALWAYS writes two handover sections from its material, no extra agent:
  "Observability" (ordered sub-list under Path to production: logger + run id,
  alerting on non-zero exit, real health check, request log, restart policy) and
  "Architecture & testability (backlog only)". A missing section is a question
  the stakeholder will ask.
- **All sweeps:** testability/architecture notes → backlog only, never into fixes.

## Constraints for discovery and review agents
- Read-only. The Agent tool cannot restrict tools, so this line is documentation;
  the enforcement is `git status --porcelain` empty before AND after every agent.
- Forbidden explicitly: `git stash`, `git reset`, `git checkout`, `git clean` —
  a reviewer once stashed the working tree "to test HEAD" under a read-only prompt.
- Sweep A must enumerate every route handler with its caller count; 0-caller
  routes are attack surface, report them mechanically.
- Cheap tier reports findings WITHOUT severity; severity is assigned at the
  verify step (strong model), never by the sweep itself.
- Never Read secret-bearing files (`.env*`, `*.pem`, `*.key`, `*credentials*`);
  report their existence + key names only (`grep -oE '^[A-Za-z_]+='`).
- You get the repo structure; request specific files, do not assume content.
- Cheap model tier; hard format above compensates.
