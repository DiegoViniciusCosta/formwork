#!/usr/bin/env bash
# Enforces commandment 1 (agnostic of design system and state management).
# See PRINCIPLES.md. Run from anywhere; exits non-zero on any violation.
set -uo pipefail
cd "$(dirname "$0")/.."

pkg=packages/formwork
fail=0

error() { echo "ERROR: $1"; fail=1; }

# 1. The core is pure Dart: no Flutter, no dart:ui.
if grep -rnE "^import '(package:flutter/|dart:ui)" "$pkg/lib/src/core"; then
  error "lib/src/core must not import Flutter or dart:ui."
fi

# 2. The main package renders no design system: widgets only.
if grep -rnE "^import 'package:flutter/(material|cupertino)\.dart'" "$pkg/lib"; then
  error "formwork must not import material or cupertino. Put visual kits in satellite packages."
fi

# 3. No runtime dependency besides the Flutter SDK.
deps=$(awk '
  /^dependencies:/ { in_deps = 1; next }
  /^[^ #]/         { in_deps = 0 }
  in_deps && /^  [a-z_]+:/ { sub(":", "", $1); print $1 }
' "$pkg/pubspec.yaml")
extra=$(echo "$deps" | grep -vx flutter || true)
if [ -n "$extra" ]; then
  error "formwork has unexpected dependencies: $(echo $extra)"
fi

if [ "$fail" -eq 0 ]; then echo "OK: principles check passed."; fi
exit "$fail"
