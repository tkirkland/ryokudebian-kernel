#!/bin/bash
# Keep the newest $KEEP releases of one variant (current + previous, for
# rollback) and delete the rest with their git tags. Run only after <rel> was
# published; refuses unless <rel> lists <n> uploaded assets, so a failed
# build never prunes.
# Usage: prune.sh <rel> <n>  |  prune.sh --variant <tag>  |  prune.sh --sortkey <tag>
set -euo pipefail
KEEP=${KEEP:-2}

# Variant, regardless of version numbers: trixie's 6.12 line, or the newest
# line (7.x today, 8.x later; a new major must not strand the old ones).
variant() { [[ $1 == 6.12[.-]* ]] && echo 6.12 || echo newest; }

# Version-ordered sort key: labels dropped, a missing Debian revision counts
# as -0, so old-style 6.12.113-zfs-* sorts below 6.12.113-1-zfs-*.
sortkey() {
  local t=${1%%-zfs-*} z=${1#*-zfs-}
  t=$(sed -E 's/[A-Za-z]+-?//g; s/-$//' <<<"$t")
  [[ $t =~ -[0-9]+$ ]] || t+=-0
  echo "$t-zfs-$z"
}
case ${1-} in
  --variant) variant "$2"; exit ;;
  --sortkey) sortkey "$2"; exit ;;
esac

rel=$1 want=$2
have=$(gh release view "$rel" --json assets -q '.assets | map(select(.state == "uploaded")) | length')
[[ $have -eq $want ]] || { echo "$rel has $have/$want assets, not pruning" >&2; exit 1; }
v=$(variant "$rel")
gh release list --limit 200 --json tagName -q '.[].tagName' | grep -- '-zfs-' |
  while read -r t; do [[ $(variant "$t") == "$v" ]] && printf '%s\t%s\n' "$(sortkey "$t")" "$t"; done |
  sort -t$'\t' -k1,1rV | cut -f2 | tail -n +"$((KEEP + 1))" |
  while read -r old; do
    echo "deleting $old (variant $v keeps $KEEP)"
    gh release delete "$old" --cleanup-tag -y
  done
