#!/bin/sh
# match-paths: prints exactly the paths a resolved path-glob setting matches.
set -eu

. "$REPO_ROOT/tests/fixture-identity.sh"
dir="$SCRATCH/data/state/${fixture_owner}__widgets__7"
mkdir -p "$dir"
printf 'owner %s\nrepo widgets\npr 7\n' "$fixture_owner" >"$dir/meta.txt"
match() { sh "$REPO_ROOT/scripts/match-paths.sh" "$dir" "$1"; }

if printf 'a\n' | match migration_paths 2>"$SCRATCH/err"; then
	echo "expected failure before the settings are resolved" >&2
	exit 1
fi
grep -q "no settings.txt" "$SCRATCH/err"

: | sh "$REPO_ROOT/scripts/resolve-settings.sh" "$dir" >/dev/null
cat >"$SCRATCH/paths" <<'END'
app/migrations/0002_add_email.py
db/migrate/20261013120000_add_index.rb
alembic/versions/ab12_drop.py
src/Migrations/20261013_Init.cs
sql/migration/V3__users.sql
src/migrate.py
docs/migrations.md
README.md

END
cat >"$SCRATCH/want" <<'END'
app/migrations/0002_add_email.py
db/migrate/20261013120000_add_index.rb
alembic/versions/ab12_drop.py
src/Migrations/20261013_Init.cs
sql/migration/V3__users.sql
END
match migration_paths <"$SCRATCH/paths" >"$SCRATCH/got"
cmp "$SCRATCH/want" "$SCRATCH/got"

: | match sensitive_paths >"$SCRATCH/got"
[ ! -s "$SCRATCH/got" ]

mkdir -p "$SCRATCH/cwd/schema"
: >"$SCRATCH/cwd/schema/a.sql"
printf 'migration_paths schema/*\n' | sh "$REPO_ROOT/scripts/resolve-settings.sh" "$dir" >/dev/null
out=$(cd "$SCRATCH/cwd" && printf 'schema/b.sql\napp/migrations/0002_add_email.py\n' | match migration_paths)
[ "$out" = "schema/b.sql" ]

if printf 'a\n' | match check_command 2>"$SCRATCH/err"; then
	echo "expected refusal of a setting that is not a path list" >&2
	exit 1
fi
grep -q "not a path setting: check_command" "$SCRATCH/err"
