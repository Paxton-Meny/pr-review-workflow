#!/bin/sh
# Say whether the ledger shows a converged review: the review phase
# complete, every finding verified or an accepted wont-fix, and, when
# the check gate is armed, the check passed at the head.
# Usage: sh scripts/ledger-allows.sh <state-dir>
# Exit 3 with one line per reason: each item review-progress.sh reports
# incomplete ("review ...", "dedup ...", "gap ..."), a finding still open
# ("open <id>"), a wont-fix finding no person accepted ("unaccepted <id>"),
# a finding marked addressed that no verifier has judged
# ("unverified <id>"), and, when the check gate is armed, a head the
# check has not passed at ("check <reason>"). merge-pr.sh and
# record-review.sh both ask here and nowhere else, so a review is never
# recorded as converged on a ledger that would not merge.
set -eu

dir=${1:?usage: ledger-allows.sh <state-dir>}
here=$(dirname -- "$0")
refused=''
rc=0
progress=$(sh "$here/review-progress.sh" "$dir") || rc=$?
case "$rc" in
0) ;;
3) refused=$(printf '%s\n' "$progress" | sed 1d) ;;
*) exit 1 ;;
esac
add() {
	refused="${refused:+$refused
}$1"
}
if [ -d "$dir/findings" ]; then
	rc=0
	counts=$(sh "$here/count-findings.sh" "$dir" --list) || rc=$?
	[ "$rc" -eq 0 ] || [ "$rc" -eq 3 ] || exit 1
	for id in $(printf '%s\n' "$counts" | sed -n 's/^open_ids//p'); do
		add "open $id"
	done
	for id in $(printf '%s\n' "$counts" | sed -n 's/^wont_fix_ids//p'); do
		sed '/^---$/q' "$dir/findings/$id" | grep -qx 'accepted: yes' || add "unaccepted $id"
	done
	for id in $(printf '%s\n' "$counts" | sed -n 's/^addressed_ids//p'); do
		add "unverified $id"
	done
fi
# Armed means the baseline passed for the command now configured; then
# the head must have passed it, by the last gate run at that head or by
# a baseline taken there.
head_sha=$(sed -n 's/^head_sha //p' "$dir/meta.txt")
check=$(sh "$here/setting.sh" "$dir" check_command) || exit 1
# The check never runs on code author-trust.sh --exec does not allow, so it
# cannot gate that author's merge; their merge needs a person and no check.
if [ -n "$check" ] && ! sh "$here/author-trust.sh" "$dir" --exec >/dev/null 2>&1; then
	check=''
fi
if [ -n "$check" ]; then
	check_hash=$(printf '%s' "$check" | git hash-object --stdin)
	baseline=$(cat "$dir/check-baseline.txt" 2>/dev/null || true)
	gate=$(cat "$dir/check-gate.txt" 2>/dev/null || true)
	case "$baseline" in
	"fail $check_hash "*) ;;
	"pass $check_hash "*)
		case "$gate" in
		"pass $check_hash $head_sha") ;;
		"fail $check_hash $head_sha")
			add "check failed at $head_sha"
			;;
		*)
			[ "$baseline" = "pass $check_hash $head_sha" ] || add "check not run at $head_sha"
			;;
		esac
		;;
	*)
		add "check has no baseline for the configured command"
		;;
	esac
fi
[ -z "$refused" ] || {
	printf '%s\n' "$refused"
	exit 3
}
