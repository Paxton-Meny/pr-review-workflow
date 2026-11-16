#!/bin/sh
# Say whether the ledger shows a converged review: the review phase
# complete and every finding verified or an accepted wont-fix.
# Usage: sh scripts/ledger-allows.sh <state-dir>
# Exit 3 with one line per reason: each item review-progress.sh reports
# incomplete ("review ...", "dedup ...", "gap ..."), a finding still open
# ("open <id>"), a wont-fix finding no person accepted ("unaccepted <id>"),
# and a finding marked addressed that no verifier has judged
# ("unverified <id>"). merge-pr.sh and record-review.sh both ask here, so
# a review is never recorded as converged on a ledger that would not merge.
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
[ -z "$refused" ] || {
	printf '%s\n' "$refused"
	exit 3
}
