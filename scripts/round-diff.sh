#!/bin/sh
# List files the last push changed outside any finding's scope.
# Usage: sh scripts/round-diff.sh <state-dir>
set -eu

dir=${1:?usage: round-diff.sh <state-dir>}
worktree="$dir/worktree"
[ -f "$dir/meta.txt" ] && [ -d "$worktree" ] || {
	echo "round-diff: no worktree in $dir" >&2
	exit 1
}
prev_head=$(sed -n 's/^prev_head //p' "$dir/meta.txt")
head_sha=$(sed -n 's/^head_sha //p' "$dir/meta.txt")
if [ -z "$prev_head" ]; then
	echo "round-diff: no push recorded yet"
	exit 0
fi

expected=$(mktemp "$dir/.round-diff.XXXXXX")
changed=$(mktemp "$dir/.round-diff.XXXXXX")
trap 'rm -f "$expected" "$changed"' EXIT

for record in "$dir/findings"/F*; do
	[ -f "$record" ] || continue
	sed -n 's/^path: //p' "$record"
done | sort -u >"$expected"
git -C "$worktree" diff --name-only "$prev_head" "$head_sha" | sort -u >"$changed"

unexpected=$(grep -vxF -f "$expected" "$changed" || true)
if [ -n "$unexpected" ]; then
	printf '%s\n' "$unexpected" | sed 's/^/unexpected /'
	exit 3
fi
echo "round-diff: clean"
