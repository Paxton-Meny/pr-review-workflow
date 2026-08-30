#!/bin/sh
# Prove every pending suggestion fence by applying it, or withdraw it.
# Usage: sh scripts/prove-suggestions.sh <state-dir> [check-command]
set -eu

dir=${1:?usage: prove-suggestions.sh <state-dir> [check-command]}
check=${2:-}
worktree="$dir/worktree"
[ -f "$dir/meta.txt" ] && [ -d "$worktree" ] || {
	echo "prove-suggestions: no worktree in $dir, run checkout-pr.sh first" >&2
	exit 1
}
repo_root=$(sed -n 's/^repo_root //p' "$dir/meta.txt")
head_sha=$(sed -n 's/^head_sha //p' "$dir/meta.txt")
[ -n "$repo_root" ] || {
	echo "prove-suggestions: meta.txt records no repo_root" >&2
	exit 1
}

scratch=''
cleanup() {
	[ -n "$scratch" ] && git -C "$repo_root" worktree remove --force "$scratch" 2>/dev/null
	rm -rf "$dir/.prove"
}
trap cleanup EXIT

withdraw() {
	rec=$1
	reason=$2
	tmp=$(mktemp "$dir/findings/.$(sed -n 's/^id: //p' "$rec").XXXXXX")
	awk -v reason="$reason" '
	/^```suggestion$/ { drop = 1; next }
	drop && /^```$/ { drop = 0; withdrawn = 1; next }
	drop { next }
	{ print }
	END {
		if (drop) withdrawn = 1
		if (withdrawn) printf "Suggestion withdrawn: %s.\n", reason
	}
	' "$rec" >"$tmp"
	mv "$tmp" "$rec"
}

proven=0
withdrawn=0
for record in "$dir/findings"/F*; do
	[ -f "$record" ] || continue
	[ "$(sed -n 's/^status: //p' "$record")" = "open" ] || continue
	grep -q '^```suggestion$' "$record" || continue
	id=$(sed -n 's/^id: //p' "$record")
	path=$(sed -n 's/^path: //p' "$record")
	line=$(sed -n 's/^line: //p' "$record")
	end_line=$(sed -n 's/^end_line: //p' "$record")
	side=$(sed -n 's/^side: //p' "$record")
	last=${end_line:-$line}

	if [ "$side" != "RIGHT" ]; then
		withdraw "$record" "a suggestion cannot replace deleted lines"
		withdrawn=$((withdrawn + 1))
		continue
	fi

	if [ -z "$scratch" ]; then
		scratch="$dir/.prove"
		git -C "$repo_root" worktree add --quiet --detach "$scratch" "$head_sha"
	fi
	target="$scratch/$path"
	if [ ! -f "$target" ] || [ "$(awk 'END { print NR }' "$target")" -lt "$last" ]; then
		withdraw "$record" "the target range does not exist at the pull request head"
		withdrawn=$((withdrawn + 1))
		continue
	fi

	replacement=$(mktemp "$dir/findings/.sugg.XXXXXX")
	awk '/^```suggestion$/ { take = 1; next } take && /^```$/ { exit } take { print }' \
		"$record" >"$replacement"
	spliced=$(mktemp "$dir/findings/.sugg.XXXXXX")
	awk -v first="$line" -v last="$last" -v repl="$replacement" '
	NR == first { while ((getline r < repl) > 0) print r }
	NR >= first && NR <= last { next }
	{ print }
	' "$target" >"$spliced"
	mv "$spliced" "$target"
	rm -f "$replacement"

	ok=1
	if [ -n "$check" ]; then
		(cd "$scratch" && sh -c "$check") >/dev/null 2>&1 || ok=0
	fi
	git -C "$scratch" checkout --quiet -- "$path"

	if [ "$ok" -eq 1 ]; then
		proven=$((proven + 1))
	else
		withdraw "$record" "the check command failed with it applied"
		withdrawn=$((withdrawn + 1))
	fi
done

echo "prove-suggestions: $proven proven, $withdrawn withdrawn"
