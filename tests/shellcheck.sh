#!/bin/bash
# Lint every shell script in the repo with shellcheck and shfmt.
# Exits non-zero on any finding.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

mapfile -t scripts < <(
    find autorun bin tests -type f \( -name '*.sh' -o -name 'autorun*' \) \
        ! -name 'lib.sh' -print
    # lib.sh is sourced, not executed; lint it explicitly with --shell=bash
    echo "autorun/lib.sh"
)

echo "==> shellcheck on ${#scripts[@]} scripts"
shellcheck --severity=warning --shell=bash "${scripts[@]}"

if command -v shfmt > /dev/null; then
    echo "==> shfmt -d -i 4 -ci -bn"
    shfmt -d -i 4 -ci -bn "${scripts[@]}"
else
    echo "WARN: shfmt not installed; skipping format check"
fi

echo "==> all green"
