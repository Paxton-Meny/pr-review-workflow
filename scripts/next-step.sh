#!/bin/sh
# Name the review-pr step to run next, read from the ledger alone.
# Usage: sh scripts/next-step.sh <state-dir>
#
# For a session that lost its place, after a compaction or a resume. The
# first line is "next-step: <step> <what to do>", the step as SKILL.md
# numbers it (2 to 13, with the sub-step for steps 8 and 11), or "end"
# when the run is over. Lines after it carry what the step needs: "ids
# <ids>" for the findings it acts on, and "route <line>" for a spawn the
# run already routed, whose model and effort the spawn takes.
#
# The step journal steps.txt places the run inside a round and inside
# the checks loop: init-state.sh writes "invoke", round-counter.sh
# "round <n>" and "ci-round <n>", route-models.sh each line of its loop
# stages, push-branch.sh "push", run-check.sh --gate "gate", round-diff.sh
# "round-diff", save-findings.sh --unit incremental "saved incremental",
# post-review.sh "post", sync-branch.sh "sync", await-checks.sh "checks",
# merge-pr.sh "merge", run-stats.sh "outcome", and cleanup-state.sh
# "cleanup". The review phase comes from review-progress.sh and the
# findings from their records. A round an outcome closed (a park or a
# hold) is over: its findings start a new round. The checks loop is read
# from the last outcome on, since every step of it is safe to rerun.
# Where an agent's report leaves no trace on disk, the line says what
# to do either way.
# Exit 0 with a placement; exit 4 with "next-step: unplaced <reason>"
# when the ledger predates the journal and cannot show the round.
set -eu

dir=${1:?usage: next-step.sh <state-dir>}
[ -d "$dir" ] || {
	echo "next-step: no state directory $dir" >&2
	exit 1
}
here=$(dirname -- "$0")
ctx="$dir/pr-context"
journal="$dir/steps.txt"

place() {
	# place <step> <text>: print the placement and stop
	echo "next-step: $1 $2"
	exit 0
}

[ -f "$dir/meta.txt" ] || place 2 "create the ledger with init-state.sh"
[ -f "$dir/settings.txt" ] || place 2 "resolve the settings with resolve-settings.sh, then the rest of step 2"
[ -f "$journal" ] || {
	echo "next-step: unplaced, the ledger predates the step journal; resume as step 2 says"
	exit 4
}
setting() { sh "$here/setting.sh" "$dir" "$1"; }
head=$(sed -n 's/^head_sha //p' "$dir/meta.txt")

# The run's own end: an outcome since the last invocation.
set -- $(awk '
$1 == "invoke" { o = ""; c = 0; d = 0 }
$1 == "merge" && $2 == "done" { d = 1 }
$1 == "outcome" { o = $2; c = 0 }
$1 == "cleanup" { c = 1 }
END { print (o == "" ? "none" : o), c, d }' "$journal")
case "$1" in
merged)
	[ "$2" -eq 1 ] && place end "merged and cleaned up; report as step 13 says"
	place 13 "cleanup-state.sh, then sweep-state.sh, then the report"
	;;
held)
	[ "$2" -eq 1 ] && place end "held; invoking review-pr again resumes it"
	place 12 "hold: cleanup-state.sh, report the state directory, and stop"
	;;
parked | review-only) place end "$1; invoking review-pr again resumes it" ;;
none)
	[ "$3" -eq 1 ] && place 13 "run-stats.sh merged, then cleanup-state.sh, then sweep-state.sh, then the report"
	;;
esac

# The review phase, steps 3 to 6.
rc=0
progress=$(sh "$here/review-progress.sh" "$dir") || rc=$?
case "$rc" in
0) ;;
3)
	owed=$(printf '%s\n' "$progress" | sed 1d)
	if [ "$owed" = 'review not planned' ]; then
		[ -f "$ctx/diff.patch" ] || place 3 "fetch-pr.sh, probe-diff.sh, classify-change.sh, then step 4"
		[ -d "$dir/worktree" ] || place 4 "checkout-pr.sh, extract-standards.sh, run-check.sh --baseline, then step 5"
		place 5 "shard-plan.sh, route-models.sh review, then the reviewers it routes"
	fi
	if [ ! -f "$ctx/diff.patch" ] || [ ! -d "$dir/worktree" ]; then
		echo "next-step: 3 the worktree is gone: steps 3 and 4, then the review items below"
		printf '%s\n' "$owed"
		exit 0
	fi
	case "$owed" in
	review*)
		echo "next-step: 5 spawn the reviewers still owed and save each report with --unit"
		printf '%s\n' "$owed"
		for unit in $(printf '%s\n' "$owed" | sed -n 's/^review \([^ ]*\) needs .*/\1/p'); do
			grep "^route review $unit " "$ctx/routes.txt" 2>/dev/null | tail -n 1 || true
		done
		exit 0
		;;
	dedup*) place 5 "dedup-findings.sh, then the gap pass (step 6)" ;;
	*) place 6 "the gap pass: route-models.sh gap, then the reviewer it routes, saved with --unit gap" ;;
	esac
	;;
*) exit 1 ;;
esac
[ -f "$ctx/diff.patch" ] && [ -d "$dir/worktree" ] ||
	place 3 "the worktree is gone: steps 3 and 4, then ask again"

# The findings: id, status, reopens, placement.
findings=$(for f in "$dir/findings"/F*; do
	[ -f "$f" ] || continue
	sed '/^---$/q' "$f" | awk -v id="${f##*/}" '
		/^status: / { s = $2 } /^reopens: / { r = $2 } /^placement: / { p = $2 }
		/^accepted: / { a = $2 }
		END { print id, s, (r == "" ? 0 : r), (p == "" ? "-" : p), (a == "" ? "-" : a) }'
done)
ids_where() { printf '%s\n' "$findings" | awk "NF && ($1) { printf \"%s%s\", s, \$1; s = \" \" } END { print \"\" }"; }
unposted=$(ids_where '$2 == "open" && $4 == "-"')
open=$(ids_where '$2 == "open"')
addressed=$(ids_where '$2 == "addressed"')
unaccepted=$(ids_where '$2 == "wont-fix" && $5 != "yes"')

if [ -n "$unposted" ]; then
	if grep -qx post "$journal"; then
		echo "next-step: 8e prove-suggestions.sh, then post-review.sh, for the new findings"
	else
		echo "next-step: 7 route-models.sh filter and its filter, then prove-suggestions.sh, then post-review.sh"
	fi
	echo "ids $unposted"
	exit 0
fi
cross=$(sed -n 's/^cross_repo //p' "$dir/meta.txt")
can=$(sed -n 's/^maintainer_can_modify //p' "$dir/meta.txt")
[ "$cross" = true ] && [ "$can" != true ] &&
	place 7 "review-only: the status comment, run-stats.sh review-only, and stop"

# Step 8: the last round, replayed from the journal.
rounds=0
[ -f "$dir/rounds.txt" ] && rounds=$(cat "$dir/rounds.txt")
round=$({
	printf '%s\n' "$findings"
	echo %%
	cat "$journal"
} | awk -v rounds="$rounds" '
function ids(line) { sub(/.* ids /, "", line); return line }
function out(step, text) { print "next-step: " step " " text }
!split_done && $0 == "%%" { split_done = 1; next }
!split_done {
	if (NF) {
		st[$1] = $2
		if ($2 == "open") open = open " " $1
		if ($2 == "addressed") addressed = addressed " " $1
		if ($2 == "open" && $3 > 2) capped = capped " " $1
	}
	next
}
{ ev[++n] = $0 }
END {
	start = 0
	for (i = n; i >= 1; i--) { split(ev[i], w, " "); if (w[1] == "round") { start = i; break } }
	if (!start) { print (rounds > 0 ? "legacy" : "none"); exit }
	for (i = start + 1; i <= n; i++) { split(ev[i], w, " "); if (w[1] == "outcome") { print "closed"; exit } }
	split(ev[start], w, " ")
	if (w[2] == "cap") { out(9, "non-convergence: the round cap is spent"); exit }
	r = w[2]
	for (i = 1; i < start; i++) if (ev[i] ~ /^route arbitrate all rung /) spent = 1
	nb = 0; cur = 1; fails = 0; repair = 0; edited = 0; prev_edit = 0
	for (i = start + 1; i <= n; i++) {
		line = ev[i]; split(line, w, " "); t = w[1]
		is_edit = (t == "route" && w[2] == "edit")
		if (is_edit) {
			if (!prev_edit) { nb = 0; cur = 1; fails = 0; repair = 0; edited = 0 }
			bl[++nb] = line; bids[nb] = ids(line)
		}
		prev_edit = is_edit
		if (t == "push") edited = 1
		else if (t == "route" && w[2] == "repair") { repair = 1; rline = line; edited = 0 }
		else if (t == "gate" && cur <= nb) {
			if (w[2] == "fail") {
				if (++fails >= 2) { out(9, "non-convergence: the check failed again after its repair in round " r); exit }
				repair = 0; edited = 0
			} else { cur++; fails = 0; repair = 0; edited = 0 }
		}
		else if (t == "route" && w[2] == "verify") { verify = (w[4] == "skip") ? "skip" : "routed"; vline = line }
		else if (t == "round-diff") diff = w[2]
		else if (t == "route" && w[2] == "incremental" && diff != "") { incr = 1; iline = line }
		else if (t == "saved" && w[2] == "incremental" && incr) isaved = 1
		else if (t == "route" && w[2] == "arbitrate") { arb = (w[4] == "skip") ? "skip" : "routed"; aline = line }
	}
	if (nb == 0) {
		out("8b", "route-models.sh edit round=" r " -- <open ids>, then the editor for each line it prints")
		if (open != "") print "ids" open
		exit
	}
	if (cur <= nb) {
		where = "batch " cur " of " nb " in round " r
		if (fails == 1 && !repair) {
			out("8c", "the check failed after " where ": route-models.sh repair round=" r " -- <ids>, then the repair editor, then run-check.sh --gate")
			print "ids " bids[cur]
		} else if (fails == 1 && !edited) {
			out("8c", "spawn the repair editor on this route; once it has reported, run-check.sh --gate")
			print rline
		} else {
			ran = edited
			if (!ran) {
				ran = 1
				k = split(bids[cur], b, " ")
				for (j = 1; j <= k; j++) if (st[b[j]] == "open") ran = 0
			}
			if (ran) out("8c", "run-check.sh --gate, after " where)
			else { out("8b", "spawn the editor for " where ", then run-check.sh --gate"); print bl[cur] }
		}
		exit
	}
	if (verify == "") {
		out("8d", "count-findings.sh --list, route-models.sh verify -- <addressed ids>, then the verifier it routes")
		if (addressed != "") print "ids" addressed
		exit
	}
	if (verify == "routed" && addressed != "") {
		out("8d", "spawn the verifier on this route")
		print vline
		print "ids" addressed
		exit
	}
	if (diff == "") { out("8e", "round-diff.sh"); exit }
	if (diff == "unexpected" && !incr) {
		out("8e", "round-diff.sh again for its paths, fetch-pr.sh, route-models.sh incremental, then the reviewer on those files, saved with --unit incremental")
		exit
	}
	if (diff == "unexpected" && !isaved) {
		out("8e", "spawn the incremental reviewer on this route and save its report with --unit incremental")
		print iline
		exit
	}
	if (capped != "") {
		if (arb == "skip" || (spent && arb == "")) { out(9, "non-convergence: findings reopened more than twice"); print "ids" capped; exit }
		if (arb == "routed") {
			out("8f", "spawn the arbitration verifier on this route unless it has reported; once it has, these findings still open park the run (step 9)")
			print aline
			print "ids" capped
			exit
		}
		out("8f", "route-models.sh arbitrate, then the arbitration verifier")
		print "ids" capped
		exit
	}
	print "complete"
}')
case "$round" in
legacy)
	if [ -n "$open$addressed" ]; then
		echo "next-step: unplaced, round $rounds ran before the step journal; resume as step 2 says"
		exit 4
	fi
	;;
none | closed | complete)
	if [ -n "$open$addressed" ]; then
		echo "next-step: 8a round-counter.sh next 4, then the round"
		echo "ids $open${open:+${addressed:+ }}$addressed"
		exit 0
	fi
	;;
*)
	printf '%s\n' "$round"
	exit 0
	;;
esac

# Step 10: every wont-fix accepted before anything merges.
if [ -n "$unaccepted" ]; then
	echo "next-step: 10 present each wont-fix; update-finding.sh <id> accepted=yes for each the user accepts"
	echo "ids $unaccepted"
	exit 0
fi

# Step 11 and the merge gate, from the last outcome on.
record="$ctx/merge-method.txt"
method=none
[ -f "$record" ] && method=$(sed -n 's/^method //p' "$record")
[ "$method" = undecided ] &&
	place 12 "the merge method is undecided: attended, ask which allowed method and merge-method.sh --set it; unattended, park (step 9)"
repeat=0
[ -f "$dir/ci-attempts.txt" ] &&
	[ "$(tail -n 2 "$dir/ci-attempts.txt" | cut -d' ' -f2 | uniq | grep -c .)" -eq 1 ] &&
	[ "$(grep -c . "$dir/ci-attempts.txt")" -ge 2 ] && repeat=1
changed=0
[ -f "$ctx/sync-changed.txt" ] && changed=$(grep -c . "$ctx/sync-changed.txt" || true)
loop=$(awk -v head="$head" -v sync="$(setting branch_sync)" -v ci="$(setting ci_checks)" \
	-v repairs="$(setting review_repairs)" -v changed="$changed" -v repeat="$repeat" '
function out(step, text) { print "next-step: " step " " text }
$1 == "outcome" { n = 0; next }
{ ev[++n] = $0 }
END {
	a = 0
	for (i = n; i >= 1; i--) {
		split(ev[i], w, " ")
		if (w[1] == "sync" || w[1] == "checks" || w[1] == "ci-round" || w[1] == "merge") { a = i; break }
	}
	if (!a) { out("11a", "merge-method.sh, then sync-branch.sh"); exit }
	split(ev[a], w, " "); kind = w[1]; what = w[2]; at = w[3]
	for (i = a + 1; i <= n; i++) {
		split(ev[i], x, " ")
		if (x[1] == "push") pushed = 1
		else if (x[1] == "gate") { if (x[2] == "fail") gfail++; else gated = 1 }
		else if (x[1] == "route" && x[2] == "ci-repair") { rr = 1; rline = ev[i] }
		else if (x[1] == "route" && x[2] == "conflict") { conflict = 1; cline = ev[i] }
		else if (x[1] == "round-diff-all") rd = x[2]
		else if (x[1] == "route" && x[2] == "incremental") { incr = 1; iline = ev[i] }
		else if (x[1] == "saved" && x[2] == "incremental" && incr) isaved = 1
	}
	if (kind == "ci-round") {
		if (what == "cap") { out(9, "non-convergence: the checks still fail after the repairs"); exit }
		for (i = a - 1; i >= 1; i--) { split(ev[i], x, " "); if (x[1] == "checks" && x[2] == "fail") { base = x[3]; break } }
		if (!rr) { out("11c", "route-models.sh ci-repair repeat=" repeat ", then the editor with the ci repair prompt (ci base " base "), posting its paragraph"); exit }
		if (gfail >= 2) { out(9, "non-convergence: the check failed again after its repair"); exit }
		if (gfail == 1 && !gated) { out("11c", "the check failed after the ci repair: the step 8c repair once, then run-check.sh --gate"); exit }
		if (!pushed && !gated) { out("11c", "spawn the ci repair editor on this route unless it has reported; once it has, run-check.sh --gate"); print rline; exit }
		if (!gated) { out("11c", "run-check.sh --gate"); exit }
		if (repairs == "true") {
			if (rd == "") { out("11c", "round-diff.sh --all " base); exit }
			if (rd == "unexpected" && !incr) { out("11c", "the incremental review of the listed files as step 8e: round-diff.sh --all " base " for them, fetch-pr.sh, route-models.sh incremental, the reviewer, saved with --unit incremental"); exit }
			if (rd == "unexpected" && !isaved) { out("11c", "spawn the incremental reviewer on this route and save its report with --unit incremental"); print iline; exit }
		}
		out("11a", "merge-method.sh, then sync-branch.sh")
		exit
	}
	if (kind == "merge") {
		if (what == "migrations" && at == head) { out(12, "migrations changed: attended, the four checks and merge or hold, merge-pr.sh with --migrations-checked only on their answer; unattended, park (step 9)"); exit }
		out("11a", "merge-method.sh, then sync-branch.sh: the base moved")
		exit
	}
	if (kind == "sync" && what == "abort") { out(9, "park: the conflict editor could not resolve the update"); exit }
	if (at != head) { out("11a", "merge-method.sh, then sync-branch.sh: the head moved"); exit }
	if (kind == "sync") {
		if (what == "stuck" || (what == "conflicts" && sync != "resolve")) {
			out("11a", "the base sync needs a person: attended, ask the user and hold (step 12); unattended, park (step 9)")
			exit
		}
		if (what == "conflicts") {
			if (!conflict) { out("11a", "route-models.sh conflict, then the editor with the conflict prompt"); exit }
			out("11a", "spawn the conflict editor on this route unless it has reported; once it has, a worktree still mid-update takes sync-branch.sh --abort and parks")
			print cline
			exit
		}
		if (what == "update") {
			if (!gated && !gfail) { out("11a", "run-check.sh --gate, since the update pushed"); exit }
			if (gfail && !gated) { out("11a", "the check fails after the update: the step 8c repair once, then run-check.sh --gate"); exit }
			if (repairs == "true" && changed > 0) {
				if (!incr) { out("11a", "the incremental review of pr-context/sync-changed.txt as step 8e: route-models.sh incremental, the reviewer, saved with --unit incremental"); exit }
				if (!isaved) { out("11a", "spawn the incremental reviewer on this route and save its report with --unit incremental"); print iline; exit }
			}
		}
		out("11b", "await-checks.sh")
		exit
	}
	if (what == "fail") {
		if (ci == "fix") out("11c", "round-counter.sh next ci, then the ci repair")
		else out("11c", "the checks failed: a comment naming them, then attended hold (step 12), unattended park (step 9)")
		exit
	}
	print "merge"
}' "$journal")
[ "$loop" = merge ] || {
	printf '%s\n' "$loop"
	exit 0
}

# Step 12: the check must have passed at the head before the merge.
check=$(setting check_command)
if [ -n "$check" ]; then
	hash=$(printf '%s' "$check" | git hash-object --stdin)
	baseline=$(cat "$dir/check-baseline.txt" 2>/dev/null || true)
	gate=$(cat "$dir/check-gate.txt" 2>/dev/null || true)
	case "$baseline" in
	"pass $hash "*)
		[ "$gate" = "pass $hash $head" ] || [ "$baseline" = "pass $hash $head" ] ||
			place 12 "run-check.sh --gate first, as step 8c describes: the check has not passed at $head"
		;;
	"fail $hash "*) ;;
	*) place 12 "run-check.sh --gate first: the check has no baseline for the configured command" ;;
	esac
fi
place 12 "merge-method.sh --refresh, then the merge gate (auto_approve $(setting auto_approve))"
