#!/bin/sh
# probe-diff: surfaces leads, withholds secret content, stays quiet when clean.
set -eu

dir="$SCRATCH/state"
ctx="$dir/pr-context"
mkdir -p "$ctx"
printf 'src/new.py\t900\t0\nrequirements.txt\t1\t0\n' >"$ctx/files.txt"
cat > "$ctx/diff.patch" <<'PATCH'
diff --git a/src/new.py b/src/new.py
--- /dev/null
+++ b/src/new.py
@@ -0,0 +1,4 @@
+import requests
+API_KEY = "sk-live_abcdefghijklmnopqrstu"
+print_r($x)
+# TODO drop this
diff --git a/old.txt b/old.txt
--- a/old.txt
+++ /dev/null
@@ -1 +0,0 @@
-gone
PATCH

out=$(sh "$REPO_ROOT/scripts/probe-diff.sh" "$dir")
[ "$out" = "probe-diff: 8 sections (added deleted deps imports secrets debug markers large)" ]
grep -qx '## Added files' "$ctx/probes.txt"
grep -qx 'src/new.py' "$ctx/probes.txt"
grep -qx '## Deleted files' "$ctx/probes.txt"
grep -qx 'old.txt' "$ctx/probes.txt"
grep -q 'requirements.txt' "$ctx/probes.txt"
grep -qx 'src/new.py:1' "$ctx/probes.txt"
grep -qx 'src/new.py:2' "$ctx/probes.txt"
if grep -q 'sk-live' "$ctx/probes.txt"; then
	echo "secret content must be withheld from probes" >&2
	exit 1
fi
grep -q 'print_r' "$ctx/probes.txt"
grep -q 'TODO drop this' "$ctx/probes.txt"
grep -q 'src/new.py (900 added)' "$ctx/probes.txt"

printf 'docs/a.md\t1\t0\n' >"$ctx/files.txt"
cat > "$ctx/diff.patch" <<'PATCH'
diff --git a/docs/a.md b/docs/a.md
--- a/docs/a.md
+++ b/docs/a.md
@@ -1 +1,2 @@
 hello
+a plain line
PATCH
out=$(sh "$REPO_ROOT/scripts/probe-diff.sh" "$dir")
[ "$out" = "probe-diff: 0 sections" ]
[ ! -f "$ctx/probes.txt" ]

if sh "$REPO_ROOT/scripts/probe-diff.sh" "$SCRATCH/empty" 2>"$SCRATCH/err"; then
	echo "expected failure without a diff" >&2
	exit 1
fi
grep -q "no diff.patch" "$SCRATCH/err"

printf 'tests/test_api.py\t2\t9\nsrc/api.py\t3\t0\n' >"$ctx/files.txt"
cat > "$ctx/diff.patch" <<'PATCH'
diff --git a/tests/test_api.py b/tests/test_api.py
--- a/tests/test_api.py
+++ b/tests/test_api.py
@@ -1,3 +1,2 @@
 keep
-first assertion stays out
+pass
PATCH
out=$(sh "$REPO_ROOT/scripts/probe-diff.sh" "$dir")
[ "$out" = "probe-diff: 1 sections (test-shrink)" ]
grep -q 'tests/test_api.py (2 added, 9 deleted)' "$ctx/probes.txt"

printf 'src/locks.py\t3\t0\n' >"$ctx/files.txt"
cat > "$ctx/diff.patch" <<'PATCH'
diff --git a/src/locks.py b/src/locks.py
--- a/src/locks.py
+++ b/src/locks.py
@@ -1,2 +1,4 @@
 keep
+with threading.Lock():
+    digest = hmac.new(key, msg)
PATCH
out=$(sh "$REPO_ROOT/scripts/probe-diff.sh" "$dir")
[ "$out" = "probe-diff: 1 sections (sensitive)" ]
grep -q 'threading.Lock' "$ctx/probes.txt"
