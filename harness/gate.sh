#!/usr/bin/env bash
# The gate. Every change passes this before commit. Exit 0 = pass.
# Configure per project via env. Unset lint/typecheck = RED (not a silent skip — brick run 3
# found a false green this way); set LINT=skip / TYPECHECK=skip to skip explicitly and loudly.
# Output is quiet on success (token budget); on failure the last 40 lines of the step are shown.
set -uo pipefail

SMOKE="${SMOKE:-./smoke.sh}"          # runtime oracle; unset in degraded mode
LINT="${LINT:-}"                      # e.g. "npm run lint" / "vendor/bin/phpstan"
TYPECHECK="${TYPECHECK:-}"            # e.g. "npx tsc --noEmit"
TEST="${TEST:-}"                      # auto-detected below if the repo already has a runner
FAIL=0

# The gate is a concept, not an npm script. Detect the stack and fill defaults from what the
# repo ALREADY has (never introduce a runner via the gate). Detection is loud; unset stays RED.
have() { command -v "$1" >/dev/null 2>&1; }
if [ -f package.json ]; then
  STACK="node"
  [ -z "$LINT" ] && grep -q '"lint"' package.json && LINT="npm run lint"
  [ -z "$TYPECHECK" ] && [ -f tsconfig.json ] && TYPECHECK="npx tsc --noEmit"
  if [ -z "$TEST" ]; then
    if grep -q '"vitest"' package.json; then TEST="npx vitest run --silent --reporter=dot"
    elif grep -q '"jest"' package.json; then TEST="npx jest --silent"
    elif grep -q '"test"' package.json; then TEST="npm test --silent"; fi
  fi
elif [ -f pyproject.toml ] || [ -f requirements.txt ] || [ -f setup.py ]; then
  STACK="python"
  [ -z "$LINT" ] && have ruff && LINT="ruff check ."
  [ -z "$TYPECHECK" ] && have mypy && TYPECHECK="mypy ."
  [ -z "$TEST" ] && have pytest && TEST="pytest -q"
  [ -z "$TEST" ] && [ -f manage.py ] && TEST="python manage.py test"
elif [ -f composer.json ]; then
  STACK="php"
  [ -z "$LINT" ] && [ -x vendor/bin/phpstan ] && LINT="vendor/bin/phpstan analyse --no-progress"
  [ -z "$LINT" ] && [ -x vendor/bin/psalm ] && LINT="vendor/bin/psalm --no-progress"
  [ -z "$TYPECHECK" ] && TYPECHECK="find . -path ./vendor -prune -o -name '*.php' -print0 | xargs -0 -n1 -P4 php -l >/dev/null"
  [ -z "$TEST" ] && [ -x vendor/bin/phpunit ] && TEST="vendor/bin/phpunit --no-progress"
elif [ -f pom.xml ]; then
  STACK="java-maven"; [ -z "$TYPECHECK" ] && TYPECHECK="mvn -q -DskipTests compile"; [ -z "$TEST" ] && TEST="mvn -q test"
elif [ -f build.gradle ] || [ -f build.gradle.kts ]; then
  STACK="java-gradle"; [ -z "$TYPECHECK" ] && TYPECHECK="./gradlew -q compileJava"; [ -z "$TEST" ] && TEST="./gradlew -q test"
elif [ -f go.mod ]; then
  STACK="go"; [ -z "$LINT" ] && LINT="go vet ./..."; [ -z "$TYPECHECK" ] && TYPECHECK="go build ./..."; [ -z "$TEST" ] && TEST="go test ./..."
else
  STACK="unknown"
fi
echo "stack: $STACK  (lint='${LINT:-UNSET}' typecheck='${TYPECHECK:-UNSET}' test='${TEST:-none}')"

step() {
  local name="$1"; shift
  if [ "$*" = "skip" ]; then echo "~ $name: SKIPPED explicitly"; return; fi
  if [ -z "$*" ]; then
    case "$name" in
      lint|typecheck) echo "✗ $name: NOT CONFIGURED — set ${name^^} or ${name^^}=skip"; FAIL=1; return;;
      *) echo "~ $name: not configured (skipped)"; return;;
    esac
  fi
  local out; out="$(mktemp)"
  if eval "$@" >"$out" 2>&1; then
    echo "✓ $name"
  else
    echo "✗ $name FAILED — last 40 lines:"; tail -n 40 "$out" | sed 's/^/    /'; FAIL=1
  fi
  rm -f "$out"
}

step "smoke"     "${SMOKE:+$SMOKE}"
step "lint"      "$LINT"
step "typecheck" "$TYPECHECK"
step "test"      "$TEST"

echo "-- secret scan: added lines + untracked files (values masked) --"
# same two-layer pattern as bootstrap.sh: UPPER_SNAKE env constants + known value prefixes
PATTERN='^[A-Z][A-Z0-9_]*(KEY|SECRET|TOKEN|PASSWORD|PASSWD)[A-Z0-9_]*[[:space:]]*=[[:space:]]*[^[:space:]#]{8,}|sk[-_][A-Za-z0-9_-]{16,}|AIza[A-Za-z0-9_-]{30,}|whsec_[A-Za-z0-9]{8,}|eyJ[A-Za-z0-9_-]{20,}\.'
mask() { sed -E 's/=[^[:space:]]+/=****/g; s/(sk[-_]|AIza|whsec_|eyJ)[A-Za-z0-9_.-]+/\1****/g'; }
if git diff HEAD | grep -E '^\+[^+]' | cut -c2- | grep -nE "$PATTERN" | mask | grep .; then
  echo "✗ possible secret in added lines"; FAIL=1
elif git ls-files --others --exclude-standard -z | xargs -0 -r grep -nE "$PATTERN" 2>/dev/null | mask | grep .; then
  echo "✗ possible secret in untracked file(s) above (agent-created?)"; FAIL=1
else
  echo "✓ no secrets in diff or untracked files"
fi

echo "-- human step (not automatable) --"
echo "  [ ] diff read by human: git diff HEAD"

exit $FAIL
