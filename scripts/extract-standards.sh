#!/bin/sh
# Gather the project's local standards files into the review context.
# Usage: sh scripts/extract-standards.sh <state-dir> [glob ...]
set -eu

dir=${1:?usage: extract-standards.sh <state-dir> [glob ...]}
shift
ctx="$dir/pr-context"
[ -f "$dir/meta.txt" ] && [ -d "$ctx" ] || {
	echo "extract-standards: state in $dir is incomplete, run fetch-pr.sh and checkout-pr.sh first" >&2
	exit 1
}
ctx=$(CDPATH= cd -- "$ctx" && pwd)
rm -f "$ctx/standards.txt"

patterns=${*:-}
if [ -z "$patterns" ]; then
	echo "extract-standards: none configured"
	exit 0
fi

repo_root=$(sed -n 's/^repo_root //p' "$dir/meta.txt")
[ -n "$repo_root" ] && [ -d "$repo_root" ] || {
	echo "extract-standards: meta.txt records no repo_root" >&2
	exit 1
}

tmp=$(mktemp "$ctx/.std.XXXXXX")
trap 'rm -f "$tmp"' EXIT
files=0
seen=
cd "$repo_root"
for path in $patterns; do
	case "$path" in
	/* | *..*)
		echo "extract-standards: refusing path outside the clone: $path" >&2
		exit 1
		;;
	esac
	[ -f "$path" ] || continue
	[ ! -L "$path" ] || continue
	case " $seen " in
	*" $path "*) continue ;;
	esac
	seen="$seen $path"
	printf '===== %s =====\n' "${path##*/}" >>"$tmp"
	cat "$path" >>"$tmp"
	printf '\n' >>"$tmp"
	files=$((files + 1))
done

if [ "$files" -eq 0 ]; then
	echo "extract-standards: no files matched"
	exit 0
fi
lines=$(grep -c . "$tmp" || true)
mv "$tmp" "$ctx/standards.txt"
trap - EXIT
echo "extract-standards: $files files, $lines lines"
