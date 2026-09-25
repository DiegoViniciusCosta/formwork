#!/usr/bin/env bash
# Enforces principle 1 (agnostic of design system, state management, and
# of how forms are defined). See PRINCIPLES.md and design doc 0007. Run
# from anywhere; exits non-zero on any violation.
set -uo pipefail
cd "$(dirname "$0")/.."

core=packages/formwork_core
pkg=packages/formwork
fail=0

error() { echo "ERROR: $1"; fail=1; }

# Prints the names under `dependencies:` in a pubspec.yaml.
runtime_deps() {
  awk '
    /^dependencies:/ { in_deps = 1; next }
    /^[^ #]/         { in_deps = 0 }
    in_deps && /^  [a-z_]+:/ { sub(":", "", $1); print $1 }
  ' "$1"
}

# 1. The core is pure Dart: no Flutter, no dart:ui, in code or pubspec.
if grep -rnE "^import '(package:flutter/|package:flutter_test/|dart:ui)" "$core/lib" "$core/test"; then
  error "formwork_core must not import Flutter or dart:ui."
fi
if grep -nE "flutter" "$core/pubspec.yaml"; then
  error "formwork_core must not depend on Flutter in pubspec.yaml: a Dart backend could not use it."
fi

# 2. The core has no runtime dependency at all.
extra=$(runtime_deps "$core/pubspec.yaml")
if [ -n "$extra" ]; then
  error "formwork_core has unexpected dependencies: $(echo $extra)"
fi

# 3. JSON is one front door: the engine imports nothing from the catalog,
#    directly or through the package's own library, which exports it.
if grep -rnE "^(import|export) ['\"](\.\./catalog/|\.\./\.\./formwork_core\.dart|package:formwork_core/)" "$core/lib/src/engine"; then
  error "formwork_core/lib/src/engine must not import src/catalog."
fi

# 4. The main package renders no design system: widgets only.
if grep -rnE "^import 'package:flutter/(material|cupertino)\.dart'" "$pkg/lib"; then
  error "formwork must not import material or cupertino. Put visual kits in satellite packages."
fi

# 5. No runtime dependency besides the Flutter SDK and formwork's own packages.
extra=$(runtime_deps "$pkg/pubspec.yaml" | grep -vxE "flutter|formwork_core" || true)
if [ -n "$extra" ]; then
  error "formwork has unexpected dependencies: $(echo $extra)"
fi

if [ "$fail" -eq 0 ]; then echo "OK: principles check passed."; fi
exit "$fail"
