#!/bin/sh
# Append one summary line per finished run to the state root's stats file.
# Usage: sh scripts/run-stats.sh <state-dir> <outcome>
#
# The stats file is the evidence loop: routing thresholds, the gap-pass
# rule, and the filter earn their tuning from these lines instead of
# guesses. Each finding retried after a failed attempt counts once, by
# what its last retry changed (the model, else only the effort) and
# whether it ended verified: the evidence for when a stronger model
# beats more effort. Run it before cleanup-state.sh, which removes
# pr-context.
set -eu

dir=${1:?usage: run-stats.sh <state-dir> <outcome>}
outcome=${2:?usage: run-stats.sh <state-dir> <outcome>}
case "$outcome" in
merged | parked | held | review-only) ;;
*)
	echo "run-stats: outcome must be merged, parked, held, or review-only: $outcome" >&2
	exit 1
	;;
esac
[ -f "$dir/meta.txt" ] || {
	echo "run-stats: no meta.txt in $dir" >&2
	exit 1
}
owner=$(sed -n 's/^owner //p' "$dir/meta.txt")
repo=$(sed -n 's/^repo //p' "$dir/meta.txt")
pr=$(sed -n 's/^pr //p' "$dir/meta.txt")

rounds=0
[ -f "$dir/rounds.txt" ] && rounds=$(cat "$dir/rounds.txt")

total=0 verified=0 wontfix=0 open=0 reopens=0 demoted=0 contracts=0 samples=1
model_climbs=0 model_climbs_verified=0 effort_climbs=0 effort_climbs_verified=0
for f in "$dir/findings"/F*; do
	[ -f "$f" ] || continue
	total=$((total + 1))
	case "$(sed -n 's/^status: //p' "$f")" in
	verified) verified=$((verified + 1)) ;;
	wont-fix) wontfix=$((wontfix + 1)) ;;
	open | addressed) open=$((open + 1)) ;;
	esac
	r=$(sed -n 's/^reopens: //p' "$f")
	[ "${r:-0}" -gt "$reopens" ] && reopens=$r
	grep -q '^Filter: ' "$f" && demoted=$((demoted + 1))
	grep -q '^Check: ' "$f" && contracts=$((contracts + 1))
	s=$(sed -n 's/^support: [0-9]*\///p' "$f" | head -n 1)
	[ "${s:-1}" -gt "$samples" ] && samples=$s
	# What the last retry changed: the model, else only the effort. A
	# pinned note ran at the pinned level, whatever the route said.
	climb=$(awk '/^Route: / { n++; pm = m; pe = e; m = $7; e = ($10 == "pinned") ? "pinned-" $11 : ($8 == "effort") ? $9 : "" }
		END { if (n < 2) print "none"; else if (m != pm) print "model"; else if (e != pe) print "effort"; else print "none" }' "$f")
	ok=0
	grep -q '^status: verified$' "$f" && ok=1
	case "$climb" in
	model) model_climbs=$((model_climbs + 1)) model_climbs_verified=$((model_climbs_verified + ok)) ;;
	effort) effort_climbs=$((effort_climbs + 1)) effort_climbs_verified=$((effort_climbs_verified + ok)) ;;
	esac
done

kind=none
[ -f "$dir/pr-context/class.txt" ] &&
	kind=$(sed -n 's/^classify-change: kind \([a-z-]*\).*/\1/p' "$dir/pr-context/class.txt")
groups=1
[ -f "$dir/pr-context/shards.txt" ] && groups=$(grep -c . "$dir/pr-context/shards.txt")
seams=0
[ -f "$dir/pr-context/seams.txt" ] && seams=$(grep -c . "$dir/pr-context/seams.txt")

routes=0 cheap=0 base=0 strong=0 strong_wanted=0 escalations=0
effort_low=0 effort_medium=0 effort_high=0 effort_xhigh=0 pinned=0
[ -f "$dir/pr-context/routes.txt" ] && {
	routes=$(grep -c '^route ' "$dir/pr-context/routes.txt" || true)
	cheap=$(grep -c ' rung cheap ' "$dir/pr-context/routes.txt" || true)
	base=$(grep -c ' rung base ' "$dir/pr-context/routes.txt" || true)
	strong=$(grep -c ' rung strong ' "$dir/pr-context/routes.txt" || true)
	strong_wanted=$(grep -c ' reason strong-wanted-unset' "$dir/pr-context/routes.txt" || true)
	escalations=$(grep -c ' reason \(escalated\|gate-failed\|mixed\) ' "$dir/pr-context/routes.txt" || true)
	effort_low=$(grep -c ' effort low ' "$dir/pr-context/routes.txt" || true)
	effort_medium=$(grep -c ' effort medium ' "$dir/pr-context/routes.txt" || true)
	effort_high=$(grep -c ' effort high ' "$dir/pr-context/routes.txt" || true)
	effort_xhigh=$(grep -c ' effort xhigh ' "$dir/pr-context/routes.txt" || true)
	pinned=$(grep -c ' pinned ' "$dir/pr-context/routes.txt" || true)
}

# The highest source any setting came from: run, local, project, or none.
config=none
if [ -f "$dir/sources.txt" ]; then
	for s in project local run; do
		grep -q " $s\$" "$dir/sources.txt" && config=$s
	done
fi

root=$(CDPATH= cd -- "$dir/.." && pwd)
line="run $owner/$repo#$pr outcome $outcome rounds $rounds findings $total verified $verified wont-fix $wontfix unresolved $open reopens $reopens demoted $demoted contracts $contracts samples $samples kind $kind groups $groups seams $seams routes $routes cheap $cheap base $base strong $strong strong_wanted $strong_wanted escalations $escalations effort_low $effort_low effort_medium $effort_medium effort_high $effort_high effort_xhigh $effort_xhigh pinned $pinned model_climbs $model_climbs model_climbs_verified $model_climbs_verified effort_climbs $effort_climbs effort_climbs_verified $effort_climbs_verified config $config"
printf '%s\n' "$line" >>"$root/stats.txt"
echo "run-stats: $line"
