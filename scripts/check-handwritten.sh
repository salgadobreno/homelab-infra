#!/usr/bin/env bash
# Fail if hand-written served content names a technology.
#
# This is the enforceable form of "a hand-written description cannot be served".
# diagram.ascii named three technologies that did not exist in the system and
# nothing went red, because nothing was measuring the claim. The fix is not to
# be careful: it is to make the claim impossible to write in a file that no
# check covers.
#
# machine.html is exempt — every technology it names was read from the cluster
# and is covered by check-diagram. replaced.html is exempt — it is labelled as
# history, describes a system that no longer exists, and is covered by D5.
# Everything else served has to stay out of the business of describing the
# system.
#
# HTML comments are stripped before scanning: the served-by marker exists for
# check-site, not for a reader.
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
content="$repo_root/k8s/site/content"
exempt_regex='(machine|replaced)\.html$'

terms='kubernetes|k3s|k8s|argo ?cd|argo|traefik|nginx|docker|compose|redis|proxmox|containerd|helm|terraform|opentofu|cloudflare|kubectl|cluster|node'

rc=0 scanned=0
while IFS= read -r f; do
    [[ "$f" =~ $exempt_regex ]] && continue
    scanned=$((scanned + 1))
    hits="$(sed 's/<!--.*-->//g' "$f" | grep -nEio -- "$terms" | sort -u -t: -k2 || true)"
    if [ -n "$hits" ]; then
        echo "  ${f#$repo_root/} names:" >&2
        printf '%s\n' "$hits" | sed 's/^/    line /' >&2
        rc=1
    fi
done < <(find "$content" -type f -name '*.html' | sort)

if [ $rc -ne 0 ]; then
    echo "FAIL: hand-written served content describes the system." >&2
    echo "      Nothing checks these claims, which is how diagram.ascii stayed" >&2
    echo "      wrong. Move the claim into the generated page, or remove it." >&2
    exit 1
fi
echo "OK: $scanned hand-written page(s) make no claim about the system"
