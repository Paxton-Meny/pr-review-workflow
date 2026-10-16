#!/bin/sh
# Compare what landed on the base branch since the review against the
# reviewed hunks, so a merge never lands over code the review never saw.
# Usage: sh scripts/base-drift.sh <state-dir>
#
# Fetches the base, takes the merge base of the reviewed head and the
# base branch, and lists the files the commits between them changed.
# Those that this pull request also changes (lockfiles and generated
# output aside) are compared hunk by hunk in the merge base's own
# coordinates, which both diffs share, so an intersection is exact.
# Writes pr-context/drift.txt (facts, per-file lines, level; a base read
# from an earlier fetch records nothing), and when
# any hunk is near or same, pr-context/overlap/base/ with ours.diff
# (the annotated per-file diffs), theirs.diff (the landed diff for the
# shared files), and summary.txt, for a person or the comparer to read.
# Prints one line, plus one "drift" line per near or same file:
#   base-drift: <n> commits landed, <k> files shared, level <level>
# Exit 0 when the level is none or disjoint, 5 when it is near or same,
# the base cannot be read, or it was read from an earlier fetch, and 1 on a
# broken ledger.
set -eu

dir=${1:?usage: base-drift.sh <state-dir>}
[ -f "$dir/meta.txt" ] || {
	echo "base-drift: no meta.txt in $dir" >&2
	exit 1
}
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ctx="$dir/pr-context"
[ -f "$ctx/diff.patch" ] && [ -f "$ctx/files.txt" ] || {
	echo "base-drift: no fetched diff in $ctx, run fetch-pr.sh first" >&2
	exit 1
}
repo_root=$(sed -n 's/^repo_root //p' "$dir/meta.txt")
base_branch=$(sed -n 's/^base_branch //p' "$dir/meta.txt")
head_sha=$(sed -n 's/^head_sha //p' "$dir/meta.txt")
snapshot=$(sed -n 's/^base_sha //p' "$dir/meta.txt")
[ -n "$repo_root" ] && [ -d "$repo_root" ] && [ -n "$base_branch" ] && [ -n "$head_sha" ] || {
	echo "base-drift: meta.txt names no clone, base branch, or head; run checkout-pr.sh first" >&2
	exit 1
}

mode=$(sh "$here/setting.sh" "$dir" overlap_check)
if [ "$mode" = off ]; then
	echo "base-drift: overlap check off"
	exit 0
fi

# drift.txt describes this attempt only; an earlier one must not be read
# as the answer to a base that cannot be read now.
rm -f "$ctx/drift.txt"

fetched=$(sh "$here/fetch-base.sh" "$repo_root" "$base_branch" 2>/dev/null) || fetched=''
case "$fetched" in
*" fresh") freshness='' ;;
*" stale") freshness=', base read from an earlier fetch' ;;
*)
	echo "base-drift: base $base_branch unreadable, so nothing landed there can be ruled out"
	exit 5
	;;
esac
base_now=$(git -C "$repo_root" rev-parse --verify --quiet "refs/remotes/origin/$base_branch") || {
	echo "base-drift: origin/$base_branch missing after the fetch"
	exit 5
}
mb=$(git -C "$repo_root" merge-base "$head_sha" "$base_now" 2>/dev/null) || {
	echo "base-drift: no merge base between the reviewed head and origin/$base_branch"
	exit 5
}
# When the branch was brought up to date since the review (its merge
# base now sits past the snapshot), the merge base hides what landed:
# compare from the snapshot instead, approximately, since the two diffs
# are then in different coordinates.
from=$mb
approx=''
if [ -n "$snapshot" ] && [ "$snapshot" != "$mb" ] &&
	git -C "$repo_root" merge-base --is-ancestor "$snapshot" "$mb" 2>/dev/null; then
	from=$snapshot
	approx=', approximate: the branch was brought up to date since the review'
fi
landed=$(git -C "$repo_root" rev-list --count "$from..$base_now")
aside=0

work=$(mktemp -d "$ctx/.drift.XXXXXX")
trap 'rm -rf "$work"' EXIT
out="$work/drift.txt"
{
	printf 'base %s\nmerge_base %s\nlanded_from %s\ncommits %s\n' "$base_now" "$mb" "$from" "$landed"
	[ -z "$snapshot" ] || printf 'snapshot %s\n' "$snapshot"
} >"$out"

finish() {
	# finish <level> <shared> [<extra lines>]
	printf 'level %s files %s\n' "$1" "$2" >>"$out"
	aside_note=''
	[ "$aside" -eq 0 ] || aside_note=", $aside docs or config set aside"
	summary="base-drift: $landed commits landed, $2 files shared${aside_note}, level $1$approx$freshness"
	# A base read from an earlier fetch cannot show whether it moved, so
	# no level there is recorded as a drift and no verdict can carry it.
	if [ -n "$freshness" ]; then
		echo "$summary"
		[ -z "${3:-}" ] || printf '%s\n' "$3"
		exit 5
	fi
	mv "$out" "$ctx/drift.txt"
	echo "$summary"
	[ -z "${3:-}" ] || printf '%s\n' "$3"
	case "$1" in
	near | same) exit 5 ;;
	esac
	exit 0
}

[ "$landed" -gt 0 ] || finish none 0

cut -f1 "$ctx/files.txt" | sort -u >"$work/ours.paths"
git -C "$repo_root" -c core.quotepath=off diff --no-ext-diff --no-textconv --no-color --no-renames --src-prefix=a/ --dst-prefix=b/ --name-only "$from" "$base_now" | sort -u >"$work/theirs.paths"
comm -12 "$work/ours.paths" "$work/theirs.paths" >"$work/shared.all"
sh "$here/split-diff.sh" --excluded <"$work/shared.all" >"$work/excluded" || true
grep -vxF -f "$work/excluded" "$work/shared.all" >"$work/shared.kept" || true
# Only code and tests count: a changelog or a dependency list is where
# every concurrent change meets, and a clash there is not a defect.
sh "$here/classify-change.sh" --classify <"$work/shared.kept" |
	awk -F '\t' '$1 == "code" || $1 == "tests" { print $2 }' >"$work/shared"
shared=$(grep -c . "$work/shared" || true)
aside=$(($(grep -c . "$work/shared.kept" || true) - shared))
[ "$shared" -gt 0 ] || finish none 0

# The user's diff config must not change what is read, so it is pinned.
# Both diffs against the merge base: ours is the forge's diff, theirs the
# landed commits restricted to the shared files.
tr '\n' '\0' <"$work/shared" | xargs -0 git -C "$repo_root" -c core.quotepath=off diff --no-ext-diff --no-textconv --no-color --no-renames --src-prefix=a/ --dst-prefix=b/ "$from" "$base_now" -- >"$work/theirs.diff"
sh "$here/hunk-ranges.sh" "$work/theirs.diff" >"$work/theirs.ranges"
sh "$here/hunk-ranges.sh" "$ctx/diff.patch" |
	awk -F '\t' 'NR == FNR { shared[$0] = 1; next } ($1 in shared)' "$work/shared" - >"$work/ours.ranges"
sh "$here/compare-hunks.sh" "$work/ours.ranges" "$work/theirs.ranges" >"$work/compare"
level=$(sed -n 's/^level \([a-z]*\) .*/\1/p' "$work/compare")
grep -v '^level ' "$work/compare" | awk -F '\t' '{ printf "file\t%s\t%s\t%s\t%s\t%s\n", $1, $2, $3, $4, $5 }' >>"$out"

lines=''
case "$level" in
near | same)
	lines=$(grep -v '^level ' "$work/compare" | awk -F '\t' '$1 == "near" || $1 == "same" {
		printf "drift %s %s ours %s theirs %s%s\n", $1, $2, $3, $4, ($5 == "" ? "" : " in " $5)
	}')
	# The bundle is rebuilt; a verdict stays, since it names the base it
	# judged and the merge gate checks that itself.
	label="$ctx/overlap/base"
	mkdir -p "$label"
	rm -f "$label/ours.diff" "$label/theirs.diff" "$label/summary.txt"
	cp "$work/theirs.diff" "$label/theirs.diff"
	: >"$label/ours.diff"
	while IFS= read -r path; do
		num=$(awk -F '\t' -v p="$path" '$2 == p { print $1; exit }' "$ctx/diff-index.txt" 2>/dev/null || true)
		[ -n "$num" ] && [ -f "$ctx/files/$num.diff" ] || continue
		cat "$ctx/files/$num.diff" >>"$label/ours.diff"
		printf '\n' >>"$label/ours.diff"
	done <"$work/shared"
	{
		printf 'label base\nbase %s\nmerge_base %s\ncommits %s\n' "$base_now" "$mb" "$landed"
		cat "$work/compare"
	} >"$label/summary.txt"
	;;
esac
finish "$level" "$shared" "$lines"
