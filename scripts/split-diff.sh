#!/bin/sh
# Split a fetched diff into annotated per-file diffs and a commentable index.
# Usage: sh scripts/split-diff.sh <state-dir>
set -eu

dir=${1:?usage: split-diff.sh <state-dir>}
patch="$dir/pr-context/diff.patch"
[ -f "$patch" ] || {
	echo "split-diff: no diff.patch in $dir/pr-context, run fetch-pr.sh first" >&2
	exit 1
}

files_dir="$dir/pr-context/files"
rm -rf "$files_dir"
mkdir -p "$files_dir"

awk -v files_dir="$files_dir" \
	-v index_file="$dir/pr-context/diff-index.txt" \
	-v commentable="$dir/pr-context/commentable.txt" '
BEGIN { seq = 0; inhunk = 0; path = "" }
/^diff --git / { inhunk = 0; path = ""; oldpath = ""; next }
/^--- / { p = $0; sub(/^--- /, "", p); sub(/^a\//, "", p); oldpath = p; next }
/^\+\+\+ / {
	p = $0; sub(/^\+\+\+ /, "", p); sub(/^b\//, "", p)
	path = (p == "/dev/null") ? oldpath : p
	seq++
	out = sprintf("%s/%03d.diff", files_dir, seq)
	printf "path: %s\n", path > out
	printf "%03d\t%s\n", seq, path > index_file
	next
}
/^@@ / {
	if (path == "") next
	o = $2; sub(/^-/, "", o); sub(/,.*/, "", o); oldl = o + 0
	n = $3; sub(/^\+/, "", n); sub(/,.*/, "", n); newl = n + 0
	inhunk = 1
	print $0 > out
	next
}
{
	if (!inhunk || path == "") next
	c = substr($0, 1, 1)
	if (c == "+") {
		printf "R%d %s\n", newl, $0 > out
		printf "%s\tRIGHT\t%d\n", path, newl > commentable
		newl++
	} else if (c == "-") {
		printf "L%d %s\n", oldl, $0 > out
		printf "%s\tLEFT\t%d\n", path, oldl > commentable
		oldl++
	} else if (c == "\\") {
		print $0 > out
	} else {
		printf "R%d %s\n", newl, $0 > out
		printf "%s\tRIGHT\t%d\n", path, newl > commentable
		oldl++
		newl++
	}
}
' "$patch"

file_count=0
[ -f "$dir/pr-context/diff-index.txt" ] && file_count=$(grep -c . "$dir/pr-context/diff-index.txt")
line_count=0
[ -f "$dir/pr-context/commentable.txt" ] && line_count=$(grep -c . "$dir/pr-context/commentable.txt")
echo "split-diff: $file_count files, $line_count commentable lines"
