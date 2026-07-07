#!/usr/bin/env bash
set -euo pipefail

THRESHOLD="${COVERAGE_THRESHOLD:-80}"

if ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun is required for coverage checks" >&2
  exit 1
fi

PROFILE="$(find .build -path '*codecov/default.profdata' -o -name default.profdata | head -1)"
TEST_BINARY="$(find .build -path '*.xctest/Contents/MacOS/*PackageTests' -print -quit)"

if [[ -z "${PROFILE}" || -z "${TEST_BINARY}" ]]; then
  echo "Coverage data not found. Run: swift test --enable-code-coverage" >&2
  exit 1
fi

COVERAGE="$(xcrun llvm-cov report "${TEST_BINARY}" -instr-profile="${PROFILE}" Sources/AzCopyMacUICore | awk '/TOTAL/ { print $4 }' | tr -d '%')"

python3 - "$COVERAGE" "$THRESHOLD" <<'PY'
import sys
coverage = float(sys.argv[1])
threshold = float(sys.argv[2])
if coverage < threshold:
    print(f"Coverage {coverage:.2f}% is below required {threshold:.2f}%")
    sys.exit(1)
print(f"Coverage {coverage:.2f}% meets required {threshold:.2f}%")
PY
