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

# Verification keeps what the clone confirms and names every drop.
out=$(printf 'survey: check makefile make check\n' | verify "$dir")
printf '%s\n' "$out" | grep -qx 'verify: dropped 1 layout docs/'
printf '%s\n' "$out" | grep -qx 'verify: dropped 1 tests tests/test_missing.py'
printf '%s\n' "$out" | grep -qx 'verify: dropped 1 check sh scripts/nope.sh'
printf '%s\n' "$out" | grep -qx 'verify: dropped 1 check npm test'
printf '%s\n' "$out" | grep -qx 'verify: dropped 1 check curl https://host'
printf '%s\n' "$out" | grep -qx 'verify: records 2 claims 12 kept 6 dropped 5'
grep -qxF '1 layout src/auth/** | authentication code' "$dir/digest.txt"
grep -qx '1 layout src/ | all sources' "$dir/digest.txt"
grep -qx '1 check make check | the Makefile gate' "$dir/digest.txt"
grep -qx '1 check sh scripts/gate.sh | the gate script' "$dir/digest.txt"
grep -qx '2 rules README.md | the readme states the rules' "$dir/digest.txt"
! grep -q 'said twice' "$dir/digest.txt"
[ "$(grep -c . "$dir/digest.txt")" -eq 6 ]
# Without the survey's candidate, make check still stands on the Makefile.
out=$(verify "$dir" </dev/null)
grep -qx '1 check make check | the Makefile gate' "$dir/digest.txt"

# A migrations claim stands only as a tracked directory, and a check
# naming migration or database tooling never stands, whatever backs it.
mkdir -p "$clone/db/changes"
printf 'ALTER TABLE users ADD email TEXT;\n' >"$clone/db/changes/0001.sql"
git -C "$clone" add -A
git -C "$clone" commit --quiet -m changes
printf 'partition 3\n' >"$dir/partitions/3.txt"
record "$dir" 3 >/dev/null <<'R'
## migrations
migrations db/changes/ | schema changes go here
migrations db/missing/ | no such directory
migrations db/changes/0001.sql | a file, not a directory
## check
check sqlcmd -i check.sql | runs a script against the server
check make migrate | a Makefile target that migrates
R
out=$(printf 'survey: check makefile make check\n' | verify "$dir")
grep -qx '3 migrations db/changes/ | schema changes go here' "$dir/digest.txt"
printf '%s\n' "$out" | grep -qx 'verify: dropped 3 migrations db/missing/'
printf '%s\n' "$out" | grep -qx 'verify: dropped 3 migrations db/changes/0001.sql'
printf '%s\n' "$out" | grep -qx 'verify: dropped 3 check sqlcmd -i check.sql (migration or database tooling)'
printf '%s\n' "$out" | grep -qx 'verify: dropped 3 check make migrate (migration or database tooling)'
if grep -qE '^3 check ' "$dir/digest.txt"; then
	echo "a check naming migration tooling must never stand" >&2
	exit 1
fi

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

# Refusals without state.
if verify "$SCRATCH/nowhere" </dev/null 2>/dev/null; then
	echo "expected refusal without meta.txt" >&2
	exit 1
fi
rm "$dir/digest.txt"
if printf 'x\n' | proposal "$dir" 2>/dev/null; then
	echo "expected refusal without a digest" >&2
	exit 1
fi
