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
