#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}/.."

if [[ $# -ne 0 ]]; then
  echo "Usage: Scripts/release-preflight.sh" >&2
  exit 1
fi

python3 "${SCRIPT_DIR}/check-version.py"
python3 -B -m unittest discover -s Tests/Scripts -p 'test_*.py'
"${SCRIPT_DIR}/security-review.sh"
"${SCRIPT_DIR}/test-with-coverage.sh"
echo "release-preflight: passed (versions, script tests, security checks, Swift tests, core line coverage)"
