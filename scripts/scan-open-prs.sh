#!/bin/sh
# Find open pull requests whose hunks touch this one's, before the review
# is paid for.
# Usage: sh scripts/scan-open-prs.sh <state-dir>
#
# One gh call lists the open pull requests on the same base with their
# files; this pull request, pull requests stacked on it or under it, and
# files the split excludes (lockfiles, generated output) are dropped.
# The MAX_CANDIDATES sharing the most files are fetched and compared
# hunk by hunk. Each diff is against its own merge base, so the
# comparison is approximate; the near tolerance covers ordinary drift.
# Writes pr-context/overlap.txt and, for each near or same candidate, a
# bundle under pr-context/overlap/pr-<n>/ (ours.diff, theirs.diff,
# summary.txt) for a person or the comparer. Prints one summary line,
# preceded by one "candidate" line per near or same pull request:
#   candidate <n> by <login> <level> files <k>[ draft][ same-author][ linked]
#   overlap: <c> candidates, <x> near, <y> same, approximate
# "linked" means one description names the other: a stack, a
# supersession, or a known pairing, reported but never asked about. A
# listing that fails prints a line saying so and exits 0: this scan is
# advisory and never blocks a review. Off under the overlap_check setting.
set -eu

MAX_CANDIDATES=5
LIST_LIMIT=100

dir=${1:?usage: scan-open-prs.sh <state-dir>}
[ -f "$dir/meta.txt" ] || {
	echo "scan-open-prs: no meta.txt in $dir" >&2
	exit 1
}
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ctx="$dir/pr-context"
[ -f "$ctx/diff.patch" ] && [ -f "$ctx/files.txt" ] || {
	echo "scan-open-prs: no fetched diff in $ctx, run fetch-pr.sh first" >&2
	exit 1
}
owner=$(sed -n 's/^owner //p' "$dir/meta.txt")
repo=$(sed -n 's/^repo //p' "$dir/meta.txt")
pr=$(sed -n 's/^pr //p' "$dir/meta.txt")
author=$(sed -n 's/^author //p' "$dir/meta.txt")
base_branch=$(sed -n 's/^base_branch //p' "$dir/meta.txt")
head_branch=$(sed -n 's/^head_branch //p' "$dir/meta.txt")
cross_repo=$(sed -n 's/^cross_repo //p' "$dir/meta.txt")
[ -n "$owner" ] && [ -n "$repo" ] && [ -n "$pr" ] || {
	echo "scan-open-prs: meta.txt in $dir is incomplete" >&2
	exit 1
}

mode=$(sh "$here/setting.sh" "$dir" overlap_check)
if [ "$mode" = off ]; then
	echo "scan-open-prs: overlap check off"
	exit 0
fi

work=$(mktemp -d "$ctx/.scan.XXXXXX")
trap 'rm -rf "$work"' EXIT
rm -f "$ctx/overlap.txt"
for old in "$ctx"/overlap/pr-*; do
	[ -d "$old" ] && rm -rf "$old"
done

# One line per pull request, then one per file; the descriptions never
# touch the disk, only whether they name this pull request does.
mention="(^|[^0-9#])#$pr([^0-9]|\$)"
if ! gh pr list --repo "$owner/$repo" --state open --limit "$LIST_LIMIT" \
	--json number,author,isDraft,baseRefName,headRefName,updatedAt,isCrossRepository,files,title,body \
	--jq ".[] | \"pr \\(.number)\\t\\(.author.login)\\t\\(.isDraft)\\t\\(.baseRefName)\\t\\(.headRefName)\\t\\(.updatedAt)\\t\\(((.title // \"\") + \" \" + (.body // \"\")) | test(\"$mention\"))\\t\\(.isCrossRepository)\", (.files[] | \"file \\(.path)\")" >"$work/list" 2>/dev/null; then
	printf 'overlap: unavailable\n' >"$ctx/overlap.txt"
	echo "scan-open-prs: could not list open pull requests for $owner/$repo; nothing compared"
	exit 0
fi
tr -d '\r' <"$work/list" >"$work/list.clean"

cut -f1 "$ctx/files.txt" | sort -u >"$work/ours.all"
{ cat "$work/ours.all"; sed -n 's/^file //p' "$work/list.clean"; } | sort -u |
	sh "$here/split-diff.sh" --excluded >"$work/excluded" || true
# Only code and tests count: a changelog or a dependency list is where
# every concurrent change meets, and a clash there is not a defect.
{ cat "$work/ours.all"; sed -n 's/^file //p' "$work/list.clean"; } | sort -u |
	sh "$here/classify-change.sh" --classify | awk -F '\t' '$1 == "code" || $1 == "tests" { print $2 }' >"$work/allowed"
grep -vxF -f "$work/excluded" "$work/ours.all" | grep -xF -f "$work/allowed" >"$work/ours.paths" || true

# Candidates: number, login, draft, updated, mentions-us, shared count.
awk -F '\t' -v me="$pr" -v base="$base_branch" -v head="$head_branch" -v mycross="$cross_repo" \
	-v ours="$work/ours.paths" -v excluded="$work/excluded" '
BEGIN {
	while ((getline l < ours) > 0) mine[l] = 1
	while ((getline l < excluded) > 0) skip[l] = 1
}
function flush() { if (num != "" && keep && shared > 0) printf "%s\t%s\t%s\t%s\t%s\t%d\n", num, login, draft, updated, mentions, shared }
/^pr / {
	flush()
	num = substr($1, 4); login = $2; draft = $3; theirbase = $4; theirhead = $5; updated = $6; mentions = $7; theirfork = $8
	shared = 0; split("", seen)
	keep = (num != me && theirbase == base && (mycross == "true" || theirbase != head) && (theirfork == "true" || theirhead != base))
	next
}
/^file / {
	p = substr($0, 6)
	if (keep && (p in mine) && !(p in skip) && !(p in seen)) { seen[p] = 1; shared++ }
}
END { flush() }
' "$work/list.clean" | sort -t "$(printf '\t')" -k6,6nr -k4,4r | head -n "$MAX_CANDIDATES" >"$work/candidates"

sh "$here/hunk-ranges.sh" "$ctx/diff.patch" >"$work/ours.ranges"
our_body_names() {
	# our_body_names <number>: this pull request's description names it
	[ -f "$ctx/body.txt" ] && grep -Eq "(^|[^0-9#])#$1([^0-9]|\$)" "$ctx/body.txt"
}

out="$work/overlap.txt"
: >"$out"
candidates=0 nears=0 sames=0
printed=''
while IFS="$(printf '\t')" read -r num login draft updated mentions shared; do
	[ -n "$num" ] || continue
	candidates=$((candidates + 1))
	flags=''
	[ "$draft" = true ] && flags="$flags draft"
	[ -n "$author" ] && [ "$login" = "$author" ] && flags="$flags same-author"
	if [ "$mentions" = true ] || our_body_names "$num"; then flags="$flags linked"; fi
	if ! gh pr diff "$num" --repo "$owner/$repo" >"$work/pr-$num.diff" 2>/dev/null; then
		printf 'candidate %s %s unavailable files %s%s\n' "$num" "$login" "$shared" "$flags" >>"$out"
		continue
	fi
	tr -d '\r' <"$work/pr-$num.diff" >"$work/pr-$num.clean"
	sh "$here/hunk-ranges.sh" "$work/pr-$num.clean" |
		awk -F '\t' 'NR == FNR { mine[$0] = 1; next } ($1 in mine)' "$work/ours.paths" - >"$work/pr-$num.ranges"
	sh "$here/compare-hunks.sh" "$work/ours.ranges" "$work/pr-$num.ranges" >"$work/pr-$num.compare"
	level=$(sed -n 's/^level \([a-z]*\) .*/\1/p' "$work/pr-$num.compare")
	printf 'candidate %s %s %s files %s%s\n' "$num" "$login" "$level" "$shared" "$flags" >>"$out"
	grep -v '^level ' "$work/pr-$num.compare" | awk -F '\t' -v n="$num" '{ printf "file\t%s\t%s\t%s\t%s\t%s\t%s\n", n, $1, $2, $3, $4, $5 }' >>"$out"
	case "$level" in
	near | same)
		[ "$level" = near ] && nears=$((nears + 1))
		[ "$level" = same ] && sames=$((sames + 1))
		printed="$printed$(printf 'candidate %s by %s %s files %s%s' "$num" "$login" "$level" "$shared" "$flags")
"
		bundle="$ctx/overlap/pr-$num"
		mkdir -p "$bundle"
		grep -v '^level ' "$work/pr-$num.compare" | cut -f2 | sort -u >"$work/pr-$num.shared"
		awk -v keep="$work/pr-$num.shared" '
		BEGIN { while ((getline l < keep) > 0) k[l] = 1 }
		/^diff --git / { on = 0; pending = 1; buf = $0 "\n"; old = ""; next }
		pending && /^--- / { old = $0; sub(/^--- /, "", old); sub(/^a\//, "", old); buf = buf $0 "\n"; next }
		pending && /^\+\+\+ / {
			p = $0; sub(/^\+\+\+ /, "", p); sub(/^b\//, "", p)
			if (p == "/dev/null") p = old
			on = (p in k); pending = 0
			if (on) printf "%s%s\n", buf, $0
			next
		}
		pending { buf = buf $0 "\n"; next }
		on { print }
		' "$work/pr-$num.clean" >"$bundle/theirs.diff"
		: >"$bundle/ours.diff"
		while IFS= read -r path; do
			n=$(awk -F '\t' -v p="$path" '$2 == p { print $1; exit }' "$ctx/diff-index.txt" 2>/dev/null || true)
			[ -n "$n" ] && [ -f "$ctx/files/$n.diff" ] || continue
			cat "$ctx/files/$n.diff" >>"$bundle/ours.diff"
			printf '\n' >>"$bundle/ours.diff"
		done <"$work/pr-$num.shared"
		{
			printf 'label pr-%s\npull_request %s\nauthor %s\nflags%s\n' "$num" "$num" "$login" "${flags:- none}"
			cat "$work/pr-$num.compare"
		} >"$bundle/summary.txt"
		;;
	esac
done <"$work/candidates"

summary="overlap: $candidates candidates, $nears near, $sames same, approximate"
printf '%s\n' "$summary" >>"$out"
mv "$out" "$ctx/overlap.txt"
[ -z "$printed" ] || printf '%s' "$printed"
echo "scan-open-prs: $summary"
