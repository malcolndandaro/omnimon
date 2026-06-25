#!/usr/bin/env bash
# Run all Omnimon tests. Seam 2 always runs; Seam 1 runs where Docker exists.
set -uo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"

rc=0
bash "$here/config_test.sh" || rc=1
echo
bash "$here/smoke_test.sh" || rc=1
exit "$rc"
