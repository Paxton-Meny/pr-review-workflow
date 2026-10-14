#!/bin/sh
# Decide how this pull request merges: the setting, the one method the
# repository allows, or the method its recent merged pull requests used.
# Usage: sh scripts/merge-method.sh <state-dir> [--refresh | --set merge|squash|rebase]
#
# Writes pr-context/merge-method.txt, one "key value" line each: method
# (merge, squash, rebase, or undecided), reason, allowed (the methods the
# repository permits), delete_branch_on_merge, and history (merge, squash,
# rebase, either counts), and prints one line. A written record is reused
# until --refresh. The history reads the last HISTORY_LIMIT merged pull
# requests into this base branch (any base when fewer than MIN_SAMPLES
# have one) and classifies each by its merge commit in the clone: two
# parents is a merge; one parent whose subject ends in "(#n)" or that
# collapsed several commits is a squash; one parent that replayed the
# pull request's own commit subjects is a rebase; one commit kept as it
# was is either a squash or a rebase, so it counts for both. The method
# wins when it is allowed, holds at least two thirds of MIN_SAMPLES or
# more classified pull requests of this pull request's shape (one commit
# or several), first within that shape and then over all of them, and no
# other allowed method ties it. Exit 4: undecided, the record written
# with the counts for a person. Exit 1: the setting names a method the
# repository does not allow. --set records a method a person chose.
set -eu

dir=${1:?usage: merge-method.sh <state-dir> [--refresh | --set merge|squash|rebase]}
mode=${2:-}
chosen=${3:-}
case "$mode" in
'' | --refresh) ;;
--set)
	case "$chosen" in
	merge | squash | rebase) ;;
	*)
		echo "merge-method: --set takes merge, squash, or rebase: $chosen" >&2
		exit 1
		;;
	esac
	;;
*)
	echo "merge-method: unknown argument: $mode" >&2
	exit 1
	;;
esac
[ -f "$dir/meta.txt" ] || {
	echo "merge-method: no meta.txt in $dir" >&2
	exit 1
}
ctx="$dir/pr-context"
[ -d "$ctx" ] || {
	echo "merge-method: no pr-context in $dir, run fetch-pr.sh first" >&2
	exit 1
}
record="$ctx/merge-method.txt"
owner=$(sed -n 's/^owner //p' "$dir/meta.txt")
repo=$(sed -n 's/^repo //p' "$dir/meta.txt")
base=$(sed -n 's/^base_branch //p' "$dir/meta.txt")
repo_root=$(sed -n 's/^repo_root //p' "$dir/meta.txt")

HISTORY_LIMIT=30
MIN_SAMPLES=3

field() {
	# field <key> <file>
	sed -n "s/^$1 //p" "$2" | head -n 1
}

report() {
	# report <method> <reason>: the one proven line, from the record
	case "$1" in
	undecided)
		echo "merge-method: undecided among $(field allowed "$record"), history $(field history "$record"); set merge_method"
		exit 4
		;;
	*) echo "merge-method: $1 reason $2" ;;
	esac
}

if [ "$mode" = --set ]; then
	[ -f "$record" ] || {
		echo "merge-method: nothing to set, run merge-method.sh $dir first" >&2
		exit 1
	}
	allowed=$(field allowed "$record")
	case " $allowed " in
	*" $chosen "*) ;;
	*)
		echo "merge-method: the repository allows $allowed, not $chosen" >&2
		exit 1
		;;
	esac
	tmp=$(mktemp "$ctx/.method.XXXXXX")
	sed -e "s/^method .*/method $chosen/" -e "s/^reason .*/reason asked/" "$record" >"$tmp"
	mv "$tmp" "$record"
	report "$chosen" asked
	exit 0
fi

if [ "$mode" = '' ] && [ -f "$record" ]; then
	report "$(field method "$record")" "$(field reason "$record")"
	exit 0
fi

setting=auto
[ -f "$dir/settings.txt" ] && setting=$(sh "$(dirname -- "$0")/setting.sh" "$dir" merge_method)

flags=$(gh api "repos/$owner/$repo" \
	--jq '"\(.allow_merge_commit) \(.allow_squash_merge) \(.allow_rebase_merge) \(.delete_branch_on_merge)"') || {
	echo "merge-method: gh could not read the repository settings of $owner/$repo" >&2
	exit 1
}
set -- $flags
allowed=''
[ "$1" = true ] && allowed="$allowed merge"
[ "$2" = true ] && allowed="$allowed squash"
[ "$3" = true ] && allowed="$allowed rebase"
allowed=${allowed# }
delete_on_merge=$4
[ -n "$allowed" ] || {
	echo "merge-method: $owner/$repo allows no merge method" >&2
	exit 1
}

history='merge 0 squash 0 rebase 0 either 0'
write() {
	# write <method> <reason>
	tmp=$(mktemp "$ctx/.method.XXXXXX")
	printf 'method %s\nreason %s\nallowed %s\ndelete_branch_on_merge %s\nhistory %s\n' \
		"$1" "$2" "$allowed" "$delete_on_merge" "$history" >"$tmp"
	mv "$tmp" "$record"
	report "$1" "$2"
}

if [ "$setting" != auto ]; then
	case " $allowed " in
	*" $setting "*) write "$setting" setting ;;
	*)
		echo "merge-method: the setting names $setting, which $owner/$repo does not allow; it allows $allowed" >&2
		exit 1
		;;
	esac
	exit 0
fi
case "$allowed" in
*' '*) ;;
*)
	write "$allowed" allowed-only
	exit 0
	;;
esac

# The history, one line per merged pull request: number, merge commit,
# commit count, then the commit subjects separated by a record separator.
merged() {
	# merged [--base <branch>]
	gh pr list --repo "$owner/$repo" --state merged --limit "$HISTORY_LIMIT" "$@" \
		--json number,mergeCommit,commits \
		--jq '.[] | "\(.number)\t\(.mergeCommit.oid // "-")\t\(.commits | length)\t\(.commits | map(.messageHeadline) | join("\u001e"))"' 2>/dev/null || true
}
raw=$(mktemp "$ctx/.history.XXXXXX")
trap 'rm -f "$raw"' EXIT
if [ -n "$base" ]; then
	merged --base "$base" >"$raw"
fi
[ "$(grep -c . "$raw")" -ge "$MIN_SAMPLES" ] || merged >"$raw"

# Classify each by the merge commit the clone holds; "shape" is single
# or multi by the pull request's own commit count.
classify() {
	# classify <oid> <count> <subjects>: prints merge|squash|rebase|either|unknown
	[ -n "$repo_root" ] && [ -d "$repo_root" ] || {
		echo unknown
		return
	}
	commit=$(git -C "$repo_root" cat-file -p "$1" 2>/dev/null) || {
		echo unknown
		return
	}
	parents=$(printf '%s\n' "$commit" | sed -n '/^$/q; /^parent /p' | grep -c . || true)
	subject=$(printf '%s\n' "$commit" | sed -n '/^$/{n;p;q;}')
	if [ "$parents" -ge 2 ]; then
		echo merge
		return
	fi
	case "$subject" in
	*' (#'[0-9]*')')
		echo squash
		return
		;;
	esac
	expected=$(printf '%s' "$3" | tr '\036' '\n' | sed '1!G;h;$!d')
	actual=$(git -C "$repo_root" log --format=%s -n "$2" "$1" 2>/dev/null || true)
	if [ "$2" -gt 1 ]; then
		if [ "$expected" = "$actual" ]; then echo rebase; else echo squash; fi
	elif [ "$expected" = "$actual" ]; then
		echo either
	else
		echo squash
	fi
}
classes=$(mktemp "$ctx/.history.XXXXXX")
trap 'rm -f "$raw" "$classes"' EXIT
while IFS='	' read -r _number oid count subjects; do
	[ "$oid" != - ] || continue
	shape=single
	[ "${count:-1}" -gt 1 ] && shape=multi
	printf '%s %s\n' "$shape" "$(classify "$oid" "${count:-1}" "$subjects")"
done <"$raw" >"$classes"

pr_commits=$(sed -n 's/^commits //p' "$ctx/meta-full.txt" 2>/dev/null | head -n 1)
pr_shape=single
[ "${pr_commits:-1}" -gt 1 ] && pr_shape=multi

count() {
	# count <shape|all> <class>
	if [ "$1" = all ]; then
		grep -c " $2\$" "$classes" || true
	else
		grep -c "^$1 $2\$" "$classes" || true
	fi
}
decide() {
	# decide <shape|all>: prints the winning allowed method, or nothing
	m=$(count "$1" merge) s=$(count "$1" squash) r=$(count "$1" rebase) e=$(count "$1" either)
	total=$((m + s + r + e))
	[ "$total" -ge "$MIN_SAMPLES" ] || return 0
	winner='' best=0 tie=0
	for method in $allowed; do
		case "$method" in
		merge) score=$m ;;
		squash) score=$((s + e)) ;;
		rebase) score=$((r + e)) ;;
		esac
		if [ "$score" -gt "$best" ]; then
			best=$score winner=$method tie=0
		elif [ "$score" -eq "$best" ] && [ "$score" -gt 0 ]; then
			tie=1
		fi
	done
	[ "$tie" -eq 0 ] && [ $((best * 3)) -ge $((total * 2)) ] || return 0
	printf '%s %s/%s\n' "$winner" "$best" "$total"
}
history="merge $(count all merge) squash $(count all squash) rebase $(count all rebase) either $(count all either)"
verdict=$(decide "$pr_shape")
reason="history-$pr_shape"
if [ -z "$verdict" ]; then
	verdict=$(decide all)
	reason=history-all
fi
if [ -n "$verdict" ]; then
	write "${verdict%% *}" "$reason ${verdict#* }"
	exit 0
fi
write undecided mixed-history
