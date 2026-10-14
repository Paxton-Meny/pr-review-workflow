#!/bin/sh
# hunk-ranges: one line per hunk with both ranges and the header's
# function, across renames, new files, deleted files, and insertions.
set -eu

cat >"$SCRATCH/multi.patch" <<'PATCH'
diff --git a/src/app.py b/src/app.py
index 1111111..2222222 100644
--- a/src/app.py
+++ b/src/app.py
@@ -1,3 +1,4 @@
 import os
-x = 1
+x = 2
+y = 3
 print(x)
@@ -10,2 +11,2 @@ def f():
     pass
-    return None
+    return x
@@ -40,0 +42,2 @@ class Thing:
+    def added(self):
+        return 1
diff --git a/old/name.go b/new/name.go
similarity index 90%
rename from old/name.go
rename to new/name.go
--- a/old/name.go
+++ b/new/name.go
@@ -7 +7 @@ func (s *S) Bar() {
-	a := 1
+	a := 2
diff --git a/docs/new.md b/docs/new.md
new file mode 100644
--- /dev/null
+++ b/docs/new.md
@@ -0,0 +1,2 @@
+# New
+text
diff --git a/gone.txt b/gone.txt
deleted file mode 100644
--- a/gone.txt
+++ /dev/null
@@ -1,2 +0,0 @@
-one
-two
PATCH

sh "$REPO_ROOT/scripts/hunk-ranges.sh" "$SCRATCH/multi.patch" >"$SCRATCH/got"
printf 'src/app.py\t2\t2\t2\t3\t\n' >"$SCRATCH/want"
printf 'src/app.py\t11\t11\t12\t12\tdef f():\n' >>"$SCRATCH/want"
printf 'src/app.py\t40\t40\t42\t43\tclass Thing:\n' >>"$SCRATCH/want"
printf 'new/name.go\t7\t7\t7\t7\tfunc (s *S) Bar() {\n' >>"$SCRATCH/want"
printf 'docs/new.md\t0\t0\t1\t2\t\n' >>"$SCRATCH/want"
printf 'gone.txt\t1\t2\t0\t0\t\n' >>"$SCRATCH/want"
cmp -s "$SCRATCH/got" "$SCRATCH/want" || {
	echo "hunk ranges differ from the expected lines:" >&2
	diff "$SCRATCH/want" "$SCRATCH/got" >&2 || true
	exit 1
}

# Stdin works the same, and an empty diff prints nothing.
[ "$(sh "$REPO_ROOT/scripts/hunk-ranges.sh" <"$SCRATCH/multi.patch" | wc -l)" -eq 6 ]
[ -z "$(: | sh "$REPO_ROOT/scripts/hunk-ranges.sh")" ]

if sh "$REPO_ROOT/scripts/hunk-ranges.sh" "$SCRATCH/missing.patch" 2>"$SCRATCH/err"; then
	echo "expected failure on a missing file" >&2
	exit 1
fi
grep -q "no such file" "$SCRATCH/err"
