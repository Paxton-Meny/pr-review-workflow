#!/bin/sh
# record-review: posts the converged review once per head, upgrades a
# comment to an approval when one is due, refuses an unconverged ledger,
# and leaves merge-pr nothing to post twice.
set -eu

stub="$SCRATCH/stub"
mkdir -p "$stub"
export GH_STUB_DIR="$stub"
export PATH="$REPO_ROOT/tests/stubs:$PATH"
. "$REPO_ROOT/tests/fixture-identity.sh"
author="${fixture_login}_author"
dir="$SCRATCH/data/state/${fixture_owner}__widgets__7"
mkdir -p "$dir/pr-context"
meta() {
	# meta <author> [reviewed_head]
	printf 'owner %s\nrepo widgets\npr 7\nauthor %s\nself_login %s\nhead_branch feat/x\nhead_sha abc123\ncross_repo false\n' "$fixture_owner" "$1" "$fixture_login" >"$dir/meta.txt"
	[ -z "${2:-}" ] || printf 'reviewed_head %s\n' "$2" >>"$dir/meta.txt"
}
meta "$fixture_login"
printf 'overlap_check off\n' | sh "$REPO_ROOT/scripts/resolve-settings.sh" "$dir" >/dev/null
printf '0\n' >"$dir/round.txt"
printf 'plan\nplanned all samples 1\nsaved all 0\ngap skip no-risk-signal\n' >"$dir/review.txt"
reviews="$stub/api-repos_${fixture_owner}_widgets_pulls_7_reviews"
: >"$reviews"
record() { sh "$REPO_ROOT/scripts/record-review.sh" "$dir" "$@"; }
posts() { grep -c "pulls/7/reviews" "$stub/calls.log" 2>/dev/null || true; }

# A clean review held without a merge still leaves a review with a body
# on the head it covered.
[ "$(record)" = "record-review: review recorded on abc123" ]
grep -q "^api repos/$fixture_owner/widgets/pulls/7/reviews -f event=COMMENT -f commit_id=abc123 -F body=@" "$stub/calls.log"
grep -q 'Review converged: no open findings.' "$stub/bodies.log"
[ "$(cat "$dir/review-record.txt")" = "COMMENT abc123" ]

# The record is the run's first comment and names the plugin; the status
# comment that follows on the same ledger does not name it again.
: >"$stub/pr-comment"
printf 'Review converged.\n' | sh "$REPO_ROOT/scripts/post-comment.sh" "$dir" >/dev/null
grep -q '^pr comment 7 ' "$stub/calls.log"
[ "$(grep -c 'Reviewed with' "$stub/bodies.log")" -eq 1 ]

# The same head is recorded once.
[ "$(record)" = "record-review: already recorded on abc123" ]
[ "$(posts)" -eq 1 ]

# The author's own pull request cannot be approved, and the comment that
# stands says so only when an approval was asked for.
[ "$(record --approve)" = "record-review: already recorded on abc123" ]
[ "$(posts)" -eq 1 ]
rm -f "$dir/review-record.txt" "$stub/bodies.log"
record --approve >/dev/null
grep -q 'stands in for the approval' "$stub/bodies.log"
[ "$(cat "$dir/review-record.txt")" = "COMMENT abc123" ]

# Another person's pull request: an approval replaces a standing comment,
# and is itself posted once.
meta "$author"
rm -f "$stub/calls.log"
[ "$(record --approve)" = "record-review: approval recorded on abc123" ]
grep -q "^api repos/$fixture_owner/widgets/pulls/7/reviews -f event=APPROVE -f commit_id=abc123 -F body=@" "$stub/calls.log"
[ "$(record --approve)" = "record-review: already recorded on abc123" ]
[ "$(record)" = "record-review: already recorded on abc123" ]
[ "$(posts)" -eq 1 ]

# The record goes on the head the review covered, and a new reviewed head
# gets its own.
meta "$author" def456
rm -f "$stub/calls.log"
[ "$(record)" = "record-review: review recorded on def456" ]
grep -q "pulls/7/reviews -f event=COMMENT -f commit_id=def456 " "$stub/calls.log"
# Neither later record names the plugin again.
[ "$(grep -c 'Reviewed with' "$stub/bodies.log")" -eq 1 ]

# merge-pr finds the record and posts no second one.
meta "$fixture_login"
rm -f "$dir/review-record.txt" "$stub/calls.log"
record >/dev/null
printf 'method rebase\nreason setting\nallowed merge squash rebase\ndelete_branch_on_merge true\nhistory merge 0 squash 0 rebase 0 either 0\n' >"$dir/pr-context/merge-method.txt"
printf 'state OPEN\ndraft false\nhead abc123\nmergeable MERGEABLE\nmerge_state CLEAN\n' >"$stub/pr-view.1"
printf 'MERGED\n' >"$stub/pr-view.2"
: >"$stub/pr-merge"
sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir" | grep -q "merged by rebase"
[ "$(posts)" -eq 1 ]

# A ledger that would not merge is not recorded as converged, and the
# forge is asked nothing.
rm -f "$dir/review-record.txt" "$stub/calls.log"
mkdir -p "$dir/findings"
printf 'id: F001\nstatus: open\ncategory: correctness\nseverity: major\npath: a.c\nline: 1\nend_line:\nside: RIGHT\nplacement: inline\ncomment_id: 1\ncommit:\nround: 1\nreopens: 0\ntitle: T\n---\nFix: x.\nResolution: x.\n' >"$dir/findings/F001"
rc=0
out=$(record) || rc=$?
[ "$rc" -eq 6 ]
[ "$out" = "$(printf 'record-review: the ledger does not show a converged review\nopen F001')" ]
[ ! -f "$stub/calls.log" ]
[ ! -f "$dir/review-record.txt" ]

# Nor is a head an armed check has not passed at: merge-pr would refuse
# it with the same line.
rm -rf "$dir/findings"
printf 'check_command true\noverlap_check off\n' | sh "$REPO_ROOT/scripts/resolve-settings.sh" "$dir" >/dev/null
hash=$(printf 'true' | git hash-object --stdin)
printf 'pass %s 0ld\n' "$hash" >"$dir/check-baseline.txt"
rc=0
out=$(record) || rc=$?
[ "$rc" -eq 6 ]
[ "$out" = "$(printf 'record-review: the ledger does not show a converged review\ncheck not run at abc123')" ]
rc=0
merged=$(sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir") || rc=$?
[ "$rc" -eq 6 ]
[ "$merged" = "$(printf 'merge-pr: the ledger does not allow a merge\ncheck not run at abc123')" ]
printf 'fail %s abc123\n' "$hash" >"$dir/check-gate.txt"
rc=0
out=$(record) || rc=$?
[ "$rc" -eq 6 ]
[ "$out" = "$(printf 'record-review: the ledger does not show a converged review\ncheck failed at abc123')" ]
[ ! -f "$stub/calls.log" ]
[ ! -f "$dir/review-record.txt" ]
# Once the gate passes at the head, the review is recorded.
printf 'pass %s abc123\n' "$hash" >"$dir/check-gate.txt"
[ "$(record)" = "record-review: review recorded on abc123" ]
rm -f "$dir/check-baseline.txt" "$dir/check-gate.txt"
printf 'overlap_check off\n' | sh "$REPO_ROOT/scripts/resolve-settings.sh" "$dir" >/dev/null

if record --bogus 2>"$SCRATCH/err"; then
	echo "expected refusal of an unknown argument" >&2
	exit 1
fi
grep -q "unknown argument: --bogus" "$SCRATCH/err"

# The skill records before it asks, and may run the script.
skill="$REPO_ROOT/skills/review-pr/SKILL.md"
grep -q 'scripts/record-review.sh \*)' "$skill"
grep -q 'scripts/record-review.sh <dir>`' "$skill"
