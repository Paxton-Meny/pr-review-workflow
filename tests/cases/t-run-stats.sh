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
printf 'route review all rung cheap model sonnet effort medium reason docs-only-small\nroute gap all rung base model inherit effort high pinned max reason follows-reviewer\nroute edit all rung strong model opus effort xhigh reason x ids F001\n' >"$dir/pr-context/routes.txt"

# F001's retry changed the model and was verified; F003's changed only
# the effort and stayed open; F002 was attempted once, so it never retried.
printf 'id: F001\nstatus: verified\nreopens: 1\nplacement: inline\n---\nbody\nCheck: pytest t\nResolution: done.\nRoute: round 1 rung cheap model sonnet effort low reason mechanical\nRoute: round 2 rung strong model opus effort medium reason escalated\n' >"$dir/findings/F001"
printf 'id: F002\nstatus: wont-fix\nreopens: 0\nsupport: 1/2\nplacement: summary\n---\nbody\nFilter: thin evidence.\nResolution: done.\nRoute: round 1 rung base model inherit reason role-model\n' >"$dir/findings/F002"
printf 'id: F003\nstatus: open\nreopens: 0\nplacement: inline\n---\nbody\nResolution: done.\nRoute: round 1 rung base model inherit effort medium reason role-model\nRoute: round 2 rung base model inherit effort high reason strong-wanted-unset\n' >"$dir/findings/F003"
# F004's retry raised the routed effort under a pinned level, so nothing changed.
printf 'id: F004\nstatus: verified\nreopens: 1\nplacement: inline\n---\nbody\nResolution: done.\nRoute: round 1 rung base model inherit effort medium pinned low reason role-model\nRoute: round 2 rung base model inherit effort high pinned low reason strong-wanted-unset\n' >"$dir/findings/F004"

out=$(sh "$REPO_ROOT/scripts/run-stats.sh" "$dir" parked)
[ "$out" = "run-stats: run o/r#7 outcome parked rounds 2 findings 4 verified 2 wont-fix 1 unresolved 1 reopens 1 demoted 1 contracts 1 samples 2 kind code groups 2 seams 1 routes 3 cheap 1 base 1 strong 1 strong_wanted 0 escalations 0 effort_low 0 effort_medium 1 effort_high 1 effort_xhigh 1 pinned 1 model_climbs 1 model_climbs_verified 1 effort_climbs 1 effort_climbs_verified 0 config none" ]
grep -qx 'run o/r#7 outcome parked rounds 2 findings 4 verified 2 wont-fix 1 unresolved 1 reopens 1 demoted 1 contracts 1 samples 2 kind code groups 2 seams 1 routes 3 cheap 1 base 1 strong 1 strong_wanted 0 escalations 0 effort_low 0 effort_medium 1 effort_high 1 effort_xhigh 1 pinned 1 model_climbs 1 model_climbs_verified 1 effort_climbs 1 effort_climbs_verified 0 config none' "$root/stats.txt"

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
