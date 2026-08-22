#!/usr/bin/env bash
# PostToolUse hook: refuse a write under k8s/site/ that crosses the disclosure
# boundary, at the write rather than at the next `make check`.
#
# Placement is the whole point. `make check` catches a leaked value after it is
# committed, and only if someone runs it. Publication is irreversible in the way
# a credential read is irreversible — a value withdrawn afterwards has still been
# served. See LEARNINGS/practice/301-guardrails-arrive-too-late.md.
#
# Reads the hook payload on stdin. Exit 2 puts the failure in front of the agent
# as feedback it has to deal with; exit 0 is silent.
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

payload="$(cat)"
file_path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"

# Bash can write files too — heredocs, sed -i, redirection — and a hook that
# only watches Write/Edit would be a guardrail on the tool rather than on the
# boundary. When there is no file path to inspect, scan the whole served
# directory instead. It is one grep over one small tree.
if [ -z "$file_path" ]; then
    output="$("$repo_root/scripts/check-disclosure.sh" 2>&1)" && exit 0
else
    case "$file_path" in
        "$repo_root"/k8s/site/*|k8s/site/*) ;;
        *) exit 0 ;;
    esac
    [ -f "$file_path" ] || exit 0
    output="$("$repo_root/scripts/check-disclosure.sh" "$file_path" 2>&1)" && exit 0
fi

# Fail closed. If the checker could not run, that is a reason to stop, not to
# wave the write through.
{
    echo "Disclosure boundary: this write is not allowed to be committed as-is."
    echo "$output"
    echo
    echo "The boundary is scripts/disclosure-rules. Remove the value, or change"
    echo "the rule deliberately — do not work around the check."
} >&2
exit 2
