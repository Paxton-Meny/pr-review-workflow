#!/bin/sh
# split-diff: annotates lines, indexes files, lists commentable positions.
set -eu

dir="$SCRATCH/state"
mkdir -p "$dir/pr-context"
cp "$REPO_ROOT/tests/fixtures/two-files.patch" "$dir/pr-context/diff.patch"

out=$(sh "$REPO_ROOT/scripts/split-diff.sh" "$dir")
[ "$out" = "split-diff: 2 files, 9 commentable lines" ]

ctx="$dir/pr-context"
printf '001\tsrc/app.py\n002\tdocs/readme.md\n' >"$SCRATCH/want-index"
cmp -s "$ctx/diff-index.txt" "$SCRATCH/want-index"

head -n 1 "$ctx/files/001.diff" | grep -qx 'path: src/app.py'
grep -qx 'R1  import os' "$ctx/files/001.diff"
grep -qx 'L2 -x = 1' "$ctx/files/001.diff"
grep -qx 'R2 +x = 2' "$ctx/files/001.diff"
grep -qx 'R3 +y = 3' "$ctx/files/001.diff"
grep -qx 'R4  print(x)' "$ctx/files/001.diff"
grep -qx 'L10 -    return None' "$ctx/files/001.diff"
grep -qx 'R11 +    return x' "$ctx/files/001.diff"
grep -qx '@@ -10,2 +11,2 @@ def f():' "$ctx/files/001.diff"

grep -qx 'R2 +more' "$ctx/files/002.diff"
grep -qx '\\ No newline at end of file' "$ctx/files/002.diff"

grep -cx 'src/app.py	RIGHT	2' "$ctx/commentable.txt" | grep -qx 1
grep -qx 'src/app.py	LEFT	2' "$ctx/commentable.txt"
grep -qx 'src/app.py	LEFT	10' "$ctx/commentable.txt"
grep -qx 'docs/readme.md	RIGHT	2' "$ctx/commentable.txt"

sh "$REPO_ROOT/scripts/split-diff.sh" "$dir" >/dev/null
[ "$(grep -c . "$ctx/commentable.txt")" -eq 9 ] || {
	echo "rerun must rewrite, not append" >&2
	exit 1
}

rm "$ctx/diff.patch"
if sh "$REPO_ROOT/scripts/split-diff.sh" "$dir" 2>"$SCRATCH/err"; then
	echo "expected failure without diff.patch" >&2
	exit 1
fi
grep -q "no diff.patch" "$SCRATCH/err"
