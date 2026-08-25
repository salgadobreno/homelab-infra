#!/usr/bin/env bash
# Fail if the committed page disagrees with the cluster.
#
# This is the check that makes static content safe. The page can be wrong — it
# is a file, and files go stale — but it cannot be wrong and green, because the
# only way to be green is to match what the generator would produce now.
#
# It is also the first check here that fails because the world moved rather than
# because the repository did. See design D2.
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
committed="$repo_root/k8s/site/content/index.html"

[ -f "$committed" ] || {
    echo "FAIL: ${committed#$repo_root/} does not exist — run 'make diagram'" >&2
    exit 1
}

fresh="$(mktemp)"; trap 'rm -f "$fresh"' EXIT
"$repo_root/scripts/generate-diagram.sh" "$fresh" >/dev/null || {
    echo "FAIL: could not regenerate from the cluster — see above" >&2
    exit 1
}

if diff -u "$committed" "$fresh" > /dev/null; then
    echo "OK: the page agrees with the cluster"
    exit 0
fi

echo "FAIL: the page and the cluster disagree." >&2
echo "      - committed  + what the cluster says now" >&2
echo >&2
diff -u --label committed --label cluster "$committed" "$fresh" | sed -n '3,$p' | grep -E '^[-+]' >&2
echo >&2
echo "Fix with 'make diagram', then commit. Do not edit the file." >&2
exit 1
