#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}/.."

if [[ $# -ne 0 ]]; then
  echo "Usage: Scripts/test-with-coverage.sh (optional SWIFTPM_BUILD_SYSTEM=native|swiftbuild|xcode)" >&2
  exit 1
fi

SWIFT_COMMAND=(swift test)
COVERAGE_COMMAND=("${SCRIPT_DIR}/check-coverage.sh")
if [[ -n "${SWIFTPM_BUILD_SYSTEM:-}" ]]; then
  case "${SWIFTPM_BUILD_SYSTEM}" in
    native|swiftbuild|xcode)
      SWIFT_COMMAND+=(--build-system "${SWIFTPM_BUILD_SYSTEM}")
      COVERAGE_COMMAND+=(--build-system "${SWIFTPM_BUILD_SYSTEM}")
      ;;
    *) echo "Unsupported SWIFTPM_BUILD_SYSTEM" >&2; exit 1 ;;
  esac
fi

# A new scratch path prevents profiles/products from older targets or runs being reused.
RUN_ID="$(python3 -c 'import uuid; print(uuid.uuid4().hex)')"
BUILD_PATH=".build/coverage-runs/${RUN_ID}"
mkdir -p .build/coverage-runs
mkdir "${BUILD_PATH}"
echo "Coverage build path: ${BUILD_PATH}"
"${SWIFT_COMMAND[@]}" --scratch-path "${BUILD_PATH}" --enable-code-coverage
"${COVERAGE_COMMAND[@]}" --build-path "${BUILD_PATH}"
