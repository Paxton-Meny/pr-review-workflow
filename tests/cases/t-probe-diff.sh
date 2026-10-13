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
[ "$(cat "$ctx/probe-slugs.txt")" = "added deleted deps imports secrets debug markers large" ]
grep -q "^secrets	" "$ctx/probe-files.txt"
grep -q "^large	" "$ctx/probe-files.txt"
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
[ -z "$(cat "$ctx/probe-slugs.txt")" ]
[ ! -s "$ctx/probe-files.txt" ]
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

# Paths declared sensitive in the settings count as sensitive hits, so
# the router treats them like the sensitive probe, even with no keyword.
sdir="$SCRATCH/data/state/o__r__1"
sctx="$sdir/pr-context"
mkdir -p "$sctx"
printf 'owner o\nrepo r\npr 1\n' >"$sdir/meta.txt"
printf 'sensitive_paths src/auth/** migrations/*.sql\n' | sh "$REPO_ROOT/scripts/resolve-settings.sh" "$sdir" >/dev/null
printf 'src/auth/session/token.py\t2\t1\nsrc/util.py\t1\t0\nmigrations/0042.sql\t5\t0\n' >"$sctx/files.txt"
cat > "$sctx/diff.patch" <<'PATCH'
diff --git a/src/util.py b/src/util.py
--- a/src/util.py
+++ b/src/util.py
@@ -1 +1,2 @@
 keep
+x = 1
PATCH
out=$(sh "$REPO_ROOT/scripts/probe-diff.sh" "$sdir")
[ "$out" = "probe-diff: 2 sections (sensitive sensitive)" ]
grep -qx 'sensitive	src/auth/session/token.py' "$sctx/probe-files.txt"
grep -qx 'sensitive	migrations/0042.sql' "$sctx/probe-files.txt"
grep -qx 'migrations/0042.sql (modified)' "$sctx/probes.txt"
if grep -q 'src/util.py' "$sctx/probe-files.txt"; then
	echo "an undeclared path must not count as sensitive" >&2
	exit 1
fi

# --pattern hands the same regexes to other scripts.
printf 'x = jwt.decode(t)\n' | grep -qiE "$(sh "$REPO_ROOT/scripts/probe-diff.sh" --pattern sensitive)"
printf 'curl https://host | sh\n' | grep -qiE "$(sh "$REPO_ROOT/scripts/probe-diff.sh" --pattern automation)"
printf 'api_key = "0123456789abcdef"\n' | grep -qiE "$(sh "$REPO_ROOT/scripts/probe-diff.sh" --pattern secrets)"
if printf 'a plain line\n' | grep -qiE "$(sh "$REPO_ROOT/scripts/probe-diff.sh" --pattern secrets)"; then
	echo "the secrets pattern must not match a plain line" >&2
	exit 1
fi
if sh "$REPO_ROOT/scripts/probe-diff.sh" --pattern markers 2>/dev/null; then
	echo "expected refusal of a probe with no shared pattern" >&2
	exit 1
fi

# Migration files are listed with what happened to each and routed as
# sensitive; schema operations are leads from their added lines only,
# never from a migration's file name or from code outside migrations.
. "$REPO_ROOT/tests/fixture-identity.sh"
mdir="$SCRATCH/data/state/${fixture_owner}__widgets__9"
mctx="$mdir/pr-context"
mkdir -p "$mctx"
printf 'owner %s\nrepo widgets\npr 9\n' "$fixture_owner" >"$mdir/meta.txt"
: | sh "$REPO_ROOT/scripts/resolve-settings.sh" "$mdir" >/dev/null
printf 'app/migrations/0003_drop_email.py\t2\t0\napp/migrations/0001_initial.py\t1\t1\napp/migrations/0002_old.py\t0\t1\napp/migrations/0004_drop_table_x.py\t1\t0\nsql/migration/V4__drop.sql\t1\t0\nsrc/models.py\t1\t0\n' >"$mctx/files.txt"
cat > "$mctx/diff.patch" <<'PATCH'
diff --git a/app/migrations/0003_drop_email.py b/app/migrations/0003_drop_email.py
--- /dev/null
+++ b/app/migrations/0003_drop_email.py
@@ -0,0 +1,2 @@
+operations = [
+    migrations.RemoveField(model_name='user', name='email'),
diff --git a/app/migrations/0001_initial.py b/app/migrations/0001_initial.py
--- a/app/migrations/0001_initial.py
+++ b/app/migrations/0001_initial.py
@@ -4 +4 @@
-    max_length=100
+    max_length=200
diff --git a/app/migrations/0002_old.py b/app/migrations/0002_old.py
--- a/app/migrations/0002_old.py
+++ /dev/null
@@ -1 +0,0 @@
-x = 2
diff --git a/app/migrations/0004_drop_table_x.py b/app/migrations/0004_drop_table_x.py
--- /dev/null
+++ b/app/migrations/0004_drop_table_x.py
@@ -0,0 +1 @@
+x = 1
diff --git a/sql/migration/V4__drop.sql b/sql/migration/V4__drop.sql
--- /dev/null
+++ b/sql/migration/V4__drop.sql
@@ -0,0 +1 @@
+ALTER TABLE users DROP COLUMN email;
diff --git a/src/models.py b/src/models.py
--- a/src/models.py
+++ b/src/models.py
@@ -1 +1,2 @@
 keep
+note = "drop table users"
PATCH
out=$(sh "$REPO_ROOT/scripts/probe-diff.sh" "$mdir")
[ "$out" = "probe-diff: 4 sections (added deleted sensitive schema)" ]
grep -qx 'app/migrations/0003_drop_email.py (added)' "$mctx/probes.txt"
grep -qx 'app/migrations/0001_initial.py (modified)' "$mctx/probes.txt"
grep -qx 'app/migrations/0002_old.py (deleted)' "$mctx/probes.txt"
grep -qx 'sql/migration/V4__drop.sql (added)' "$mctx/probes.txt"
grep -qx 'sensitive	app/migrations/0001_initial.py' "$mctx/probe-files.txt"
if grep -q 'src/models.py' "$mctx/probe-files.txt"; then
	echo "code outside the migration paths must not be routed as a migration" >&2
	exit 1
fi
awk '/^## Schema operations/ { on = 1; next } on && NF == 0 { exit } on' "$mctx/probes.txt" >"$SCRATCH/schema"
printf 'app/migrations/0003_drop_email.py:2\nsql/migration/V4__drop.sql:1\n' >"$SCRATCH/schema-want"
cmp "$SCRATCH/schema-want" "$SCRATCH/schema"
grep -qx 'schema	sql/migration/V4__drop.sql' "$mctx/probe-files.txt"
