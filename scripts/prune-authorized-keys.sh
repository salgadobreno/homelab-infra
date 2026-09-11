#!/usr/bin/env bash
#
# Reduce authorized_keys to the devices actually in use, by fingerprint.
#
#   ./scripts/prune-authorized-keys.sh            # show what would change
#   APPLY=yes ./scripts/prune-authorized-keys.sh  # write it
#
# No root needed: the operator owns the file. Pass KEYS= to work on another account.
#
# An allow-list, not a deny-list. The same key comes back with a different comment when
# it is re-installed from another machine, and a deny-list of today's comments would
# silently re-admit it. A fingerprint is the key itself.
#
# The fingerprints live in local.mk, which .gitignore covers, rather than here. They are
# not secret — a fingerprint is a hash of a public key — but this repository is public,
# and an inventory of exactly which devices hold access is a shape worth not publishing.
# See local.mk.example.
#
# Re-runnable. Backs the file up before writing and prints what is left.

set -euo pipefail

KEYS="${KEYS:-$HOME/.ssh/authorized_keys}"
STAMP="$(date +%Y%m%d-%H%M%S)"

# Resolve local.mk from this script's own location, so it works from any cwd.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_MK="${LOCAL_MK:-$HERE/../local.mk}"

# KEEP_FINGERPRINTS wins when set, so the Makefile can pass its own value and a test can
# supply a fixture. Otherwise read the one line out of local.mk.
KEEP=()
if [ -n "${KEEP_FINGERPRINTS:-}" ]; then
  read -r -a KEEP <<< "$KEEP_FINGERPRINTS" || true
  SOURCE_DESC="the KEEP_FINGERPRINTS environment variable"
elif [ -r "$LOCAL_MK" ]; then
  # `|| true` because pipefail makes a non-matching grep fatal, and a local.mk without
  # the line is a case the emptiness check below reports properly.
  line="$(grep -E '^[[:space:]]*SSH_KEEP_FINGERPRINTS[[:space:]]*\??=' "$LOCAL_MK" | tail -1 || true)"
  read -r -a KEEP <<< "${line#*=}" || true
  SOURCE_DESC="$LOCAL_MK"
else
  echo "error: no fingerprints — $LOCAL_MK is missing." >&2
  echo "       Copy local.mk.example to local.mk and fill it in." >&2
  exit 1
fi

# An empty or mangled allow-list matches nothing, and matching nothing means removing
# every key. Refuse both rather than discover it from the output.
if [ "${#KEEP[@]}" -eq 0 ]; then
  echo "error: $SOURCE_DESC defines no SSH_KEEP_FINGERPRINTS." >&2
  exit 1
fi
for k in "${KEEP[@]}"; do
  case "$k" in
    SHA256:?*) ;;
    *) echo "error: not a SHA256 fingerprint in $SOURCE_DESC: '$k'" >&2; exit 1 ;;
  esac
done
echo "keep-list: ${#KEEP[@]} fingerprint(s) from $SOURCE_DESC"

[ -r "$KEYS" ] || { echo "error: cannot read $KEYS" >&2; exit 1; }
[ -w "$KEYS" ] || { echo "error: cannot write $KEYS — run as its owner" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
KEPT="$TMP/kept"
: > "$KEPT"

kept=0
dropped=0
echo "--- $KEYS ---"
n=0
while IFS= read -r line; do
  # Blank lines and comments carry no credential; drop them silently.
  case "$line" in ''|'#'*) continue ;; esac
  n=$((n + 1))

  printf '%s\n' "$line" > "$TMP/one.pub"
  # A line sshd cannot parse authorises nobody, but removing it silently would hide a
  # corrupted file. Report it and drop it.
  if ! info="$(ssh-keygen -lf "$TMP/one.pub" 2>/dev/null)"; then
    echo "  DROP  #$n  unparseable line"
    dropped=$((dropped + 1))
    continue
  fi

  fp="$(printf '%s\n' "$info" | awk '{print $2}')"
  comment="$(printf '%s\n' "$info" | cut -d' ' -f3-)"

  keep=no
  for k in "${KEEP[@]}"; do
    [ "$fp" = "$k" ] && keep=yes && break
  done

  if [ "$keep" = yes ]; then
    echo "  KEEP  #$n  $comment"
    printf '%s\n' "$line" >> "$KEPT"
    kept=$((kept + 1))
  else
    echo "  DROP  #$n  $comment"
    dropped=$((dropped + 1))
  fi
done < "$KEYS"

echo
echo "$kept to keep, $dropped to remove"

# The same guard harden-sshd.sh uses: never leave an account with no way in.
if [ "$kept" -eq 0 ]; then
  echo "error: that would remove every key and lock this account out. Nothing written." >&2
  exit 1
fi

# A key in the keep-list that is not present means this ran against the wrong account,
# or a device was already removed. Worth saying before writing.
for k in "${KEEP[@]}"; do
  grep -qF "$k" <(while IFS= read -r l; do
      printf '%s\n' "$l" > "$TMP/c.pub"
      ssh-keygen -lf "$TMP/c.pub" 2>/dev/null | awk '{print $2}'
    done < "$KEPT") || echo "WARNING: keep-list fingerprint not found in the file: $k"
done

if [ "${APPLY:-}" != "yes" ]; then
  echo
  echo "nothing written. Re-run with APPLY=yes to apply:"
  echo "    APPLY=yes $0"
  exit 0
fi

BACKUP="${KEYS}.${STAMP}.bak"
cp -a "$KEYS" "$BACKUP"
chmod 600 "$BACKUP"
echo "backed up to $BACKUP"

cat "$KEPT" > "$KEYS"
chmod 600 "$KEYS"
echo "$KEYS now holds $(grep -c '^[^#]' "$KEYS") key(s)"

echo
echo "verify:      make check-tunnel-ssh"
echo "revert with: cp -a $BACKUP $KEYS"
