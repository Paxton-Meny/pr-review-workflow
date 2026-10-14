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
printf 'route review all rung cheap model sonnet effort medium reason docs-only-small\nroute gap all rung base model inherit effort high pinned max reason follows-reviewer\nroute edit all rung strong model opus effort xhigh reason x ids F001\nroute edit all rung base model inherit effort high reason more-effort ids F003\nroute edit all rung base model inherit effort high unapplied medium reason stakes-floor ids F011\n' >"$dir/pr-context/routes.txt"

# Every retry counts once, by what changed from the attempt before.
# F001 climbed the model twice and then only the effort, and is still
# open: three failed retries. F003 raised only the effort and was
# verified. F004 and F008 changed nothing that ran (a pinned level both
# times, or the same level pinned and unpinned) and were verified.
# F005's repair belongs to its first round, so it never retried. F006
# was verified by arbitration over a reopen, and F007 ended wont-fix,
# so neither last retry counts. F009's last fix broke the check and was
# never verified: a failed model retry. F010's first note predates
# effort, so its same-model retry is left out. F002 holds one old note.
# F011 and F012 ran at the editor's own level each time because the
# spawn tool took no effort, once across a resume from a session whose
# tool did: plain retries, verified.
note() { printf 'Route: round %s rung x model %s %s reason r\n' "$@"; }
finding() { printf 'id: %s\nstatus: %s\nreopens: %s\nplacement: inline\n---\nbody\nResolution: done.\n' "$1" "$2" "${3:-0}" >"$dir/findings/$1"; }
finding F001 open 1
printf 'Check: pytest t\n' >>"$dir/findings/F001"
{ note 1 sonnet 'effort low'; note 2 inherit 'effort medium'; note 3 opus 'effort high'; note 4 opus 'effort xhigh'; } >>"$dir/findings/F001"
printf 'id: F002\nstatus: wont-fix\nreopens: 0\nsupport: 1/2\nplacement: summary\n---\nbody\nFilter: thin evidence.\nResolution: done.\nRoute: round 1 rung base model inherit reason role-model\n' >"$dir/findings/F002"
finding F003 verified
{ note 1 inherit 'effort medium'; note 2 inherit 'effort high'; } >>"$dir/findings/F003"
finding F004 verified
{ note 1 inherit 'effort medium pinned low'; note 2 inherit 'effort high pinned low'; } >>"$dir/findings/F004"
finding F005 verified
{ note 1 sonnet 'effort low'; note 1 inherit 'effort medium'; } >>"$dir/findings/F005"
finding F006 verified
{ note 1 inherit 'effort medium'; note 2 opus 'effort high'; printf 'Reopened (round 2): still fails.\nArbitrated: verified from open, over the last reopen.\n'; } >>"$dir/findings/F006"
finding F007 wont-fix
{ note 1 sonnet 'effort low'; note 2 inherit 'effort medium'; } >>"$dir/findings/F007"
finding F008 verified
{ note 1 inherit 'effort low pinned high'; note 2 inherit 'effort high'; } >>"$dir/findings/F008"
finding F009 addressed
{ note 1 sonnet 'effort low'; note 2 inherit 'effort medium'; } >>"$dir/findings/F009"
finding F010 verified
{ printf 'Route: round 1 rung base model inherit reason role-model\n'; note 2 inherit 'effort high'; } >>"$dir/findings/F010"
finding F011 verified
{ note 1 inherit 'effort medium unapplied medium'; note 2 inherit 'effort high unapplied medium'; } >>"$dir/findings/F011"
finding F012 verified
{ note 1 inherit 'effort medium'; note 2 inherit 'effort high unapplied medium'; } >>"$dir/findings/F012"

out=$(sh "$REPO_ROOT/scripts/run-stats.sh" "$dir" parked)
[ "$out" = "run-stats: run o/r#7 outcome parked rounds 2 findings 12 verified 8 wont-fix 2 unresolved 2 reopens 1 demoted 1 contracts 1 samples 2 kind code groups 2 seams 1 routes 5 cheap 1 base 3 strong 1 strong_wanted 0 escalations 1 effort_low 0 effort_medium 1 effort_high 3 effort_xhigh 1 pinned 1 unapplied 1 model_retries 3 model_retries_verified 0 effort_retries 2 effort_retries_verified 1 same_retries 4 same_retries_verified 4 config none method none ci unknown ci_rounds 0" ]
grep -qx 'run o/r#7 outcome parked rounds 2 findings 12 verified 8 wont-fix 2 unresolved 2 reopens 1 demoted 1 contracts 1 samples 2 kind code groups 2 seams 1 routes 5 cheap 1 base 3 strong 1 strong_wanted 0 escalations 1 effort_low 0 effort_medium 1 effort_high 3 effort_xhigh 1 pinned 1 unapplied 1 model_retries 3 model_retries_verified 0 effort_retries 2 effort_retries_verified 1 same_retries 4 same_retries_verified 4 config none method none ci unknown ci_rounds 0' "$root/stats.txt"

[ "$(cat "$dir/outcome.txt")" = parked ]
printf 'pass abc\n' >"$dir/ci-result.txt"
printf '1\n' >"$dir/ci-rounds.txt"
sh "$REPO_ROOT/scripts/run-stats.sh" "$dir" merged >/dev/null
[ "$(grep -c . "$root/stats.txt")" = "2" ]
grep -q ' outcome merged .* ci repaired ci_rounds 1$' "$root/stats.txt"
[ "$(cat "$dir/outcome.txt")" = merged ]

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
