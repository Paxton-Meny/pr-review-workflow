#!/bin/sh
# review-progress: the review phase's plan, saved units, dedup and gap
# pass are read back from the ledger, so a resumed run finishes what a
# crash left, and posting and merging refuse until it is complete.
set -eu
unset CLAUDE_CODE_EFFORT_LEVEL

dir="$SCRATCH/state"
ctx="$dir/pr-context"
mkdir -p "$ctx"
printf '0\n' >"$dir/round.txt"
printf 'classify-change: kind code files 2 lines 40 code_lines 40\n' >"$ctx/class.txt"
: >"$ctx/probe-slugs.txt"
progress() { sh "$REPO_ROOT/scripts/review-progress.sh" "$dir"; }
pending() {
	# pending <owed lines>: exit 3 with exactly those items
	rc=0
	out=$(progress) || rc=$?
	[ "$rc" -eq 3 ] && [ "$out" = "$(printf 'review-progress: pending\n%s' "$1")" ] || {
		echo "expected pending '$1', got $rc: $out" >&2
		exit 1
	}
}
finding() {
	printf '=== finding\ncategory: correctness\nseverity: major\npath: src/a.py\nline: %s\nside: RIGHT\ntitle: Thing %s\n---\nEvidence %s.\nFix: do.\nResolution: done.\n' "$1" "$1" "$2"
}

# A fresh ledger owes the whole review.
pending 'review not planned'

# Two groups of two samples each: a crash after three reports leaves
# exactly the missing sample owed, and the gap pass after it.
printf 'group 1 lines 20 files 001\ngroup 2 lines 20 files 002\n' >"$ctx/shards.txt"
printf '001\tsrc/a.py\tcode\t20\n002\tsrc/b.py\tcode\t20\n' >"$ctx/files-kind.txt"
sh "$REPO_ROOT/scripts/route-models.sh" "$dir" review routing=auto samples=2 >/dev/null
pending "$(printf 'review group-1 needs 2 of 2\nreview group-2 needs 2 of 2\ngap not run')"
finding 3 one | sh "$REPO_ROOT/scripts/save-findings.sh" "$dir" --unit group-1 >/dev/null
finding 4 longer-evidence | sh "$REPO_ROOT/scripts/save-findings.sh" "$dir" --unit group-1 >/dev/null
[ "$(printf 'no findings\n' | sh "$REPO_ROOT/scripts/save-findings.sh" "$dir" --unit group-2)" = 'save-findings: no findings for group-2' ]
pending "$(printf 'review group-2 needs 1 of 2\ngap not run')"

# A resumed run routes again; the plan is the same and nothing restarts.
sh "$REPO_ROOT/scripts/route-models.sh" "$dir" review routing=auto samples=2 >/dev/null
pending "$(printf 'review group-2 needs 1 of 2\ngap not run')"
printf '\nno findings\n\n' | sh "$REPO_ROOT/scripts/save-findings.sh" "$dir" --unit group-2 >/dev/null

# Samples that saved findings owe a dedup, then the gap pass.
pending "$(printf 'dedup not run\ngap not run')"
sh "$REPO_ROOT/scripts/dedup-findings.sh" "$dir" 2 >/dev/null
pending 'gap not run'
printf 'no findings\n' | sh "$REPO_ROOT/scripts/save-findings.sh" "$dir" --unit gap >/dev/null
[ "$(progress)" = 'review-progress: complete' ]

# A skipped gap pass counts as run, and one sample saving nothing needs
# no dedup.
rm -rf "$dir/findings"
: >"$dir/review.txt"
rm -f "$ctx/shards.txt"
sh "$REPO_ROOT/scripts/route-models.sh" "$dir" review routing=auto samples=1 >/dev/null
printf 'no findings\n' | sh "$REPO_ROOT/scripts/save-findings.sh" "$dir" --unit all >/dev/null
pending 'gap not run'
sh "$REPO_ROOT/scripts/route-models.sh" "$dir" gap routing=auto double=off >/dev/null
[ "$(progress)" = 'review-progress: complete' ]

# A ledger from before the record counts as complete once it holds findings.
rm -f "$dir/review.txt"
pending 'review not planned'
finding 7 legacy | sh "$REPO_ROOT/scripts/save-findings.sh" "$dir" >/dev/null
[ "$(progress)" = 'review-progress: complete, recorded before progress was kept' ]

# Units are named, never free text.
for bad in group-0 group-1a shard x; do
	if finding 9 bad | sh "$REPO_ROOT/scripts/save-findings.sh" "$dir" --unit "$bad" 2>"$SCRATCH/err"; then
		echo "expected refusal of the unit $bad" >&2
		exit 1
	fi
	grep -q 'the unit must be all, gap, or group-<n>' "$SCRATCH/err"
done

# Posting refuses while the phase is incomplete, changing nothing.
stub="$SCRATCH/stub"
mkdir -p "$stub"
export GH_STUB_DIR="$stub"
export PATH="$REPO_ROOT/tests/stubs:$PATH"
printf 'owner o\nrepo widgets\npr 7\nhead_sha abc123\n' >"$dir/meta.txt"
printf 'src/a.py\tRIGHT\t7\n' >"$ctx/commentable.txt"
printf 'plan\nplanned all samples 1\n' >"$dir/review.txt"
rc=0
out=$(sh "$REPO_ROOT/scripts/post-review.sh" "$dir") || rc=$?
[ "$rc" -eq 5 ]
[ "$out" = "$(printf 'post-review: the review phase is incomplete, finish steps 5 and 6 first\nreview all needs 1 of 1\ngap not run')" ]
[ ! -f "$stub/calls.log" ]
[ "$(cat "$dir/round.txt")" = 0 ]
grep -qx 'placement:' "$dir/findings/F001"

# Merging refuses the same way, before the forge is asked anything.
: | sh "$REPO_ROOT/scripts/resolve-settings.sh" "$dir" >/dev/null
printf 'method merge\nreason setting\nallowed merge\ndelete_branch_on_merge true\n' >"$ctx/merge-method.txt"
sh "$REPO_ROOT/scripts/update-finding.sh" "$dir" F001 status=wont-fix >/dev/null
sh "$REPO_ROOT/scripts/update-finding.sh" "$dir" F001 accepted=yes >/dev/null
rc=0
out=$(sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir") || rc=$?
[ "$rc" -eq 6 ]
[ "$out" = "$(printf 'merge-pr: the ledger does not allow a merge\nreview all needs 1 of 1\ngap not run')" ]
[ ! -f "$stub/calls.log" ]
