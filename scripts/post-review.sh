#!/bin/sh
# Post a new round's summary, then unposted findings as inline review comments.
# Usage: sh scripts/post-review.sh <state-dir>
# Every body passes through redact.sh first; the result line counts
# what it masked when anything was.
# Exit 4: refused, posting and changing nothing, because a record about
# to be posted carries a suggestion fence prove-suggestions.sh has not
# proven at the head the comments anchor to ("unproven <id>" lines).
# Exit 5: refused the same way because the review phase is incomplete:
# a shard or sample unsaved, a dedup or gap pass not run, as the lines
# from review-progress.sh name. Posting then would close the round
# before its findings are all in.
set -eu

dir=${1:?usage: post-review.sh <state-dir>}
ctx="$dir/pr-context"
[ -f "$dir/meta.txt" ] && [ -f "$ctx/commentable.txt" ] || {
	echo "post-review: state in $dir is incomplete, run fetch-pr.sh first" >&2
	exit 1
}
owner=$(sed -n 's/^owner //p' "$dir/meta.txt")
repo=$(sed -n 's/^repo //p' "$dir/meta.txt")
pr=$(sed -n 's/^pr //p' "$dir/meta.txt")
head_sha=$(sed -n 's/^head_sha //p' "$dir/meta.txt")
round=$(($(cat "$dir/round.txt") + 1))
here=$(dirname -- "$0")
tab=$(printf '\t')

# Header fields only: a body may quote a line that looks like one.
field() { sed -n "/^---\$/q; s/^$2: //p" "$1"; }
body_of() { awk 'f && !/^Criteria note: / { print } /^---$/ { f = 1 }' "$1"; }
unposted() { [ "$(field "$1" status)" = "open" ] && [ -z "$(field "$1" placement)" ]; }

rc=0
progress=$(sh "$here/review-progress.sh" "$dir") || rc=$?
case "$rc" in
0) ;;
3)
	echo "post-review: the review phase is incomplete, finish steps 5 and 6 first"
	printf '%s\n' "$progress" | sed 1d
	exit 5
	;;
*) exit 1 ;;
esac

masked=0
redact() {
	# redact <file>: mask credentials in place, counting them
	out=$(sh "$here/redact.sh" "$1")
	n=$(printf '%s\n' "$out" | sed -n 's/^redact: \([0-9]*\) masked$/\1/p')
	masked=$((masked + ${n:-0}))
}
# Every fence this run would post, inline or in this round's summary,
# must have been proven at the head first.
unproven=''
for record in "$dir/findings"/F*; do
	[ -f "$record" ] && [ "$(field "$record" status)" = open ] || continue
	case "$(field "$record" placement)" in
	'') ;;
	summary) [ "$(field "$record" round)" = "$round" ] || continue ;;
	*) continue ;;
	esac
	grep -q '^```suggestion$' "$record" || continue
	[ "$(sed '/^---$/q' "$record" | sed -n 's/^proven: //p')" = "$head_sha" ] ||
		unproven="$unproven
unproven $(field "$record" id)"
done
if [ -n "$unproven" ]; then
	echo "post-review: suggestion fences not proven at the head, run prove-suggestions.sh first$unproven"
	exit 4
fi

demoted=0
for record in "$dir/findings"/F*; do
	[ -f "$record" ] && unposted "$record" || continue
	path=$(field "$record" path)
	side=$(field "$record" side)
	n=$(field "$record" line)
	last=$(field "$record" end_line)
	last=${last:-$n}
	while [ "$n" -le "$last" ]; do
		if ! grep -qxF "$path$tab$side$tab$n" "$ctx/commentable.txt"; then
			sh "$here/update-finding.sh" "$dir" "$(field "$record" id)" placement=summary >/dev/null
			demoted=$((demoted + 1))
			break
		fi
		n=$((n + 1))
	done
done

summarized=0
new_round=0
for record in "$dir/findings"/F*; do
	[ -f "$record" ] && [ "$(field "$record" round)" = "$round" ] && new_round=1 && break
done
if [ "$new_round" -eq 1 ]; then
	blocker=0 major=0 minor=0 nit=0
	summary_ids=''
	for record in "$dir/findings"/F*; do
		[ "$(field "$record" round)" = "$round" ] || continue
		case "$(field "$record" severity)" in
		blocker) blocker=$((blocker + 1)) ;;
		major) major=$((major + 1)) ;;
		minor) minor=$((minor + 1)) ;;
		nit) nit=$((nit + 1)) ;;
		esac
		if [ "$(field "$record" placement)" = "summary" ] && [ "$(field "$record" status)" = "open" ]; then
			summary_ids="$summary_ids $(field "$record" id)"
		fi
	done
	credit=$(sh "$here/attribution.sh" "$dir")

	tmp=$(mktemp "$dir/.post.XXXXXX")
	trap 'rm -f "$tmp"' EXIT
	{
		printf 'Review round %d: %d blocker, %d major, %d minor, %d nit.\n' \
			"$round" "$blocker" "$major" "$minor" "$nit"
		for sid in $summary_ids; do
			record="$dir/findings/$sid"
			printf '\n### `%s` %s (%s, %s) at %s:%s\n\n' "$sid" \
				"$(field "$record" title)" "$(field "$record" severity)" \
				"$(field "$record" category)" "$(field "$record" path)" \
				"$(field "$record" line)"
			body_of "$record"
		done
		[ -z "$credit" ] || printf '\n%s\n' "$credit"
	} >"$tmp"
	redact "$tmp"
	gh pr comment "$pr" --repo "$owner/$repo" --body-file "$tmp" >/dev/null
	rm -f "$tmp"
	trap - EXIT

	rtmp=$(mktemp "$dir/.round.XXXXXX")
	printf '%d\n' "$round" >"$rtmp"
	mv "$rtmp" "$dir/round.txt"
	summarized=1
fi

posted=0
for record in "$dir/findings"/F*; do
	[ -f "$record" ] && unposted "$record" || continue
	id=$(field "$record" id)
	path=$(field "$record" path)
	line=$(field "$record" line)
	end_line=$(field "$record" end_line)
	side=$(field "$record" side)

	tmp=$(mktemp "$dir/.post.XXXXXX")
	trap 'rm -f "$tmp"' EXIT
	{
		printf '`%s` **%s (%s).** %s\n\n' "$id" "$(field "$record" severity)" \
			"$(field "$record" category)" "$(field "$record" title)"
		body_of "$record"
	} >"$tmp"
	redact "$tmp"

	if [ -n "$end_line" ]; then
		comment_id=$(gh api "repos/$owner/$repo/pulls/$pr/comments" \
			-f commit_id="$head_sha" -f path="$path" -f side="$side" \
			-F start_line="$line" -f start_side="$side" -F line="$end_line" \
			-F body=@"$tmp" --jq .id)
	else
		comment_id=$(gh api "repos/$owner/$repo/pulls/$pr/comments" \
			-f commit_id="$head_sha" -f path="$path" -f side="$side" \
			-F line="$line" -F body=@"$tmp" --jq .id)
	fi
	rm -f "$tmp"
	trap - EXIT
	sh "$here/update-finding.sh" "$dir" "$id" \
		"comment_id=$comment_id" placement=inline >/dev/null
	posted=$((posted + 1))
done

if [ "$summarized" -eq 0 ] && [ "$posted" -eq 0 ]; then
	echo "post-review: nothing to post, round $((round - 1)) unchanged"
	exit 0
fi
tail=''
[ "$masked" -eq 0 ] || tail=", $masked masked"
echo "post-review: $posted posted inline, $demoted in the summary, round $(cat "$dir/round.txt")$tail"
