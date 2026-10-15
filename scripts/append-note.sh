#!/bin/sh
# Append a note to a finding's body. The note arrives on stdin.
# Usage: sh scripts/append-note.sh <state-dir> <id>
set -eu

dir=${1:?usage: append-note.sh <state-dir> <id>}
id=${2:?usage: append-note.sh <state-dir> <id>}
record="$dir/findings/$id"
[ -f "$record" ] || {
	echo "append-note: unknown finding: $id" >&2
	exit 1
}

note=$(cat)
[ -n "$note" ] || {
	echo "append-note: empty note" >&2
	exit 1
}
if printf '%s\n' "$note" | grep -qx -e '=== finding'; then
	echo "append-note: a note may not contain the record separator" >&2
	exit 1
fi
# A note records what happened; the contract lines are the reviewer's.
# One that added a Check line would choose what run-contract executes.
if printf '%s\n' "$note" | grep -Eq '^(Check|Resolution|Fix): |^```suggestion$'; then
	echo "append-note: a note may not add a Check, Resolution, or Fix line or a suggestion fence" >&2
	exit 1
fi

tmp=$(mktemp "$dir/findings/.$id.XXXXXX")
{
	cat "$record"
	printf '\n%s\n' "$note"
} >"$tmp"
mv "$tmp" "$record"
echo "append-note: $id noted"
