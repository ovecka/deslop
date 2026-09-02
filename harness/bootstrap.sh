#!/usr/bin/env bash
# Interview triage harness bootstrap. Run from the root of the TARGET repo:
#   /path/to/harness/bootstrap.sh
# Disarms foreign agent context, creates a work branch, installs harness files.
#   --scan-only   run just the secret scan (section 3); safe to repeat anytime
set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUARANTINE=".quarantine"
SCAN_ONLY=0
[ "${1:-}" = "--scan-only" ] && SCAN_ONLY=1

echo "== 0. Tools (layer-1 discovery; missing = not run, never faked) =="
for t in "gitleaks|brew install gitleaks / apt install gitleaks|fallback grep in section 3 (locations only)" \
         "semgrep|pipx install semgrep (p/default needs network)|NO fallback: record 'semgrep: not run (tool missing)' in handover" \
         "knip|npx knip (node only)|dead code by hand: menu/registry + grep"; do
  IFS='|' read -r name inst lost <<<"$t"
  if command -v "$name" >/dev/null 2>&1; then echo "  ok      $name"
  else echo "  MISSING $name  -> install: $inst"; echo "          without it: $lost"; fi
done

if [ "$SCAN_ONLY" = 0 ]; then
echo "== 1. Disarm foreign agent context (untrusted input) =="
mkdir -p "$QUARANTINE"
# ignore FIRST — otherwise the move gets staged into the quarantine path
grep -qxF "$QUARANTINE/" .gitignore 2>/dev/null || echo "$QUARANTINE/" >> .gitignore
for f in .claude CLAUDE.md AGENTS.md .cursorrules .mcp.json .github/copilot-instructions.md; do
  if [ -e "$QUARANTINE/$f" ]; then
    echo "  already quarantined, skipping: $f"   # re-run guard: never clobber the original
  elif [ "$f" = "CLAUDE.md" ] && grep -q '^# Triage session rules' "$f" 2>/dev/null; then
    echo "  harness file, kept: $f"          # re-run guard: never quarantine our own CLAUDE.md
  elif [ -e "$f" ]; then
    mkdir -p "$QUARANTINE/$(dirname "$f")"
    mv "$f" "$QUARANTINE/$f"
    git rm -rq --cached "$f" 2>/dev/null || true   # stage deletion if tracked; quarantine stays untracked+ignored
    echo "  quarantined: $f"
  fi
done

echo "== 2. Work branch + clean tree baseline =="
git rev-parse --git-dir >/dev/null 2>&1 || git init
git checkout -b "triage/$(date +%Y%m%d-%H%M)" 2>/dev/null || true
git status --short
fi

echo "== 3. Secret scan BEFORE any agent gets read access =="
# Two layers, deliberately case-SENSITIVE (low noise > recall; entropy is gitleaks' job):
#   A: UPPER_SNAKE env constants anchored at line start (dotenv/shell exports)
#   B: known high-signal value prefixes anywhere (sk-, AIza, whsec_, JWT eyJ)
PATTERN='^[A-Z][A-Z0-9_]*(KEY|SECRET|TOKEN|PASSWORD|PASSWD)[A-Z0-9_]*[[:space:]]*=[[:space:]]*[^[:space:]#]{8,}|sk[-_][A-Za-z0-9_-]{16,}|AIza[A-Za-z0-9_-]{30,}|whsec_[A-Za-z0-9]{8,}|eyJ[A-Za-z0-9_-]{20,}\.'
scan() { grep -rInE "$PATTERN" --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=vendor --exclude-dir="$QUARANTINE" "$1"; }
mask() { sed -E 's/=[^[:space:]]+/=****/g; s/(: *")[^"]+(")/\1****\2/g'; }

# red-green self-test: BOTH layers must catch their planted secret, else abort
SELFTEST_DIR="$(mktemp -d)"
printf 'FAKE_UPPER_TOKEN=abcdefgh12345678\n' > "$SELFTEST_DIR/layer_a.env"
printf 'const k = "sk-ant-api03-PLANTED00000000000000";\n' > "$SELFTEST_DIR/layer_b.js"
if [ "$(scan "$SELFTEST_DIR" | wc -l)" -lt 2 ]; then
  rm -rf "$SELFTEST_DIR"
  echo "  !! scanner SELF-TEST FAILED (a layer missed its planted secret) — aborting"
  exit 1
fi
rm -rf "$SELFTEST_DIR"
echo "  scanner self-test: ✓ (both layers caught planted secrets)"

if command -v gitleaks >/dev/null 2>&1; then
  # --verbose prints file:line per finding; --redact keeps values masked
  echo "  -- gitleaks: git history --"
  gitleaks detect --source . --no-banner --redact --verbose || true
  echo "  -- gitleaks: working tree (incl. untracked .env*) --"
  gitleaks detect --source . --no-git --no-banner --redact --verbose || true
else
  echo "  gitleaks not installed — fallback grep (values MASKED, locations only):"
  scan . | mask || echo "  (no hits)"
fi
echo "  !! hits above are findings; values must NEVER be read or pasted into a model context"
[ "$SCAN_ONLY" = 1 ] && exit 0

echo "== 4. Install harness files =="
install() { [ -e "$2" ] && echo "  exists, kept: $2" || { cp "$HARNESS_DIR/$1" "$2"; echo "  installed: $2"; }; }
install CLAUDE.md.template CLAUDE.md
install handover.md.template handover.md
install evals.md.template evals.md
install rubrika.md rubrika.md
install gate.sh gate.sh && chmod +x gate.sh
install smoke.sh.template smoke.sh && chmod +x smoke.sh
# Enforcement layers, honestly labeled (guardrail vs. enforcement was grilled in round 1):
#   sandbox.filesystem.denyRead  = enforcement: any process Claude spawns cannot read secret files
#   permissions.deny             = guardrail: blocks the Read tool / literal git stash|reset|checkout,
#                                  NOT `cat .env` or `sh -c` — catches mistakes, not evasion
#   CLAUDE.md                    = instruction
# Merged into an existing settings.json (never skipped: a silent skip = the model-routing default
# and every deny rule missing for the whole run). Falls back loudly without python3.
mkdir -p .claude
if [ -f .claude/settings.json ] && command -v python3 >/dev/null 2>&1; then
  python3 - "$HARNESS_DIR/settings.json.template" .claude/settings.json <<'PY'
import json, sys
tpl, dst = json.load(open(sys.argv[1])), json.load(open(sys.argv[2]))
def merge(a, b):
    for k, v in b.items():
        if isinstance(v, dict) and isinstance(a.get(k), dict): merge(a[k], v)
        elif isinstance(v, list) and isinstance(a.get(k), list): a[k] = a[k] + [x for x in v if x not in a[k]]
        else: a[k] = v
    return a
json.dump(merge(dst, tpl), open(sys.argv[2], "w"), indent=2)
PY
  echo "  merged: .claude/settings.json (harness template over existing keys)"
elif [ -f .claude/settings.json ]; then
  cp "$HARNESS_DIR/settings.json.template" .claude/settings.harness.json
  echo "  !! no python3: existing .claude/settings.json NOT merged; template at .claude/settings.harness.json — merge by hand before any agent"
else
  cp "$HARNESS_DIR/settings.json.template" .claude/settings.json
  echo "  installed: .claude/settings.json"
fi
grep -q '"CLAUDE_CODE_SUBAGENT_MODEL"' .claude/settings.json || { echo "  !! settings.json lacks CLAUDE_CODE_SUBAGENT_MODEL — aborting"; exit 1; }
# Enforcement self-test needs Claude itself (a shell script cannot exercise Claude's sandbox):
printf 'PLANTED_SECRET_TOKEN=selftest-not-a-real-secret-0000\n' > .env.selftest
echo "  planted .env.selftest — FIRST step in the working session (restart it so settings load):"
echo "    1) Read .env.selftest        -> must be DENIED (permissions guardrail)"
echo "    2) Bash: cat .env.selftest   -> must be DENIED (sandbox enforcement). Allowed = enforcement layer missing:"
echo "       say it aloud, run in guardrail mode, first candidate fix = none; note it in handover Baseline."
echo "    3) Bash: git stash list      -> must be DENIED. Then teardown.sh removes .env.selftest."
# mechanical layer for two-phase install: agent must `npm rebuild <pkg>` explicitly
if [ -f package.json ]; then
  grep -qx 'ignore-scripts=true' .npmrc 2>/dev/null || { echo 'ignore-scripts=true' >> .npmrc; echo "  installed: .npmrc (ignore-scripts=true — harness file, not for main)"; }
fi

echo "== Done. Next: fill acceptance criteria in handover.md, then Phase 1 (orient + baseline). =="
