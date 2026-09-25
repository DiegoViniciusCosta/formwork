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

# Prints " name version" for each sibling package that $1 depends on and
# whose version (the one in the sibling's own pubspec.yaml) is not on
# pub.dev. Only a 404 counts: if pub.dev cannot be reached, pana runs and
# reports the problem itself.
unpublished_siblings() {
  local deps dep version code
  deps=$(awk '
    /^dependencies:/ { in_deps = 1; next }
    /^[^ #]/         { in_deps = 0 }
    in_deps && /^  [a-z_]+:/ { sub(":", "", $1); print $1 }
  ' "$1/pubspec.yaml")
  for dep in $deps; do
    [ -f "packages/$dep/pubspec.yaml" ] || continue
    version=$(awk '/^version:/ { print $2 }' "packages/$dep/pubspec.yaml")
    code=$(curl -s -o /dev/null -w '%{http_code}' \
      "https://pub.dev/api/packages/$dep/versions/$version")
    [ "$code" = 404 ] && printf ' %s %s' "$dep" "$version"
  done
}

step "principles" bash tool/check_principles.sh

for dir in packages/*/; do
  pkg=$(basename "$dir")
  # Pure Dart packages (formwork_core) are checked with dart alone, which
  # proves a Dart backend can use them without Flutter.
  if grep -qE '^ +sdk: flutter' "$dir/pubspec.yaml"; then
    tool=flutter
  else
    tool=dart
  fi
  (cd "$dir" && $tool pub get >/dev/null) || { echo "FAILED: pub get $pkg"; status=1; continue; }
  example="$dir/example"
  if [ -d "$example" ]; then
    (cd "$example" && flutter pub get >/dev/null) || { echo "FAILED: pub get $pkg/example"; status=1; }
  fi

  step "format $pkg"  dart format --output=none --set-exit-if-changed "$dir"
  if [ "$tool" = flutter ]; then
    step "analyze $pkg" bash -c "cd '$dir' && flutter analyze --no-pub"
    step "test $pkg"    bash -c "cd '$dir' && flutter test --no-pub --reporter=$reporter"
  else
    step "analyze $pkg" bash -c "cd '$dir' && dart analyze --fatal-infos"
    step "test $pkg"    bash -c "cd '$dir' && dart test --reporter=$reporter"
    # A pure Dart example is a script: running it proves it still works.
    for script in "$dir"example/*.dart; do
      [ -f "$script" ] || continue
      step "run $pkg/example/$(basename "$script")" \
        bash -c "cd '$dir' && dart run 'example/$(basename "$script")' >/dev/null"
    done
  fi
  # The example is documentation that runs: its tests guard the scenarios.
  if [ -d "$example/test" ]; then
    step "test $pkg/example" bash -c "cd '$example' && flutter test --no-pub --reporter=$reporter"
  fi

  if ! $fast; then
    # pana scores the package as pub.dev would, so it ignores
    # pubspec_overrides.yaml and cannot resolve a sibling that is not
    # published yet. Skip it until every sibling's version is on pub.dev.
    missing=$(unpublished_siblings "$dir")
    if [ -n "$missing" ]; then
      echo "==> pana $pkg"
      echo "SKIPPED: not on pub.dev yet:$missing"
    else
      dart pub global activate pana >/dev/null
      step "pana $pkg" bash -c "cd '$dir' && dart pub global run pana --exit-code-threshold 20 ."
    fi
  fi
done

[ "$status" -eq 0 ] && echo "OK: all checks passed."
exit "$status"
