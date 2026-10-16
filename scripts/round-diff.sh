#!/bin/sh
# List files the last push changed outside any finding's scope.
# Usage: sh scripts/round-diff.sh <state-dir> [--all [<base-sha>]]
# With --all every file changed in prev_head..head_sha is listed, finding
# paths included; "clean" then means the range is empty. prev_head moves on
# every push, so after several pushes pass the head the first one started
# from as <base-sha> to cover them all.
set -eu

dir=${1:?usage: round-diff.sh <state-dir> [--all [<base-sha>]]}
all=0
base=""
case "${2:-}" in
'') ;;
--all)
	all=1
	base=${3:-}
	;;
*)
	echo "round-diff: unknown argument: $2" >&2
	exit 1
	;;
esac
worktree="$dir/worktree"
[ -f "$dir/meta.txt" ] && [ -d "$worktree" ] || {
	echo "round-diff: no worktree in $dir" >&2
	exit 1
}
prev_head=$(sed -n 's/^prev_head //p' "$dir/meta.txt")
head_sha=$(sed -n 's/^head_sha //p' "$dir/meta.txt")
[ -z "$base" ] || prev_head=$base
if [ -z "$prev_head" ]; then
	echo "round-diff: no push recorded yet"
	exit 0
fi

expected=$(mktemp "$dir/.round-diff.XXXXXX")
changed=$(mktemp "$dir/.round-diff.XXXXXX")
raw=$(mktemp "$dir/.round-diff.XXXXXX")
trap 'rm -f "$expected" "$changed" "$raw"' EXIT

for record in "$dir/findings"/F*; do
	[ -f "$record" ] || continue
	sed -n '/^---$/q; s/^path: //p' "$record"
done | sort -u >"$expected"
git -C "$worktree" diff --name-only "$prev_head" "$head_sha" >"$raw" || {
	echo "round-diff: cannot diff $prev_head and $head_sha" >&2
	exit 1
}
sort -u "$raw" >"$changed"

if [ "$all" -eq 1 ]; then
	unexpected=$(cat "$changed")
else
	unexpected=$(grep -vxF -f "$expected" "$changed" || true)
fi
if [ -n "$unexpected" ]; then
	printf '%s\n' "$unexpected" | sed 's/^/unexpected /'
	exit 3
fi
echo "round-diff: clean"
