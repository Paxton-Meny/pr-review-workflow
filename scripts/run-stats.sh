#!/bin/sh
# Append one summary line per finished run to the state root's stats file.
# Usage: sh scripts/run-stats.sh <state-dir> <outcome>
#
# The stats file is the evidence loop: routing thresholds, the gap-pass
# rule, and the filter earn their tuning from these lines instead of
# guesses. Every retry of a finding counts once, by what it changed from
# the attempt before: the model, else only the effort, else nothing; a
# pair where an older note lacks the effort and the model is unchanged
# is left out, since the effort is unknown. An attempt is a round's last
# Route note, so a repair after a failed check gate is part of its
# round, not a retry. A retry another attempt followed failed; a
# finding's last retry succeeded when the verifier verified it, failed
# when the finding is still open or addressed, and is left out when it
# ended wont-fix or arbitration verified it over a reopen (the
# Arbitrated note update-finding.sh writes). This is the evidence for
# when a stronger model beats more effort, against a plain retry with
# the verifier's note. Run it before cleanup-state.sh, which removes
# pr-context. The outcome is also written to outcome.txt in the state
# directory, where sweep-state.sh and list-runs.sh read it.
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
model_retries=0 model_retries_verified=0 effort_retries=0 effort_retries_verified=0
same_retries=0 same_retries_verified=0
for f in "$dir/findings"/F*; do
	[ -f "$f" ] || continue
	total=$((total + 1))
	case "$(sed -n '/^---$/q; s/^status: //p' "$f")" in
	verified) verified=$((verified + 1)) ;;
	wont-fix) wontfix=$((wontfix + 1)) ;;
	open | addressed) open=$((open + 1)) ;;
	esac
	r=$(sed -n '/^---$/q; s/^reopens: //p' "$f")
	[ "${r:-0}" -gt "$reopens" ] && reopens=$r
	grep -q '^Filter: ' "$f" && demoted=$((demoted + 1))
	grep -q '^Check: ' "$f" && contracts=$((contracts + 1))
	s=$(sed -n '/^---$/q; s/^support: [0-9]*\///p' "$f" | head -n 1)
	[ "${s:-1}" -gt "$samples" ] && samples=$s
	# Retries by what changed, as "model verified effort verified same
	# verified". A pinned note ran at its pinned level, and an unapplied
	# note at the editor's own level, whatever either routed.
	set -- $(awk -v status="$(sed -n '/^---$/q; s/^status: //p' "$f")" '
		/^Route: / {
			if ($3 != round) { k++; round = $3 }
			m[k] = $7; e[k] = ($10 == "pinned" || $10 == "unapplied") ? $11 : ($8 == "effort") ? $9 : ""
		}
		/^Arbitrated: / { arbitrated = 1 }
		END {
			for (i = 2; i <= k; i++) {
				if (m[i] != m[i - 1]) kind = "model"
				else if (e[i] == "" || e[i - 1] == "") continue
				else if (e[i] != e[i - 1]) kind = "effort"
				else kind = "same"
				if (i < k || status == "open" || status == "addressed") n[kind]++
				else if (status == "verified" && !arbitrated) { n[kind]++; v[kind]++ }
			}
			printf "%d %d %d %d %d %d\n", n["model"], v["model"], n["effort"], v["effort"], n["same"], v["same"]
		}' "$f")
	model_retries=$((model_retries + $1)) model_retries_verified=$((model_retries_verified + $2))
	effort_retries=$((effort_retries + $3)) effort_retries_verified=$((effort_retries_verified + $4))
	same_retries=$((same_retries + $5)) same_retries_verified=$((same_retries_verified + $6))
done

kind=none
[ -f "$dir/pr-context/class.txt" ] &&
	kind=$(sed -n 's/^classify-change: kind \([a-z-]*\).*/\1/p' "$dir/pr-context/class.txt")
groups=1
[ -f "$dir/pr-context/shards.txt" ] && groups=$(grep -c . "$dir/pr-context/shards.txt")
seams=0
[ -f "$dir/pr-context/seams.txt" ] && seams=$(grep -c . "$dir/pr-context/seams.txt")

routes=0 cheap=0 base=0 strong=0 strong_wanted=0 escalations=0
effort_low=0 effort_medium=0 effort_high=0 effort_xhigh=0 pinned=0 unapplied=0
[ -f "$dir/pr-context/routes.txt" ] && {
	routes=$(grep -c '^route ' "$dir/pr-context/routes.txt" || true)
	cheap=$(grep -c ' rung cheap ' "$dir/pr-context/routes.txt" || true)
	base=$(grep -c ' rung base ' "$dir/pr-context/routes.txt" || true)
	strong=$(grep -c ' rung strong ' "$dir/pr-context/routes.txt" || true)
	strong_wanted=$(grep -c ' reason strong-wanted-unset' "$dir/pr-context/routes.txt" || true)
	escalations=$(grep -c ' reason \(escalated\|more-effort\|gate-failed\|ci-repeat\|mixed\) ' "$dir/pr-context/routes.txt" || true)
	effort_low=$(grep -c ' effort low ' "$dir/pr-context/routes.txt" || true)
	effort_medium=$(grep -c ' effort medium ' "$dir/pr-context/routes.txt" || true)
	effort_high=$(grep -c ' effort high ' "$dir/pr-context/routes.txt" || true)
	effort_xhigh=$(grep -c ' effort xhigh ' "$dir/pr-context/routes.txt" || true)
	pinned=$(grep -c ' pinned ' "$dir/pr-context/routes.txt" || true)
	unapplied=$(grep -c ' unapplied ' "$dir/pr-context/routes.txt" || true)
}

# The merge method merge-method.sh decided, or none before it ran.
method=none
[ -f "$dir/pr-context/merge-method.txt" ] && method=$(sed -n 's/^method //p' "$dir/pr-context/merge-method.txt")

# The checks' outcome await-checks.sh recorded, repaired when they
# passed after a repair, and the repairs made.
ci=unknown
[ -f "$dir/ci-result.txt" ] && ci=$(cut -d' ' -f1 "$dir/ci-result.txt")
ci_rounds=0
[ -f "$dir/ci-rounds.txt" ] && ci_rounds=$(cat "$dir/ci-rounds.txt")
[ "$ci" = pass ] && [ "$ci_rounds" -gt 0 ] && ci=repaired
[ "$ci" = fail ] && ci=failed

# The passes that brought the branch up to date, and the conflicts met.
updates=0 conflicts=0
[ -f "$dir/sync.txt" ] && {
	updates=$(grep -c '^update ' "$dir/sync.txt" || true)
	conflicts=$(grep -c '^conflicts ' "$dir/sync.txt" || true)
}

# The editor batches that changed the user's own checkout.
escapes=0
[ -f "$dir/escapes.txt" ] && escapes=$(grep -c '^escape$' "$dir/escapes.txt" || true)

# The highest source any setting came from: run, local, project, or none.
config=none
if [ -f "$dir/sources.txt" ]; then
	for s in project local run; do
		grep -q " $s\$" "$dir/sources.txt" && config=$s
	done
fi

root=$(CDPATH= cd -- "$dir/.." && pwd)
line="run $owner/$repo#$pr outcome $outcome rounds $rounds findings $total verified $verified wont-fix $wontfix unresolved $open reopens $reopens demoted $demoted contracts $contracts samples $samples kind $kind groups $groups seams $seams routes $routes cheap $cheap base $base strong $strong strong_wanted $strong_wanted escalations $escalations effort_low $effort_low effort_medium $effort_medium effort_high $effort_high effort_xhigh $effort_xhigh pinned $pinned unapplied $unapplied model_retries $model_retries model_retries_verified $model_retries_verified effort_retries $effort_retries effort_retries_verified $effort_retries_verified same_retries $same_retries same_retries_verified $same_retries_verified config $config method $method ci $ci ci_rounds $ci_rounds updates $updates conflicts $conflicts escapes $escapes"
printf '%s\n' "$line" >>"$root/stats.txt"
# The outcome marks the ledger for sweep-state.sh and list-runs.sh: held,
# parked, and review-only runs stay live without a worktree.
printf '%s\n' "$outcome" >"$dir/outcome.txt"
echo "run-stats: $line"
