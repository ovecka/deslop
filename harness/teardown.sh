#!/usr/bin/env bash
# Leave the environment as found, except the triage branch and the runbook.
# Run from the TARGET repo root. Default = dry run (prints the plan). --apply executes.
#   --apply            execute
#   --purge-reports    also delete .quarantine/reports (diffs, logs, masked scan output)
# What stays on purpose: the triage branch with its commits, handover.md, evals.md,
# gate.sh, smoke.sh, rubric.md, CLAUDE.md (harness files, committed). Say this aloud.
set -uo pipefail
APPLY=0; PURGE=0
for a in "$@"; do case "$a" in --apply) APPLY=1;; --purge-reports) PURGE=1;; esac; done
Q=".quarantine"; REPO="$(basename "$(pwd)")"
run() { if [ "$APPLY" = 1 ]; then eval "$@"; else echo "  would: $*"; fi; }

echo "== 1. Processes started by the harness =="
if [ -f "$Q/pids" ]; then
  while read -r pid; do [ -n "$pid" ] && run "kill -- -$pid 2>/dev/null || kill $pid 2>/dev/null || true"; done < "$Q/pids"
  run "rm -f $Q/pids"
else echo "  no $Q/pids (smoke.sh records PGIDs there)"; fi
for c in $(docker ps -q --filter "name=triage-" 2>/dev/null); do run "docker stop $c"; done
echo "  check by hand: ss -ltnp | grep -E ':(3000|3999)'"

echo "== 2. Worktrees created by the fix loop =="
git worktree list --porcelain | awk '/^worktree /{print $2}' | grep -E "/${REPO}-(prefix|[a-z0-9-]+)$" | while read -r wt; do
  run "git worktree remove --force '$wt'"
done
run "git worktree prune"

echo "== 3. Restore foreign agent context from quarantine =="
if [ -f .claude/settings.json ]; then run "mkdir -p $Q/reports && mv .claude/settings.json $Q/reports/harness-settings.json"; fi
run "rm -f .env.selftest"
# everything the session quarantined (bootstrap list + ad-hoc, e.g. GEMINI.md), except reports/
for f in $(cd "$Q" && find . -mindepth 1 -maxdepth 2 ! -path './reports*' ! -name reports ! -path './.github' | sed 's|^\./||'); do
  if [ -e "$Q/$f" ]; then
    if [ -e "$f" ] && [ "$f" != ".claude" ]; then
      echo "  CONFLICT: $f exists (harness) and $Q/$f (foreign). Harness copy is committed on the branch;"
      echo "            restoring foreign copy to the working tree — branch keeps ours, main keeps theirs."
    fi
    run "rm -rf '$f' && mkdir -p '$(dirname "$f")' && mv '$Q/$f' '$f'"
  fi
done

echo "== 4. Reports =="
if [ "$PURGE" = 1 ]; then run "rm -rf $Q/reports"; else echo "  kept: $Q/reports (gitignored; diffs, logs, MASKED scan locations). --purge-reports to delete."; fi
[ -z "$(ls -A "$Q" 2>/dev/null)" ] && run "rmdir $Q"

echo "== 5. What stays, and how it merges =="
BASE="$(git merge-base HEAD main 2>/dev/null || git merge-base HEAD master 2>/dev/null || echo '')"
echo "  branch: $(git branch --show-current)"
[ -n "$BASE" ] && { echo "  commits since base:"; git log --oneline "$BASE..HEAD" | sed 's/^/    /'; }
echo "  harness files on the branch: CLAUDE.md rubric.md gate.sh smoke.sh handover.md evals.md"
echo "  merge: review handover.md, then 'git merge --no-ff $(git branch --show-current)' from main; CLAUDE.md on the branch REPLACES theirs — decide before merging."
[ "$APPLY" = 0 ] && echo "== dry run. Re-run with --apply. =="
exit 0
