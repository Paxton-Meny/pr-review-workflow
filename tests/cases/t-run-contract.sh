#!/bin/sh
# run-contract: prefix policy, metacharacter ban, pass/fail/fallback exits.
set -eu

dir="$SCRATCH/state"
mkdir -p "$dir/findings" "$dir/worktree"

mkrec() {
	printf 'id: F001\nstatus: open\ncategory: correctness\nseverity: minor\npath: a.sh\nline: 1\nend_line:\nside: RIGHT\nplacement:\ncomment_id:\ncommit:\nround: 1\nreopens: 0\ntitle: T\n---\nevidence\nFix: do.\n%s\nResolution: done.\n' "$1" >"$dir/findings/F001"
}

mkrec 'Check: sh check.sh one'
printf '#!/bin/sh\nexit 0\n' >"$dir/worktree/check.sh"
out=$(sh "$REPO_ROOT/scripts/run-contract.sh" "$dir" F001 'sh check.sh')
[ "$out" = "run-contract: F001 verdict satisfied" ]
out=$(sh "$REPO_ROOT/scripts/run-contract.sh" --policy "$dir" F001 'sh check.sh')
[ "$out" = "run-contract: F001 verdict executable" ]
if sh "$REPO_ROOT/scripts/run-contract.sh" --policy "$dir" F001 'make check' >"$SCRATCH/pol"; then
	echo "policy mode must refuse an unapproved prefix" >&2
	exit 1
fi
[ "$(cat "$SCRATCH/pol")" = "run-contract: F001 verdict not-executable reason unapproved-prefix" ]

printf '#!/bin/sh\necho broken assertion\nexit 1\n' >"$dir/worktree/check.sh"
rc=0
out=$(sh "$REPO_ROOT/scripts/run-contract.sh" "$dir" F001 'sh check.sh') || rc=$?
[ "$rc" -eq 3 ]
printf '%s\n' "$out" | grep -qx 'run-contract: F001 verdict failed'
printf '%s\n' "$out" | grep -q 'broken assertion'

rc=0
out=$(sh "$REPO_ROOT/scripts/run-contract.sh" "$dir" F001 'pytest') || rc=$?
[ "$rc" -eq 4 ]
printf '%s\n' "$out" | grep -q 'unapproved-prefix'

rc=0
out=$(sh "$REPO_ROOT/scripts/run-contract.sh" "$dir" F001 '') || rc=$?
[ "$rc" -eq 4 ]

printf '#!/bin/sh\nexit 0\n' >"$dir/worktree/check.sh"
out=$(sh "$REPO_ROOT/scripts/run-contract.sh" "$dir" F001 'pytest' 'go test, sh check.sh')
[ "$out" = "run-contract: F001 verdict satisfied" ]

mkrec 'Check: sh check.sh; rm -rf /'
rc=0
out=$(sh "$REPO_ROOT/scripts/run-contract.sh" "$dir" F001 'sh check.sh') || rc=$?
[ "$rc" -eq 4 ]
printf '%s\n' "$out" | grep -q 'metacharacters'

mkrec 'Check: sh check.sh $(pwd)'
rc=0
out=$(sh "$REPO_ROOT/scripts/run-contract.sh" "$dir" F001 'sh check.sh') || rc=$?
[ "$rc" -eq 4 ]

mkrec 'Check: sh check.should-not-match'
rc=0
out=$(sh "$REPO_ROOT/scripts/run-contract.sh" "$dir" F001 'sh check.sh') || rc=$?
[ "$rc" -eq 4 ]
printf '%s\n' "$out" | grep -q 'unapproved-prefix'

# Arguments after the prefix stay inside the worktree and literal: no
# absolute, home, or parent paths, also after an =, and no quotes,
# globs, braces, parentheses, comments, or history marks.
printf '#!/bin/sh\n: >unsafe-ran\nexit 0\n' >"$dir/worktree/check.sh"
for line in 'sh check.sh --basetemp=/home/someone/projects' 'sh check.sh /etc' \
	'sh check.sh ~/projects' 'sh check.sh --out=~' 'sh check.sh ../up' 'sh check.sh a/../../b' \
	'sh check.sh a/..' 'sh check.sh ..' 'sh check.sh --cfg=x=/abs' 'sh check.sh --dir=../x' \
	"sh check.sh -k 'x'" 'sh check.sh -k "x"' 'sh check.sh tests/*.py' 'sh check.sh a?b' \
	'sh check.sh [ab]' 'sh check.sh {a,b}' 'sh check.sh (x)' 'sh check.sh #x' 'sh check.sh !x'; do
	mkrec "Check: $line"
	for flag in '' --policy; do
		rc=0
		out=$(sh "$REPO_ROOT/scripts/run-contract.sh" $flag "$dir" F001 'sh check.sh') || rc=$?
		[ "$rc" -eq 4 ] && [ "$out" = "run-contract: F001 verdict not-executable reason unsafe-argument" ] || {
			echo "unsafe argument allowed: $line ($out)" >&2
			exit 1
		}
	done
	[ ! -e "$dir/worktree/unsafe-ran" ]
done
for line in 'sh check.sh ./...' 'sh check.sh ./pkg/... -run TestX' 'sh check.sh --dir=sub/dir a.b' \
	'sh check.sh v1..v2-notes'; do
	mkrec "Check: $line"
	out=$(sh "$REPO_ROOT/scripts/run-contract.sh" "$dir" F001 'sh check.sh')
	[ "$out" = "run-contract: F001 verdict satisfied" ] || {
		echo "safe argument refused: $line ($out)" >&2
		exit 1
	}
done
rm -f "$dir/worktree/unsafe-ran"
# The configured prefix itself is the user's and is not judged.
mkrec 'Check: sh ./check.sh ./...'
out=$(sh "$REPO_ROOT/scripts/run-contract.sh" "$dir" F001 'sh ./check.sh')
[ "$out" = "run-contract: F001 verdict satisfied" ]

printf 'id: F002\nstatus: open\ncategory: correctness\nseverity: minor\npath: a.sh\nline: 1\nend_line:\nside: RIGHT\nplacement:\ncomment_id:\ncommit:\nround: 1\nreopens: 0\ntitle: T\n---\nevidence\nFix: do.\nResolution: done.\n' >"$dir/findings/F002"
rc=0
out=$(sh "$REPO_ROOT/scripts/run-contract.sh" "$dir" F002 'sh check.sh') || rc=$?
[ "$rc" -eq 4 ]
printf '%s\n' "$out" | grep -q 'no-check-line'

if sh "$REPO_ROOT/scripts/run-contract.sh" "$dir" F999 'x' 2>"$SCRATCH/err"; then
	echo "expected failure for an unknown finding" >&2
	exit 1
fi
grep -q "unknown finding" "$SCRATCH/err"

# Migration tooling never runs, even under an allowed prefix: the check
# script leaves a marker if it is ever executed.
printf '#!/bin/sh\n: >ran\nexit 0\n' >"$dir/worktree/check.sh"
for line in 'sh check.sh migrate' 'sh check.sh manage.py makemigrations --check' \
	'sh check.sh db:migrate' 'sh check.sh .venv/bin/alembic upgrade head' \
	'sh check.sh npx prisma db push' 'sh check.sh knex migrate:latest' 'sh check.sh flyway validate' \
	'sh check.sh dotnet ef database update' 'sh check.sh sqlcmd -S . -i deploy.sql'; do
	mkrec "Check: $line"
	rc=0
	out=$(sh "$REPO_ROOT/scripts/run-contract.sh" "$dir" F001 'sh check.sh') || rc=$?
	[ "$rc" -eq 4 ] || {
		echo "migration tooling must not run: $line" >&2
		exit 1
	}
	[ "$out" = "run-contract: F001 verdict not-executable reason migration-tooling" ]
	[ ! -e "$dir/worktree/ran" ]
done
rc=0
out=$(sh "$REPO_ROOT/scripts/run-contract.sh" --policy "$dir" F001 'sh check.sh') || rc=$?
[ "$rc" -eq 4 ]
[ "$out" = "run-contract: F001 verdict not-executable reason migration-tooling" ]

mkrec 'Check: sh check.sh tests/test_migrations_doc.py prisma generate'
out=$(sh "$REPO_ROOT/scripts/run-contract.sh" "$dir" F001 'sh check.sh')
[ "$out" = "run-contract: F001 verdict satisfied" ]
[ -e "$dir/worktree/ran" ]
