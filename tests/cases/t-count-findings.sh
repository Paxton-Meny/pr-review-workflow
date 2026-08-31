#!/bin/sh
# count-findings: per-status counts, reopen maximum, convergence exit codes.
set -eu

dir="$SCRATCH/state"
mkdir -p "$dir"
printf '0\n' >"$dir/round.txt"
printf '=== finding\ncategory: correctness\nseverity: major\npath: a.c\nline: 1\nside: RIGHT\ntitle: One\n---\nResolution: done.\n=== finding\ncategory: security\nseverity: nit\npath: b.c\nline: 2\nside: RIGHT\ntitle: Two\n---\nResolution: done.\n=== finding\ncategory: performance\nseverity: minor\npath: c.c\nline: 3\nside: RIGHT\ntitle: Three\n---\nResolution: done.\n' \
	| sh "$REPO_ROOT/scripts/save-findings.sh" "$dir" >/dev/null

out=$(sh "$REPO_ROOT/scripts/count-findings.sh" "$dir") && {
	echo "expected exit 3 while findings are open" >&2
	exit 1
}
[ "$out" = "open 3 addressed 0 verified 0 wont-fix 0 max_reopens 0" ]

sh "$REPO_ROOT/scripts/update-finding.sh" "$dir" F001 status=addressed >/dev/null
sh "$REPO_ROOT/scripts/update-finding.sh" "$dir" F001 status=open >/dev/null
sh "$REPO_ROOT/scripts/update-finding.sh" "$dir" F001 status=addressed >/dev/null
sh "$REPO_ROOT/scripts/update-finding.sh" "$dir" F001 status=verified >/dev/null
sh "$REPO_ROOT/scripts/update-finding.sh" "$dir" F002 status=wont-fix >/dev/null
sh "$REPO_ROOT/scripts/update-finding.sh" "$dir" F003 status=addressed >/dev/null

out=$(sh "$REPO_ROOT/scripts/count-findings.sh" "$dir")
[ "$out" = "open 0 addressed 1 verified 1 wont-fix 1 max_reopens 1" ]

if sh "$REPO_ROOT/scripts/count-findings.sh" "$SCRATCH/empty" 2>"$SCRATCH/err"; then
	echo "expected failure without a findings directory" >&2
	exit 1
fi
grep -q "no findings directory" "$SCRATCH/err"

out=$(sh "$REPO_ROOT/scripts/count-findings.sh" "$dir" --list)
printf '%s\n' "$out" | grep -qx 'addressed_ids F003'
printf '%s\n' "$out" | grep -qx 'verified_ids F001'
printf '%s\n' "$out" | grep -qx 'wont_fix_ids F002'
printf '%s\n' "$out" | grep -qx 'open_ids'

if sh "$REPO_ROOT/scripts/count-findings.sh" "$dir" --wat 2>"$SCRATCH/err"; then
	echo "expected refusal of an unknown argument" >&2
	exit 1
fi
grep -q "unknown argument" "$SCRATCH/err"
