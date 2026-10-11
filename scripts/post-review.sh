#!/bin/sh
# Post a new round's summary, then unposted findings as inline review comments.
# Usage: sh scripts/post-review.sh <state-dir>
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

field() { sed -n "s/^$2: //p" "$1"; }
body_of() { awk 'f && !/^Criteria note: / { print } /^---$/ { f = 1 }' "$1"; }
unposted() { [ "$(field "$1" status)" = "open" ] && [ -z "$(field "$1" placement)" ]; }

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
if grep -qx "round: $round" "$dir/findings"/F* 2>/dev/null; then
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
echo "post-review: $posted posted inline, $demoted in the summary, round $(cat "$dir/round.txt")"
