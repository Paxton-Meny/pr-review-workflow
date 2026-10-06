#!/bin/sh
# run-stats: field extraction, appending, outcome validation.
set -eu

root="$SCRATCH/state-root"
dir="$root/o__r__7"
mkdir -p "$dir/findings" "$dir/pr-context"
printf 'owner o\nrepo r\npr 7\n' >"$dir/meta.txt"
printf '2\n' >"$dir/rounds.txt"
printf 'classify-change: kind code files 3 lines 900\n' >"$dir/pr-context/class.txt"
printf 'group 1 lines 500 files 001\ngroup 2 lines 400 files 002\n' >"$dir/pr-context/shards.txt"
printf 'a and b split across groups 1 and 2 (shared name: x)\n' >"$dir/pr-context/seams.txt"
printf 'route review all rung cheap model sonnet reason docs-only-small\nroute gap all rung base model inherit reason follows-reviewer\nroute edit all rung strong model opus reason x ids F001\n' >"$dir/pr-context/routes.txt"

printf 'id: F001\nstatus: verified\nreopens: 1\nplacement: inline\n---\nbody\nCheck: pytest t\nResolution: done.\n' >"$dir/findings/F001"
printf 'id: F002\nstatus: wont-fix\nreopens: 0\nsupport: 1/2\nplacement: summary\n---\nbody\nFilter: thin evidence.\nResolution: done.\n' >"$dir/findings/F002"
printf 'id: F003\nstatus: open\nreopens: 0\nplacement: inline\n---\nbody\nResolution: done.\n' >"$dir/findings/F003"

out=$(sh "$REPO_ROOT/scripts/run-stats.sh" "$dir" parked)
[ "$out" = "run-stats: run o/r#7 outcome parked rounds 2 findings 3 verified 1 wont-fix 1 unresolved 1 reopens 1 demoted 1 contracts 1 samples 2 kind code groups 2 seams 1 routes 3 cheap 1 base 1 strong 1 strong_wanted 0" ]
grep -qx 'run o/r#7 outcome parked rounds 2 findings 3 verified 1 wont-fix 1 unresolved 1 reopens 1 demoted 1 contracts 1 samples 2 kind code groups 2 seams 1 routes 3 cheap 1 base 1 strong 1 strong_wanted 0' "$root/stats.txt"

sh "$REPO_ROOT/scripts/run-stats.sh" "$dir" merged >/dev/null
[ "$(grep -c . "$root/stats.txt")" = "2" ]

if sh "$REPO_ROOT/scripts/run-stats.sh" "$dir" wat 2>"$SCRATCH/err"; then
	echo "expected refusal of an unknown outcome" >&2
	exit 1
fi
grep -q "outcome must be" "$SCRATCH/err"

if sh "$REPO_ROOT/scripts/run-stats.sh" "$SCRATCH/empty" merged 2>"$SCRATCH/err"; then
	echo "expected failure without meta" >&2
	exit 1
fi
grep -q "no meta.txt" "$SCRATCH/err"
