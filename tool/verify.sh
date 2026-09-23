#!/usr/bin/env bash
# Single verification entrypoint for humans, agents and CI.
#
#   bash tool/verify.sh          full: everything CI runs, including pana
#   bash tool/verify.sh --fast   local loop: skips pana, prints failures only
#
# Exits non-zero if any step fails. Every step runs even after a failure, so
# one run reports every problem.
set -uo pipefail
cd "$(dirname "$0")/.."

fast=false
[ "${1:-}" = "--fast" ] && fast=true
reporter=$($fast && echo failures-only || echo compact)
status=0

step() {
  local label=$1; shift
  echo "==> $label"
  if ! "$@"; then
    echo "FAILED: $label"
    status=1
  fi
}

step "principles" bash tool/check_principles.sh

for dir in packages/*/; do
  pkg=$(basename "$dir")
  (cd "$dir" && flutter pub get >/dev/null) || { echo "FAILED: pub get $pkg"; status=1; continue; }
  if ! $fast && [ -d "$dir/example" ]; then
    (cd "$dir/example" && flutter pub get >/dev/null) || { echo "FAILED: pub get $pkg/example"; status=1; }
  fi

  step "format $pkg"  dart format --output=none --set-exit-if-changed "$dir"
  step "analyze $pkg" bash -c "cd '$dir' && flutter analyze --no-pub"
  step "test $pkg"    bash -c "cd '$dir' && flutter test --no-pub --reporter=$reporter"

  if ! $fast; then
    dart pub global activate pana >/dev/null
    step "pana $pkg" bash -c "cd '$dir' && dart pub global run pana --exit-code-threshold 20 ."
  fi
done

[ "$status" -eq 0 ] && echo "OK: all checks passed."
exit "$status"
