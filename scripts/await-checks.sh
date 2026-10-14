#!/bin/sh
# Wait for the pull request head's checks and record how they ended.
# Usage: sh scripts/await-checks.sh <state-dir> [--slice <seconds>]
#
# Reads the checks GitHub reports for the head in meta.txt until they
# finish, the slice ends, or the wait budget (ci_wait_minutes, kept per
# head in <state-dir>/ci-wait.txt so a resumed run cannot restart it)
# is spent. With ci_checks off nothing is read. Exit 0 prints
# "await-checks: pass <m> checks", "await-checks: no checks" (none
# appeared within a grace: SCHEDULE_GRACE seconds when the base branch
# holds workflows, STATUS_GRACE otherwise), or "await-checks: off"; exit
# 5 means the slice ended with checks pending, call again; exit 6 means
# the budget is spent. Exit 3 means a check failed: the digest for the
# editor is written to pr-context/ci-failure.txt (name, link,
# description, the check run's title and summary, its annotations, and
# the failed steps' log for an Actions run, each capped, none of it
# printed), the attempt is appended to <state-dir>/ci-attempts.txt as
# "<head> <signature> <names>", and the line ends "signature repeat"
# when the signature equals the previous attempt's, else "signature
# new". The signature hashes the failed names, the annotations, and the
# error lines of the logs with timestamps removed, so the same failure
# reads the same across runs. A cancelled Actions run is rerun once
# (gh run rerun --failed, recorded in ci-reruns.txt with the time) and
# waited for, as pending while the rerun registers (RERUN_GRACE); a
# second cancel counts as a failure. The outcome is written to
# ci-result.txt as "pass|fail|none|off <head>".
set -eu

dir=${1:?usage: await-checks.sh <state-dir> [--slice <seconds>]}
shift
slice=${AWAIT_CHECKS_SLICE:-480}
case "${1:-}" in
'') ;;
--slice)
	slice=${2:?usage: await-checks.sh <state-dir> [--slice <seconds>]}
	;;
*)
	echo "await-checks: unknown argument: $1" >&2
	exit 1
	;;
esac
case "$slice" in
'' | *[!0-9]*)
	echo "await-checks: slice must be a number of seconds: $slice" >&2
	exit 1
	;;
esac
[ -f "$dir/meta.txt" ] || {
	echo "await-checks: no meta.txt in $dir" >&2
	exit 1
}
ctx="$dir/pr-context"
[ -d "$ctx" ] || {
	echo "await-checks: no pr-context in $dir, run fetch-pr.sh first" >&2
	exit 1
}
owner=$(sed -n 's/^owner //p' "$dir/meta.txt")
repo=$(sed -n 's/^repo //p' "$dir/meta.txt")
pr=$(sed -n 's/^pr //p' "$dir/meta.txt")
head_sha=$(sed -n 's/^head_sha //p' "$dir/meta.txt")
base=$(sed -n 's/^base_branch //p' "$dir/meta.txt")
repo_root=$(sed -n 's/^repo_root //p' "$dir/meta.txt")
[ -n "$head_sha" ] || {
	echo "await-checks: meta.txt records no head_sha" >&2
	exit 1
}

INTERVAL=${AWAIT_CHECKS_INTERVAL:-20}
SCHEDULE_GRACE=${AWAIT_CHECKS_SCHEDULE_GRACE:-120}
STATUS_GRACE=${AWAIT_CHECKS_STATUS_GRACE:-30}
SUMMARY_LINES=40
ANNOTATION_LINES=50
LOG_TAIL_LINES=150
DIGEST_LINES=600
RERUN_GRACE=${AWAIT_CHECKS_RERUN_GRACE:-120}

mode=$(sh "$(dirname -- "$0")/setting.sh" "$dir" ci_checks)
minutes=$(sh "$(dirname -- "$0")/setting.sh" "$dir" ci_wait_minutes)

result() {
	# result <outcome>
	tmp=$(mktemp "$dir/.ci.XXXXXX")
	printf '%s %s\n' "$1" "$head_sha" >"$tmp"
	mv "$tmp" "$dir/ci-result.txt"
}

if [ "$mode" = off ]; then
	result off
	echo "await-checks: off"
	exit 0
fi

now=$(date +%s)
wait_record=''
[ -f "$dir/ci-wait.txt" ] && wait_record=$(cat "$dir/ci-wait.txt")
case "$wait_record" in
"$head_sha "*)
	set -- $wait_record
	first_seen=$2 deadline=$3
	;;
*)
	first_seen=$now deadline=$((now + minutes * 60))
	tmp=$(mktemp "$dir/.ci.XXXXXX")
	printf '%s %s %s\n' "$head_sha" "$first_seen" "$deadline" >"$tmp"
	mv "$tmp" "$dir/ci-wait.txt"
	;;
esac
slice_end=$((now + slice))

grace=$STATUS_GRACE
if [ -n "$repo_root" ] && [ -n "$base" ] &&
	[ -n "$(git -C "$repo_root" ls-tree -r --name-only "origin/$base" -- .github/workflows 2>/dev/null)" ]; then
	grace=$SCHEDULE_GRACE
fi

checks=$(mktemp "$ctx/.checks.XXXXXX")
trap 'rm -f "$checks"' EXIT

esc=$(printf '\033')
clean_log() {
	# ANSI sequences and the timestamp column gone, the step name kept
	sed -e "s/$esc\[[0-9;]*[A-Za-z]//g" -e 's/^\([^	]*	[^	]*	\)[0-9][0-9-]*T[0-9:.]*Z /\1/'
}

run_id() {
	# run_id <link>: the Actions run id in a check's link, or nothing
	printf '%s\n' "$1" | sed -n 's|.*/actions/runs/\([0-9][0-9]*\).*|\1|p'
}

field() {
	# field <tab-separated line> <cut list>: keeps empty fields, which read with a tab IFS drops
	printf '%s\n' "$1" | cut -f"$2"
}

digest() {
	# digest <failed lines>: writes pr-context/ci-failure.txt, prints the signature
	out=$(mktemp "$ctx/.digest.XXXXXX")
	sig=$(mktemp "$ctx/.digest.XXXXXX")
	runs=$(mktemp "$ctx/.digest.XXXXXX")
	gh api "repos/$owner/$repo/commits/$head_sha/check-runs" --paginate \
		--jq '.check_runs[] | "\(.id)\t\(.name)\t\(.output.title // "")\t\(.output.summary // "" | gsub("\n"; "\\n"))"' >"$runs" 2>/dev/null || : >"$runs"
	printf '%s\n' "$1" | while IFS= read -r line; do
		bucket=$(field "$line" 1)
		name=$(field "$line" 2)
		link=$(field "$line" 3)
		description=$(field "$line" 5-)
		printf 'check %s %s %s\n' "$name" "$bucket" "$link"
		[ -z "$description" ] || printf 'description %s\n' "$description"
		printf '%s\n' "$name" >>"$sig"
		awk -F '\t' -v want="$name" '$2 == want' "$runs" | while IFS= read -r rline; do
			id=$(field "$rline" 1)
			title=$(field "$rline" 3)
			summary=$(field "$rline" 4-)
			[ -z "$title" ] || printf 'title %s\n' "$title"
			[ -z "$summary" ] || printf '%s\n' "$summary" | sed 's/\\n/\n/g' | head -n "$SUMMARY_LINES" | sed 's/^/summary /'
			gh api "repos/$owner/$repo/check-runs/$id/annotations" --paginate \
				--jq '.[] | "\(.path):\(.start_line) \(.annotation_level // "") \(.title // "") \(.message // "")"' 2>/dev/null |
				head -n "$ANNOTATION_LINES" | tee -a "$sig" | sed 's/^/annotation /'
		done
		id=$(run_id "$link")
		if [ -n "$id" ]; then
			log=$(gh run view "$id" --repo "$owner/$repo" --log-failed 2>/dev/null | clean_log || true)
			if [ -n "$log" ]; then
				printf '%s\n' "$log" | tail -n "$LOG_TAIL_LINES" | sed 's/^/log /'
				printf '%s\n' "$log" | grep '##\[error\]' >>"$sig" || true
			else
				echo 'logs unavailable'
			fi
		else
			echo 'logs unavailable'
		fi
	done | head -n "$DIGEST_LINES" >"$out"
	mv "$out" "$ctx/ci-failure.txt"
	git hash-object --stdin <"$sig"
	rm -f "$sig" "$runs"
}

while :; do
	# Exit 0 and 8 (checks pending) are answers; any other exit (network,
	# rate limit, token, 5xx) leaves the poll unreadable, and an
	# unreadable poll is never "no checks".
	rc=0
	gh pr checks "$pr" --repo "$owner/$repo" --json name,state,bucket,link,workflow,description \
		--jq '.[] | "\(.bucket)\t\(.name)\t\(.link)\t\(.workflow)\t\(.description)"' >"$checks" 2>/dev/null || rc=$?
	readable=1
	case "$rc" in
	0 | 8) ;;
	*) readable=0 ;;
	esac
	total=$(grep -c . "$checks" || true)
	now=$(date +%s)
	if [ "$total" -eq 0 ]; then
		if [ "$readable" -eq 1 ] && [ "$now" -ge $((first_seen + grace)) ]; then
			result none
			echo "await-checks: no checks"
			exit 0
		fi
	else
		failed=$(grep '^fail	' "$checks" || true)
		cancelled=$(grep '^cancel	' "$checks" || true)
		pending=$(grep -c '^pending	' "$checks" || true)
		if [ -n "$cancelled" ]; then
			# A cancelled Actions run is rerun once and then pending while
			# the rerun registers; cancelled again, or not an Actions run, it failed.
			rm -f "$checks.pending" "$checks.failed"
			printf '%s\n' "$cancelled" | while IFS= read -r line; do
				bucket=$(field "$line" 1)
				name=$(field "$line" 2)
				link=$(field "$line" 3)
				workflow=$(field "$line" 4)
				description=$(field "$line" 5-)
				id=$(run_id "$link")
				since=$(sed -n "s/^$id //p" "$dir/ci-reruns.txt" 2>/dev/null | tail -n 1)
				if [ -n "$id" ] && [ -z "$since" ] && gh run rerun "$id" --failed --repo "$owner/$repo" >/dev/null 2>&1; then
					printf '%s %s\n' "$id" "$now" >>"$dir/ci-reruns.txt"
					echo "await-checks: run $id was cancelled, rerunning its failed jobs once"
					echo "$id" >>"$checks.pending"
				elif [ -n "$since" ] && [ "$now" -lt $((since + RERUN_GRACE)) ]; then
					echo "$id" >>"$checks.pending"
				else
					printf '%s\t%s\t%s\t%s\t%s\n' "$bucket" "$name" "$link" "$workflow" "$description" >>"$checks.failed"
				fi
			done
			[ ! -s "$checks.pending" ] || pending=$((pending + $(grep -c . "$checks.pending")))
			[ ! -s "$checks.failed" ] || failed=$(printf '%s\n%s\n' "$failed" "$(cat "$checks.failed")")
			rm -f "$checks.pending" "$checks.failed"
		fi
		if [ -n "$failed" ]; then
			failed=$(printf '%s\n' "$failed" | grep .)
			signature=$(digest "$failed")
			names=$(printf '%s\n' "$failed" | cut -f2 | tr '\n' ' ')
			names=${names% }
			previous=$(tail -n 1 "$dir/ci-attempts.txt" 2>/dev/null | cut -d' ' -f2)
			printf '%s %s %s\n' "$head_sha" "$signature" "$names" >>"$dir/ci-attempts.txt"
			verdict=new
			[ "$previous" = "$signature" ] && verdict=repeat
			result fail
			count=$(printf '%s\n' "$failed" | grep -c .)
			echo "await-checks: fail $count of $total: $names; signature $verdict"
			exit 3
		fi
		if [ "$pending" -eq 0 ]; then
			result pass
			echo "await-checks: pass $total checks"
			exit 0
		fi
	fi
	if [ "$now" -ge "$deadline" ]; then
		echo "await-checks: wait budget of $minutes minutes spent, ${pending:-0} pending"
		exit 6
	fi
	if [ "$now" -ge "$slice_end" ]; then
		if [ "$total" -eq 0 ]; then
			echo "await-checks: no checks reported yet, call again"
		else
			echo "await-checks: pending $pending of $total, call again"
		fi
		exit 5
	fi
	sleep "$INTERVAL"
done
