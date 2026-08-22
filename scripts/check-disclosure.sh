#!/usr/bin/env bash
# Assert that nothing served from the site crosses the disclosure boundary.
#
# The boundary lives in scripts/disclosure-rules, not here. This script only
# applies it. Reads no credentials, touches no cluster, needs no root.
#
#   check-disclosure.sh [path ...]   scan files (default: k8s/site/content)
#   check-disclosure.sh --selftest   prove each rule fires on a fixture
#
# Exit 0 clean, 1 on a violation or a broken rule file.
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rules_file="$repo_root/scripts/disclosure-rules"
default_target="$repo_root/k8s/site/content"

[ -r "$rules_file" ] || { echo "FAIL: cannot read $rules_file" >&2; exit 1; }

labels=() patterns=()
while IFS= read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    labels+=("${line%%|*}")
    patterns+=("${line#*|}")
done < "$rules_file"

[ "${#patterns[@]}" -gt 0 ] || { echo "FAIL: $rules_file defines no rules" >&2; exit 1; }

# Scan one file against every rule. Prints violations, returns 1 if any.
scan_file() {
    local file="$1" i found=0
    for i in "${!patterns[@]}"; do
        local hits
        hits="$(grep -nE -- "${patterns[$i]}" "$file" 2>/dev/null)" || continue
        while IFS= read -r hit; do
            [ -n "$hit" ] || continue
            # Print the line number and rule, never the matched text — echoing a
            # leaked value into a log is the disclosure happening again.
            printf '  %s:%s  %s\n' "${file#$repo_root/}" "${hit%%:*}" "${labels[$i]}"
            found=1
        done <<< "$hits"
    done
    return $found
}

selftest() {
    # A check never seen to fail is not a check. Every rule gets a fixture that
    # must trip it; a rule that stops matching its own example is a broken rule,
    # not a clean scan.
    local tmp rc=0 i
    tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
    local fixtures=(
        '192.168.0.30'
        'token lives in /etc/cloudflared/token'
        'provisioned by terraform@pve!tofu'
        'ssh buzaga@pve'
        'site-7d4b9c8f5a-x2k9p'
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9zz'
    )
    [ "${#fixtures[@]}" -eq "${#patterns[@]}" ] || {
        echo "FAIL: ${#patterns[@]} rules but ${#fixtures[@]} fixtures — every rule needs one" >&2
        return 1
    }
    for i in "${!patterns[@]}"; do
        printf '%s\n' "${fixtures[$i]}" > "$tmp/fixture"
        if grep -qE -- "${patterns[$i]}" "$tmp/fixture"; then
            printf 'OK: rule fires   %s\n' "${labels[$i]}"
        else
            printf 'FAIL: rule never fires on its own fixture: %s\n' "${labels[$i]}" >&2
            rc=1
        fi
    done
    # And the inverse: a clean page must pass, or the check is just noise.
    printf '<p>k3s-server-1 Ready v1.36.3+k3s1 4 vCPU 5.8 GiB</p>\n' > "$tmp/clean"
    if scan_file "$tmp/clean" >/dev/null; then
        printf 'OK: a clean page passes\n'
    else
        printf 'FAIL: a clean page was rejected — the rules are too broad\n' >&2
        scan_file "$tmp/clean" >&2
        rc=1
    fi
    [ $rc -eq 0 ] && echo "OK: ${#patterns[@]} rules, each seen to fail and to pass"
    return $rc
}

[ "${1:-}" = "--selftest" ] && { selftest; exit $?; }

targets=("$@")
[ "${#targets[@]}" -eq 0 ] && targets=("$default_target")

files=() rc=0
for t in "${targets[@]}"; do
    if [ -d "$t" ]; then
        while IFS= read -r f; do files+=("$f"); done < <(find "$t" -type f | sort)
    elif [ -f "$t" ]; then
        files+=("$t")
    fi
    # A path that does not exist is not a failure: the hook passes file paths
    # that may have been deleted, and group 3 has not created the fragment yet.
done

[ "${#files[@]}" -eq 0 ] && { echo "OK: nothing to scan"; exit 0; }

for f in "${files[@]}"; do
    scan_file "$f" || rc=1
done

if [ $rc -ne 0 ]; then
    echo "FAIL: content above crosses the disclosure boundary (scripts/disclosure-rules)" >&2
    exit 1
fi
echo "OK: ${#files[@]} file(s) inside the disclosure boundary"
