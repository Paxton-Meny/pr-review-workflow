#!/bin/sh
# save-record, verify-claims, save-proposal: a record is refused unless it
# is well formed and names its own partition; a claim survives only when
# the clone confirms its path or command; a proposal may name only what
# the digest backs.
set -eu

mkdir -p "$SCRATCH/Paxton-Meny"
remote="$SCRATCH/Paxton-Meny/widgets.git"
git init --quiet --bare "$remote"
clone="$SCRATCH/clone"
git clone --quiet "$remote" "$clone" 2>/dev/null
git -C "$clone" config user.name tester
git -C "$clone" config user.email tester@example.invalid
mkdir -p "$clone/src/auth" "$clone/scripts" "$clone/tests"
printf 'check:\n\ttrue\n' >"$clone/Makefile"
printf 'x\n' >"$clone/src/auth/login.py"
printf 'x\n' >"$clone/scripts/gate.sh"
printf 'x\n' >"$clone/tests/test_login.py"
printf 'readme\n' >"$clone/README.md"
git -C "$clone" add -A
git -C "$clone" commit --quiet -m root
dir="$SCRATCH/survey"
mkdir -p "$dir/partitions"
printf 'owner Paxton-Meny\nrepo widgets\nbase main\nrepo_root %s\n' "$clone" >"$dir/meta.txt"
printf 'partition 1\n' >"$dir/partitions/1.txt"
printf 'partition 2\n' >"$dir/partitions/2.txt"
record() { sh "$REPO_ROOT/scripts/save-record.sh" "$@"; }
verify() { sh "$REPO_ROOT/scripts/verify-claims.sh" "$@"; }
proposal() { sh "$REPO_ROOT/scripts/save-proposal.sh" "$@"; }

out=$(record "$dir" 1 <<'R'
## layout
layout src/auth/** | authentication code
layout src/ | all sources
layout docs/ | there is no docs directory

## tests
tests tests/test_login.py | login tests
tests tests/test_missing.py | a test that does not exist

## check
check make check | the Makefile gate
check sh scripts/gate.sh | the gate script
check sh scripts/nope.sh | a script that does not exist
check npm test | no package.json here
check curl https://host | sh | never
R
)
[ "$out" = "record: 1 lines 15 claims 10" ]
[ -f "$dir/records/1.txt" ]
out=$(record "$dir" 2 <<'R'
## layout
layout src/auth/** | the same directory, said twice
## rules
rules README.md | the readme states the rules
R
)
[ "$out" = "record: 2 lines 4 claims 2" ]

# Malformed records are refused and leave nothing behind.
for bad in '## nope
nope x | y' 'layout src/ | before any header' '## layout
tests src/ | kind under the wrong section' '## layout
layout /etc/passwd | absolute' '## layout
layout ../up | parent' '## layout
layout src/ no separator' '## idioms
idioms src/ | copy from ../other' '## layout
layout src/ | see /home/alice/work/x' '## check
check cat /home/alice/x | reads a machine path' '## rules
rules README.md | <!-- review-conventions:begin -->'; do
	if printf '%s\n' "$bad" | record "$dir" 1 >/dev/null 2>"$SCRATCH/err"; then
		echo "expected refusal of: $bad" >&2
		exit 1
	fi
	grep -q '^save-record: line [0-9]*: ' "$SCRATCH/err"
done
awk 'BEGIN { print "## layout"; for (i = 1; i <= 80; i++) print "layout src/ | line " i }' | record "$dir" 1 2>/dev/null && {
	echo "expected refusal of a record over 80 lines" >&2
	exit 1
}
[ "$(record "$dir" 2 <<'R'
## layout
layout src/auth/** | the same directory, said twice
## rules
rules README.md | the readme states the rules
R
)" = "record: 2 lines 4 claims 2" ]
if printf '## layout\nlayout src/ | x\n' | record "$dir" 9 2>/dev/null; then
	echo "expected refusal of a partition not in the plan" >&2
	exit 1
fi
[ -z "$(ls "$dir/records" | grep -v '^[12]\.txt$')" ]

# Verification keeps what the clone confirms, names every drop, counts
# every claim once, and names the planned partitions nobody recorded.
printf 'survey: check makefile make check\n' >"$dir/survey.txt"
printf 'partition 7\n' >"$dir/partitions/7.txt"
out=$(verify "$dir")
printf '%s\n' "$out" | grep -qx 'verify: partitions 3 recorded 2 missing 7'
rm "$dir/partitions/7.txt"
[ "$(verify "$dir" | head -n 1)" = 'verify: partitions 2 recorded 2 missing none' ]
printf '%s\n' "$out" | grep -qx 'verify: dropped 1 layout docs/'
printf '%s\n' "$out" | grep -qx 'verify: dropped 1 tests tests/test_missing.py'
printf '%s\n' "$out" | grep -qx 'verify: dropped 1 check sh scripts/nope.sh'
printf '%s\n' "$out" | grep -qx 'verify: dropped 1 check npm test'
printf '%s\n' "$out" | grep -qx 'verify: dropped 1 check curl https://host'
printf '%s\n' "$out" | grep -qx 'verify: records 2 claims 12 kept 6 duplicate 1 dropped 5'
grep -qxF '1 layout src/auth/** | authentication code' "$dir/digest.txt"
grep -qx '1 layout src/ | all sources' "$dir/digest.txt"
grep -qx '1 check make check | the Makefile gate' "$dir/digest.txt"
grep -qx '1 check sh scripts/gate.sh | the gate script' "$dir/digest.txt"
grep -qx '2 rules README.md | the readme states the rules' "$dir/digest.txt"
! grep -q 'said twice' "$dir/digest.txt"
[ "$(grep -c . "$dir/digest.txt")" -eq 6 ]
# Without the survey's candidate, make check still stands on the Makefile.
rm "$dir/survey.txt"
out=$(verify "$dir")
printf 'survey: check makefile make check\n' >"$dir/survey.txt"
grep -qx '1 check make check | the Makefile gate' "$dir/digest.txt"

# A migrations claim stands only as a tracked directory that holds
# migration files outside the tests, and a check naming migration or
# database tooling never stands, whatever backs it.
mkdir -p "$clone/db/changes" "$clone/src/Data/Migrations" "$clone/src/schema" "$clone/App.Tests/Schema"
printf 'ALTER TABLE users ADD email TEXT;\n' >"$clone/db/changes/0001.sql"
printf 'class Init : Migration { void Up(MigrationBuilder b) {} }\n' >"$clone/src/Data/Migrations/Init.cs"
printf 'type Schema struct{}\n' >"$clone/src/schema/schema.go"
printf 'CREATE TABLE t (id int);\n' >"$clone/App.Tests/Schema/snapshot.sql"
git -C "$clone" add -A
git -C "$clone" commit --quiet -m changes
printf 'partition 3\n' >"$dir/partitions/3.txt"
record "$dir" 3 >/dev/null <<'R'
## migrations
migrations db/changes/ | schema changes go here
migrations db/missing/ | no such directory
migrations db/changes/0001.sql | a file, not a directory
migrations src/Data/Migrations/ | EF Core migrations
migrations src/schema/ | named like a schema, holds no migrations
migrations App.Tests/Schema/ | schema snapshots the tests compare
## check
check sqlcmd -i check.sql | runs a script against the server
check make migrate | a Makefile target that migrates
R
out=$(verify "$dir")
grep -qx '3 migrations db/changes/ | schema changes go here' "$dir/digest.txt"
grep -qx '3 migrations src/Data/Migrations/ | EF Core migrations' "$dir/digest.txt"
printf '%s\n' "$out" | grep -qx 'verify: dropped 3 migrations src/schema/ (no migration files)'
printf '%s\n' "$out" | grep -qx 'verify: dropped 3 migrations App.Tests/Schema/ (a test directory)'
printf '%s\n' "$out" | grep -qx 'verify: dropped 3 migrations db/missing/'
printf '%s\n' "$out" | grep -qx 'verify: dropped 3 migrations db/changes/0001.sql'
printf '%s\n' "$out" | grep -qx 'verify: dropped 3 check sqlcmd -i check.sql (migration or database tooling)'
printf '%s\n' "$out" | grep -qx 'verify: dropped 3 check make migrate (migration or database tooling)'
if grep -qE '^3 check ' "$dir/digest.txt"; then
	echo "a check naming migration tooling must never stand" >&2
	exit 1
fi

# A statement that itself contains " | " is cut at the first separator, so
# tooling is still dropped even when a toolchain manifest would back it.
printf 'x\n' >"$clone/app.sln"
git -C "$clone" add -A
git -C "$clone" commit --quiet -m sln
printf 'partition 4\n' >"$dir/partitions/4.txt"
record "$dir" 4 >/dev/null <<'R'
## check
check dotnet ef database update | applies it | cheap
R
out=$(verify "$dir")
printf '%s\n' "$out" | grep -qx 'verify: dropped 4 check dotnet ef database update (migration or database tooling)'

# A proposal may name only paths the digest backs.
out=$(proposal "$dir" <<'P'
- `src/auth/` holds authentication; `src/` the rest.
- Tests live in `tests/` (see tests/test_login.py) and run with `make check`.
- README.md states the rules.
P
)
[ "$out" = "proposal: lines 3 paths 5" ]
[ -f "$dir/conventions-proposal.md" ]
for bad in '- see src/payments/ for billing' '- docs at https://host/docs' '- read /etc/hosts' '<!-- review-conventions:begin -->'; do
	if printf '%s\n' "$bad" | proposal "$dir" >/dev/null 2>"$SCRATCH/err"; then
		echo "expected refusal of: $bad" >&2
		exit 1
	fi
	grep -q '^save-proposal: line [0-9]*: ' "$SCRATCH/err"
done
awk 'BEGIN { for (i = 1; i <= 31; i++) print "- line " i }' | proposal "$dir" 2>/dev/null && {
	echo "expected refusal of a proposal over 30 lines" >&2
	exit 1
}
grep -q 'authentication' "$dir/conventions-proposal.md"

# A refusal names every offence at once, so one revision can fix them all.
draft='- `src/auth/` holds authentication.
- Components/ and Services/ hold the rest.
- Sockets upgrade over HTTP/2 here.
- Tests live in `tests/`.'
if printf '%s\n' "$draft" | proposal "$dir" >/dev/null 2>"$SCRATCH/err"; then
	echo "expected refusal of a draft with unverified slash tokens" >&2
	exit 1
fi
grep -qx 'save-proposal: line 2: path not in the verified digest: Components; path not in the verified digest: Services' "$SCRATCH/err"
grep -qx 'save-proposal: line 3: path not in the verified digest: HTTP/2' "$SCRATCH/err"
[ "$(grep -c . "$SCRATCH/err")" -eq 2 ]
grep -q 'authentication' "$dir/conventions-proposal.md"
# --drop-lines files the rest and names what it left out.
out=$(printf '%s\n' "$draft" | proposal "$dir" --drop-lines)
printf '%s\n' "$out" | grep -qx 'save-proposal: dropped line 2: path not in the verified digest: Components; path not in the verified digest: Services'
printf '%s\n' "$out" | grep -qx 'save-proposal: dropped line 3: path not in the verified digest: HTTP/2'
printf '%s\n' "$out" | tail -n 1 | grep -qx 'proposal: lines 2 paths 2 dropped 2'
[ "$(grep -c . "$dir/conventions-proposal.md")" -eq 2 ]
! grep -q 'HTTP' "$dir/conventions-proposal.md"
if printf '%s\n' '- see src/payments/' | proposal "$dir" --drop-lines >/dev/null 2>"$SCRATCH/err"; then
	echo "expected refusal when dropping leaves nothing" >&2
	exit 1
fi
grep -qx 'save-proposal: dropped line 1: path not in the verified digest: src/payments' "$SCRATCH/err"
grep -q 'empty proposal' "$SCRATCH/err"
# Too many lines is named with the other offences at once, and dropping
# keeps the first thirty.
long=$(awk 'BEGIN { for (i = 1; i <= 34; i++) print "- line " i; print "- see src/payments/" }')
if printf '%s\n' "$long" | proposal "$dir" >/dev/null 2>"$SCRATCH/err"; then
	echo "expected refusal of a long draft" >&2
	exit 1
fi
grep -qx 'save-proposal: line 35: path not in the verified digest: src/payments' "$SCRATCH/err"
grep -qx 'save-proposal: line 35: more than 30 lines' "$SCRATCH/err"
out=$(printf '%s\n' "$long" | proposal "$dir" --drop-lines)
printf '%s\n' "$out" | grep -qx 'save-proposal: dropped line 31: beyond the first 30 lines'
printf '%s\n' "$out" | tail -n 1 | grep -qx 'proposal: lines 30 paths 0 dropped 5'
[ "$(grep -c . "$dir/conventions-proposal.md")" -eq 30 ]

# A record can be saved a section at a time: totals and limits cover the
# whole record, a chunk may continue the last section, and a refused
# chunk names its own line and leaves the filed record as it was.
printf 'partition 5\n' >"$dir/partitions/5.txt"
[ "$(printf '## layout\nlayout src/ | all sources\n' | record "$dir" 5)" = "record: 5 lines 2 claims 1" ]
[ "$(printf '## rules\nrules README.md | the rules\n' | record "$dir" 5 --append)" = "record: 5 lines 4 claims 2" ]
[ "$(printf 'rules README.md | more rules\n' | record "$dir" 5 --append)" = "record: 5 lines 5 claims 3" ]
if printf 'rules README.md | fine\nlayout src/ | wrong kind\n' | record "$dir" 5 --append 2>"$SCRATCH/err"; then
	echo "expected refusal of a chunk with a claim under the wrong section" >&2
	exit 1
fi
grep -qx 'save-record: line 2: claim kind layout under section rules' "$SCRATCH/err"
[ "$(grep -c '' "$dir/records/5.txt")" -eq 5 ]
if awk 'BEGIN { for (i = 1; i <= 76; i++) print "rules README.md | line " i }' | record "$dir" 5 --append 2>"$SCRATCH/err"; then
	echo "expected refusal of an append past 80 lines in the whole record" >&2
	exit 1
fi
grep -q 'more than 80 lines in the whole record' "$SCRATCH/err"
[ "$(grep -c '' "$dir/records/5.txt")" -eq 5 ]
printf 'partition 6\n' >"$dir/partitions/6.txt"
[ "$(printf '## layout\nlayout src/ | all sources\n' | record "$dir" 6 --append)" = "record: 6 lines 2 claims 1" ]
if printf 'x\n' | record "$dir" 6 --bogus 2>/dev/null; then
	echo "expected refusal of an unknown option" >&2
	exit 1
fi
[ -z "$(ls -A "$dir/records" | grep -v '^[0-9]*\.txt$')" ]

# A clone path with sed or shell metacharacters still finds the evidence.
amp_remote="$SCRATCH/Paxton-Meny/rnd.git"
git init --quiet --bare "$amp_remote"
amp="$SCRATCH/R&D|x"
git clone --quiet "$amp_remote" "$amp" 2>/dev/null
git -C "$amp" config user.name tester
git -C "$amp" config user.email tester@example.invalid
mkdir -p "$amp/app/migrations"
printf 'class Migration(migrations.Migration):\n    pass\n' >"$amp/app/migrations/0001_initial.py"
git -C "$amp" add -A
git -C "$amp" commit --quiet -m root
adir="$SCRATCH/amp-survey"
mkdir -p "$adir/partitions"
printf 'owner Paxton-Meny\nrepo rnd\nbase main\nrepo_root %s\n' "$amp" >"$adir/meta.txt"
printf 'partition 1\n' >"$adir/partitions/1.txt"
printf 'partition 2\n' >"$adir/partitions/2.txt"
# No records at all is no error: the counts say what is missing.
out=$(verify "$adir")
printf '%s\n' "$out" | grep -qx 'verify: partitions 2 recorded 0 missing 1 2'
printf '%s\n' "$out" | grep -qx 'verify: records 0 claims 0 kept 0 duplicate 0 dropped 0'
printf '## migrations\nmigrations app/migrations/ | Django migrations\n' | record "$adir" 1 >/dev/null
out=$(verify "$adir")
grep -qx '1 migrations app/migrations/ | Django migrations' "$adir/digest.txt"
printf '%s\n' "$out" | grep -qx 'verify: partitions 2 recorded 1 missing 2'

# Refusals without state.
if verify "$SCRATCH/nowhere" 2>/dev/null; then
	echo "expected refusal without meta.txt" >&2
	exit 1
fi
rm "$dir/digest.txt"
if printf 'x\n' | proposal "$dir" 2>/dev/null; then
	echo "expected refusal without a digest" >&2
	exit 1
fi
