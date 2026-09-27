#!/bin/sh
# split-diff: annotates lines, indexes files, lists commentable positions.
set -eu

dir="$SCRATCH/state"
mkdir -p "$dir/pr-context"
cp "$REPO_ROOT/tests/fixtures/two-files.patch" "$dir/pr-context/diff.patch"

out=$(sh "$REPO_ROOT/scripts/split-diff.sh" "$dir")
[ "$out" = "split-diff: 2 files, 9 commentable lines, 0 excluded" ]

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

: >"$ctx/diff.patch"
sh "$REPO_ROOT/scripts/split-diff.sh" "$dir" | grep -qx 'split-diff: 0 files, 0 commentable lines, 0 excluded'
[ ! -f "$ctx/diff-index.txt" ]
[ ! -f "$ctx/commentable.txt" ]

cat > "$ctx/diff.patch" <<'PATCH'
diff --git a/src/app.py b/src/app.py
--- a/src/app.py
+++ b/src/app.py
@@ -1 +1,2 @@
 keep
+real change
diff --git a/package-lock.json b/package-lock.json
--- a/package-lock.json
+++ b/package-lock.json
@@ -1 +1,2 @@
 lock
+churn
diff --git a/assets/bundle.min.js b/assets/bundle.min.js
--- a/assets/bundle.min.js
+++ b/assets/bundle.min.js
@@ -1 +1,2 @@
 blob
+more
PATCH
out=$(sh "$REPO_ROOT/scripts/split-diff.sh" "$dir")
[ "$out" = "split-diff: 1 files, 2 commentable lines, 2 excluded" ]
grep -qx 'package-lock.json' "$ctx/excluded.txt"
grep -qx 'assets/bundle.min.js' "$ctx/excluded.txt"
grep -qx '001	src/app.py' "$ctx/diff-index.txt"
if grep -q 'package-lock' "$ctx/diff-index.txt" "$ctx/commentable.txt"; then
	echo "excluded files must not be indexed or commentable" >&2
	exit 1
fi
[ "$(ls "$ctx/files" | wc -l)" -eq 1 ]

cat > "$ctx/diff.patch" <<'PATCH'
diff --git a/yarn.lock b/yarn.lock
--- a/yarn.lock
+++ /dev/null
@@ -1,2 +0,0 @@
-a
-b
diff --git a/src/app.py b/src/app.py
--- a/src/app.py
+++ b/src/app.py
@@ -1 +1,2 @@
 keep
+line
PATCH
out=$(sh "$REPO_ROOT/scripts/split-diff.sh" "$dir")
[ "$out" = "split-diff: 1 files, 2 commentable lines, 1 excluded" ]
grep -qx 'yarn.lock' "$ctx/excluded.txt"
if grep -q 'yarn.lock' "$ctx/commentable.txt"; then
	echo "a deleted lockfile must not be commentable" >&2
	exit 1
fi
