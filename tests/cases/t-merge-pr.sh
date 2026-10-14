#!/bin/sh
# merge-pr: refuses bad states, approves or falls back, merges by the
# decided method, keeps a branch that must stay, proves the merge.
set -eu

stub="$SCRATCH/stub"
mkdir -p "$stub"
export GH_STUB_DIR="$stub"
export PATH="$REPO_ROOT/tests/stubs:$PATH"
. "$REPO_ROOT/tests/fixture-identity.sh"
author="${fixture_login}_author"
dir="$SCRATCH/data/state/${fixture_owner}__widgets__7"
mkdir -p "$dir/pr-context"
printf 'owner %s\nrepo widgets\npr 7\nauthor %s\nself_login %s\nhead_branch feat/x\nhead_sha abc123\ncross_repo false\n' "$fixture_owner" "$author" "$fixture_login" >"$dir/meta.txt"
# This ledger has no clone, so the overlap check is off until the drift
# section below builds one.
printf 'overlap_check off\n' | sh "$REPO_ROOT/scripts/resolve-settings.sh" "$dir" >/dev/null
printf '0\n' >"$dir/round.txt"
printf 'plan\nplanned all samples 1\nsaved all 0\ngap skip no-risk-signal\n' >"$dir/review.txt"
method() {
	# method <name> [delete_branch_on_merge]
	printf 'method %s\nreason setting\nallowed merge squash rebase\ndelete_branch_on_merge %s\nhistory merge 0 squash 0 rebase 0 either 0\n' "$1" "${2:-false}" >"$dir/pr-context/merge-method.txt"
}
clean='state OPEN\ndraft false\nhead abc123\nmergeable MERGEABLE\nmerge_state CLEAN\n'

# No decided method, nothing happens.
if sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir" 2>"$SCRATCH/err"; then
	echo "expected refusal without a decided merge method" >&2
	exit 1
fi
grep -q "run merge-method.sh first" "$SCRATCH/err"
method undecided
if sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir" 2>"$SCRATCH/err"; then
	echo "expected refusal of an undecided merge method" >&2
	exit 1
fi
grep -q "merge method is undecided" "$SCRATCH/err"
[ ! -f "$stub/calls.log" ]

method rebase
printf "$clean" >"$stub/pr-view.1"
: >"$stub/pr-review"
: >"$stub/pr-list"
: >"$stub/pr-merge"
printf 'MERGED\n' >"$stub/pr-view.2"
sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir" --approve | grep -qx "merge-pr: $fixture_owner/widgets#7 merged by rebase, branch deleted"
grep -q "^pr review 7 --repo $fixture_owner/widgets --approve" "$stub/calls.log"
[ "$(tail -n 1 "$dir/steps.txt")" = "merge done $(sed -n 's/^head_sha //p' "$dir/meta.txt")" ]
grep -q 'Reviewed with \[pr-review-workflow\]' "$stub/calls.log" || {
	echo "a clean run's approval is its first comment and names the plugin" >&2
	exit 1
}
grep -qx "pr merge 7 --repo $fixture_owner/widgets --rebase --match-head-commit abc123 --delete-branch" "$stub/calls.log"
grep -qx "pr list --repo $fixture_owner/widgets --base feat/x --state open --json number --jq .\[\].number" "$stub/calls.log"

# The method the record names is the one passed; the branch stays when
# the repository deletes it, when an open pull request bases on it, or
# when it is a fork's.
rm -f "$stub"/pr-view.*.done "$stub/calls.log"
printf 'owner %s\nrepo widgets\npr 7\nauthor %s\nself_login %s\nhead_branch feat/x\nhead_sha abc123\ncross_repo false\n' "$fixture_owner" "$fixture_login" "$fixture_login" >"$dir/meta.txt"
method squash true
printf "$clean" >"$stub/pr-view.1"
: >"$stub/pr-comment"
printf 'MERGED\n' >"$stub/pr-view.2"
printf '1\n' >"$dir/round.txt"
out=$(sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir" --approve)
[ "$out" = "merge-pr: $fixture_owner/widgets#7 merged by squash, branch kept (the repository deletes it)" ]
grep -qx "pr merge 7 --repo $fixture_owner/widgets --squash --match-head-commit abc123" "$stub/calls.log"
grep -q '^pr comment 7' "$stub/calls.log"
if grep -q 'Reviewed with' "$stub/calls.log"; then
	echo "after a posted round the approval must not name the plugin again" >&2
	exit 1
fi
if grep -q '^pr review' "$stub/calls.log"; then
	echo "own pull request must not be approved" >&2
	exit 1
fi
if grep -q '^pr list' "$stub/calls.log"; then
	echo "no dependents are looked up when the repository deletes the branch itself" >&2
	exit 1
fi

rm -f "$stub"/pr-view.*.done "$stub/calls.log"
method merge
printf "$clean" >"$stub/pr-view.1"
printf '9\n11\n' >"$stub/pr-list"
printf 'MERGED\n' >"$stub/pr-view.2"
out=$(sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir")
[ "$out" = "merge-pr: $fixture_owner/widgets#7 merged by merge, branch kept (#9 #11 bases on it)" ]
grep -qx "pr merge 7 --repo $fixture_owner/widgets --merge --match-head-commit abc123" "$stub/calls.log"

# An unknown answer about dependents keeps the branch.
rm -f "$stub"/pr-view.*.done "$stub/calls.log" "$stub/pr-list"
printf "$clean" >"$stub/pr-view.1"
printf 'MERGED\n' >"$stub/pr-view.2"
printf '1\n' >"$stub/pr-list.exit"
out=$(sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir")
[ "$out" = "merge-pr: $fixture_owner/widgets#7 merged by merge, branch kept (dependents could not be checked)" ]
grep -qx "pr merge 7 --repo $fixture_owner/widgets --merge --match-head-commit abc123" "$stub/calls.log"
rm -f "$stub/pr-list.exit"

rm -f "$stub"/pr-view.*.done "$stub/calls.log"
sed -i 's/^cross_repo false$/cross_repo true/' "$dir/meta.txt"
printf "$clean" >"$stub/pr-view.1"
printf 'MERGED\n' >"$stub/pr-view.2"
out=$(sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir")
[ "$out" = "merge-pr: $fixture_owner/widgets#7 merged by merge, branch kept (it belongs to a fork)" ]
grep -qx "pr merge 7 --repo $fixture_owner/widgets --merge --match-head-commit abc123" "$stub/calls.log"

# An automatic merge needs an author who can push: another account's
# fork is refused under --approve, writing nothing, and merges when a
# person asked for it; write permission lets it through.
sed -i "s/^author .*/author $author/" "$dir/meta.txt"
rm -f "$stub"/pr-view.* "$stub/calls.log"
printf "$clean" >"$stub/pr-view.1"
rc=0
out=$(sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir" --approve) || rc=$?
[ "$rc" -eq 7 ]
[ "$out" = "merge-pr: author-trust: untrusted $author fork, permission unknown; an automatic merge needs a person" ]
if grep -qE '^pr (review|comment|merge)' "$stub/calls.log"; then
	echo "an untrusted author's automatic merge must write nothing" >&2
	exit 1
fi
printf 'author_permission read\n' >>"$dir/meta.txt"
sed -i 's/^cross_repo true$/cross_repo false/' "$dir/meta.txt"
rm -f "$stub"/pr-view.*
printf "$clean" >"$stub/pr-view.1"
rc=0
sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir" --approve >/dev/null || rc=$?
[ "$rc" -eq 7 ]
rm -f "$stub"/pr-view.* "$stub/calls.log"
printf "$clean" >"$stub/pr-view.1"
printf 'MERGED\n' >"$stub/pr-view.2"
sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir" >/dev/null
grep -q '^pr merge 7' "$stub/calls.log"
sed -i 's/^author_permission .*/author_permission write/' "$dir/meta.txt"
sed -i 's/^cross_repo false$/cross_repo true/' "$dir/meta.txt"
rm -f "$stub"/pr-view.* "$stub/calls.log"
printf "$clean" >"$stub/pr-view.1"
printf 'MERGED\n' >"$stub/pr-view.2"
sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir" --approve >/dev/null
grep -q "^pr review 7 --repo $fixture_owner/widgets --approve" "$stub/calls.log"
grep -q '^pr merge 7' "$stub/calls.log"
sed -i -e '/^author_permission /d' -e 's/^cross_repo true$/cross_repo false/' "$dir/meta.txt"

# A base that moved is a distinct refusal, writing nothing.
for status in 'mergeable CONFLICTING\nmerge_state DIRTY' 'mergeable MERGEABLE\nmerge_state BEHIND'; do
	rm -f "$stub"/pr-view.* "$stub/calls.log"
	printf "state OPEN\ndraft false\nhead abc123\n$status\n" >"$stub/pr-view.1"
	rc=0
	out=$(sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir" --approve) || rc=$?
	[ "$rc" -eq 5 ]
	[ "$(tail -n 1 "$dir/steps.txt")" = "merge moved abc123" ]
	case "$out" in
	'merge-pr: pull request is CONFLICTING, bring the branch up to date first' | 'merge-pr: pull request is BEHIND, bring the branch up to date first') ;;
	*)
		echo "unexpected line: $out" >&2
		exit 1
		;;
	esac
	if grep -qE '^pr (review|comment|merge)' "$stub/calls.log"; then
		echo "a moved base must write nothing to the pull request" >&2
		exit 1
	fi
done

rm -f "$stub"/pr-view.*
printf 'state OPEN\ndraft false\nhead abc123\nmergeable MERGEABLE\nmerge_state BLOCKED\n' >"$stub/pr-view.1"
if sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir" 2>"$SCRATCH/err"; then
	echo "expected refusal of a blocked merge state" >&2
	exit 1
fi
grep -q "merge state is BLOCKED, refusing" "$SCRATCH/err"

rm -f "$stub"/pr-view.*
printf "$clean" >"$stub/pr-view.1"
printf 'OPEN\n' >"$stub/pr-view.2"
rc=0
sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir" 2>"$SCRATCH/err" || rc=$?
[ "$rc" -eq 2 ]
grep -q "reported success but the pull request is OPEN" "$SCRATCH/err"

export MERGE_PR_SETTLE_SECONDS=0
rm -f "$stub"/pr-view.*
printf 'state OPEN\ndraft false\nhead abc123\nmergeable UNKNOWN\nmerge_state CLEAN\n' >"$stub/pr-view.1"
printf "$clean" >"$stub/pr-view.2"
: >"$stub/pr-comment"
printf 'MERGED\n' >"$stub/pr-view.3"
sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir" >/dev/null

rm -f "$stub"/pr-view.*
for n in 1 2 3 4 5; do
	printf 'state OPEN\ndraft false\nhead abc123\nmergeable UNKNOWN\nmerge_state CLEAN\n' >"$stub/pr-view.$n"
done
if sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir" 2>"$SCRATCH/err"; then
	echo "expected failure when mergeability never settles" >&2
	exit 1
fi
grep -q "still UNKNOWN after waiting" "$SCRATCH/err"

# A pull request changing migrations never merges until a person has
# checked what the review cannot see, with or without --approve, and a
# file list too short to rule migrations out is refused the same way.
rm -f "$stub"/pr-view.* "$stub/calls.log"
status="${clean}changed 2\nfile app/migrations/0002_add_email.py\nfile src/app.py\n"
for flag in --approve ''; do
	printf "$status" >"$stub/pr-view.1"
	rc=0
	out=$(sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir" $flag) || rc=$?
	[ "$rc" -eq 4 ]
	[ "$out" = "$(printf 'merge-pr: migrations changed, a person decides\nmigration app/migrations/0002_add_email.py')" ]
	[ "$(tail -n 1 "$dir/steps.txt")" = "merge migrations abc123" ]
	if grep -qE '^pr (review|comment|merge)' "$stub/calls.log"; then
		echo "a refused merge must write nothing to the pull request" >&2
		exit 1
	fi
	rm -f "$stub"/pr-view.*
done

printf "$status" >"$stub/pr-view.1"
printf 'MERGED\n' >"$stub/pr-view.2"
sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir" --approve --migrations-checked | grep -q "^merge-pr: $fixture_owner/widgets#7 merged by merge"
grep -q '^pr merge 7' "$stub/calls.log"

rm -f "$stub"/pr-view.* "$stub/calls.log"
printf "${clean}changed 150\nfile src/app.py\n" >"$stub/pr-view.1"
rc=0
out=$(sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir" --approve) || rc=$?
[ "$rc" -eq 4 ]
[ "$out" = "merge-pr: only 1 of 150 changed files listed, so migrations cannot be ruled out; a person decides" ]
if grep -qE '^pr (review|comment|merge)' "$stub/calls.log"; then
	echo "an incomplete file list must write nothing to the pull request" >&2
	exit 1
fi

# A head the review did not cover never merges, whatever head_sha a
# resumed init-state took from GitHub: the reviewed head decides, and
# the merge is pinned to it.
for meta_head in abc123 def456; do
	rm -f "$stub"/pr-view.* "$stub/calls.log"
	sed -i -e '/^reviewed_head /d' -e "s/^head_sha .*/head_sha $meta_head/" "$dir/meta.txt"
	printf 'reviewed_head abc123\n' >>"$dir/meta.txt"
	printf 'state OPEN\ndraft false\nhead def456\nmergeable MERGEABLE\nmerge_state CLEAN\n' >"$stub/pr-view.1"
	rc=0
	out=$(sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir" --approve) || rc=$?
	[ "$rc" -eq 6 ]
	[ "$out" = "merge-pr: the head is def456, not abc123 that the review covered; review what was pushed since first" ]
	if grep -qE '^pr (review|comment|merge)' "$stub/calls.log"; then
		echo "an unreviewed head must write nothing to the pull request" >&2
		exit 1
	fi
done
rm -f "$stub"/pr-view.* "$stub/calls.log"
printf "$clean" >"$stub/pr-view.1"
printf 'MERGED\n' >"$stub/pr-view.2"
sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir" >/dev/null
grep -q '^pr merge 7 .* --match-head-commit abc123' "$stub/calls.log"
sed -i -e '/^reviewed_head /d' -e 's/^head_sha .*/head_sha abc123/' "$dir/meta.txt"

if sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir" --approve --checked 2>"$SCRATCH/err"; then
	echo "expected refusal of an unknown argument" >&2
	exit 1
fi
grep -q "unknown argument: --checked" "$SCRATCH/err"

# The ledger decides before the forge is asked anything: a finding still
# open, a wont-fix no person accepted, or an armed check that has not
# passed at the head refuses the merge, with or without --approve.
rm -f "$stub"/pr-view.* "$stub/calls.log"
: >"$stub/pr-list"
mkdir -p "$dir/findings"
finding() {
	# finding <id> <status>
	printf 'id: %s\nstatus: %s\ncategory: correctness\nseverity: major\npath: a.c\nline: 1\nend_line:\nside: RIGHT\nplacement: inline\ncomment_id: 1\ncommit:\nround: 1\nreopens: 0\ntitle: T\n---\nFix: x.\nResolution: x.\n' "$1" "$2" >"$dir/findings/$1"
}
finding F001 open
finding F002 wont-fix
finding F003 verified
finding F004 addressed
for flag in --approve ''; do
	rc=0
	out=$(sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir" $flag) || rc=$?
	[ "$rc" -eq 6 ]
	[ "$out" = "$(printf 'merge-pr: the ledger does not allow a merge\nopen F001\nunaccepted F002\nunverified F004')" ]
	[ ! -f "$stub/calls.log" ] || {
		echo "a ledger refusal must not reach the forge" >&2
		exit 1
	}
done
sh "$REPO_ROOT/scripts/update-finding.sh" "$dir" F001 status=addressed >/dev/null
sh "$REPO_ROOT/scripts/update-finding.sh" "$dir" F001 status=verified >/dev/null
rc=0
out=$(sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir") || rc=$?
[ "$rc" -eq 6 ]
[ "$out" = "$(printf 'merge-pr: the ledger does not allow a merge\nunaccepted F002\nunverified F004')" ]
sh "$REPO_ROOT/scripts/update-finding.sh" "$dir" F004 status=verified >/dev/null
rc=0
out=$(sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir") || rc=$?
[ "$rc" -eq 6 ]
[ "$out" = "$(printf 'merge-pr: the ledger does not allow a merge\nunaccepted F002')" ]
sh "$REPO_ROOT/scripts/update-finding.sh" "$dir" F002 accepted=yes >/dev/null
printf "$clean" >"$stub/pr-view.1"
printf 'MERGED\n' >"$stub/pr-view.2"
sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir" | grep -q "^merge-pr: $fixture_owner/widgets#7 merged by merge"

# With a check command configured, the head must have passed it.
printf 'check_command true\n' | sh "$REPO_ROOT/scripts/resolve-settings.sh" "$dir" >/dev/null
hash=$(printf 'true' | git hash-object --stdin)
refusal() {
	# refusal <line>: merge-pr refuses with exactly that reason
	rm -f "$stub"/pr-view.* "$stub/calls.log"
	rc=0
	out=$(sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir") || rc=$?
	[ "$rc" -eq 6 ] && [ "$out" = "$(printf 'merge-pr: the ledger does not allow a merge\n%s' "$1")" ] || {
		echo "expected the refusal '$1', got $rc: $out" >&2
		exit 1
	}
	[ ! -f "$stub/calls.log" ]
}
merges() {
	rm -f "$stub"/pr-view.* "$stub/calls.log"
	printf "$clean" >"$stub/pr-view.1"
	printf 'MERGED\n' >"$stub/pr-view.2"
	sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir" | grep -q "^merge-pr: $fixture_owner/widgets#7 merged by merge"
}
rm -f "$dir/check-baseline.txt" "$dir/check-gate.txt"
refusal 'check has no baseline for the configured command'
printf 'pass %s 0ld\n' "$hash" >"$dir/check-baseline.txt"
refusal 'check not run at abc123'
# A gate record for an older head counts as not run, pass or fail.
printf 'pass %s 0ld\n' "$hash" >"$dir/check-gate.txt"
refusal 'check not run at abc123'
printf 'fail %s 0ld\n' "$hash" >"$dir/check-gate.txt"
refusal 'check not run at abc123'
# A baseline taken for a different command does not arm the gate.
rm -f "$dir/check-gate.txt"
printf 'pass %s abc123\n' "$(printf 'other' | git hash-object --stdin)" >"$dir/check-baseline.txt"
refusal 'check has no baseline for the configured command'
printf 'pass %s 0ld\n' "$hash" >"$dir/check-baseline.txt"
printf 'fail %s abc123\n' "$hash" >"$dir/check-gate.txt"
refusal 'check failed at abc123'
printf 'pass %s abc123\n' "$hash" >"$dir/check-gate.txt"
merges
rm -f "$dir/check-gate.txt"
printf 'pass %s abc123\n' "$hash" >"$dir/check-baseline.txt"
merges
# A baseline that failed disarms the gate, so nothing is required.
printf 'fail %s 0ld\n' "$hash" >"$dir/check-baseline.txt"
merges
# The check does not run for an author the run does not trust, so no
# baseline or gate record is ever written and none is required.
rm -f "$dir/check-baseline.txt" "$dir/check-gate.txt"
sed -i 's/^cross_repo false$/cross_repo true/' "$dir/meta.txt"
printf 'author_permission read\n' >>"$dir/meta.txt"
merges
sed -i -e '/^author_permission /d' -e 's/^cross_repo true$/cross_repo false/' "$dir/meta.txt"
refusal 'check has no baseline for the configured command'

# Base drift. With a clone in the ledger and the overlap check on, commits
# landing on the base since the review are compared against the reviewed
# hunks before anything is written: disjoint ones merge, near ones refuse
# with exit 6 until a person decides or the comparer judged that very
# base independent, and off skips the check. Migrations are asked about
# first, so a drift question never hides one.
remote="$SCRATCH/remote.git"
git init --quiet --bare "$remote"
seed="$SCRATCH/seed"
git clone --quiet "$remote" "$seed" 2>/dev/null
git -C "$seed" config user.name tester
git -C "$seed" config user.email tester@example.invalid
mkdir -p "$seed/src"
awk 'BEGIN { print "def alpha():"; for (i = 2; i <= 20; i++) print "    a" i " = " i; print "def beta():"; for (i = 22; i <= 40; i++) print "    b" i " = " i }' >"$seed/src/app.py"
git -C "$seed" add .
git -C "$seed" commit --quiet -m base
git -C "$seed" push --quiet origin HEAD:main
git -C "$seed" checkout --quiet -b feature
sed -i 's/^    a10 = 10$/    a10 = 100/' "$seed/src/app.py"
git -C "$seed" commit --quiet -am feature
git -C "$seed" push --quiet origin feature
head=$(git -C "$seed" rev-parse HEAD)
git -C "$seed" checkout --quiet main
clone="$SCRATCH/clone"
git clone --quiet "$remote" "$clone" 2>/dev/null
git -C "$clone" fetch --quiet origin feature
printf 'owner %s\nrepo widgets\npr 7\nauthor %s\nself_login %s\nbase_branch main\nhead_branch feature\nhead_sha %s\nrepo_root %s\n' "$fixture_owner" "$fixture_login" "$fixture_login" "$head" "$clone" >"$dir/meta.txt"
mkdir -p "$dir/pr-context"
method rebase
: >"$stub/pr-list"
git -C "$clone" diff "origin/main...$head" >"$dir/pr-context/diff.patch"
printf 'src/app.py\t1\t1\n' >"$dir/pr-context/files.txt"
sh "$REPO_ROOT/scripts/split-diff.sh" "$dir" >/dev/null
: | sh "$REPO_ROOT/scripts/resolve-settings.sh" "$dir" >/dev/null
land() {
	git -C "$seed" commit --quiet -am "$1"
	git -C "$seed" push --quiet origin main
}
clean='state OPEN\ndraft false\nmergeable MERGEABLE\nmerge_state CLEAN\nchanged 1\nfile src/app.py\n'

# Nothing landed: merges as before.
rm -f "$stub"/pr-view.* "$stub/calls.log"
printf "$clean" >"$stub/pr-view.1"
printf 'MERGED\n' >"$stub/pr-view.2"
sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir" | grep -qx "merge-pr: $fixture_owner/widgets#7 merged by rebase, branch deleted"

# A disjoint landing merges too.
sed -i 's/^    b35 = 35$/    b35 = 350/' "$seed/src/app.py"
land far
rm -f "$stub"/pr-view.* "$stub/calls.log"
printf "$clean" >"$stub/pr-view.1"
printf 'MERGED\n' >"$stub/pr-view.2"
sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir" | grep -qx "merge-pr: $fixture_owner/widgets#7 merged by rebase, branch deleted"

# A near landing refuses before any write, with the drift lines.
sed -i 's/^    a15 = 15$/    a15 = 150/' "$seed/src/app.py"
land near
rm -f "$stub"/pr-view.* "$stub/calls.log"
printf "$clean" >"$stub/pr-view.1"
rc=0
out=$(sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir" --approve) || rc=$?
[ "$rc" -eq 6 ]
printf '%s\n' "$out" | sed -n 1p | grep -qx 'merge-pr: base moved under the review and touches the reviewed hunks, a person decides'
printf '%s\n' "$out" | grep -qx 'base-drift: 2 commits landed, 1 files shared, level near'
printf '%s\n' "$out" | grep -qx 'drift near src/app.py ours 10-10 theirs 15-15 in def alpha():'
if grep -qE '^pr (review|comment|merge)' "$stub/calls.log"; then
	echo "a drift refusal must write nothing to the pull request" >&2
	exit 1
fi

# A person's decision merges it.
rm -f "$stub"/pr-view.* "$stub/calls.log"
printf "$clean" >"$stub/pr-view.1"
printf 'MERGED\n' >"$stub/pr-view.2"
sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir" --overlap-checked | grep -qx "merge-pr: $fixture_owner/widgets#7 merged by rebase, branch deleted"
grep -q '^pr merge 7' "$stub/calls.log"

# So does an independent verdict, but only on the base it judged.
printf 'verdict base independent: alpha gains an unrelated constant five lines below.\n' |
	sh "$REPO_ROOT/scripts/save-verdict.sh" "$dir" base | grep -qx 'save-verdict: base independent'
rm -f "$stub"/pr-view.* "$stub/calls.log"
printf "$clean" >"$stub/pr-view.1"
printf 'MERGED\n' >"$stub/pr-view.2"
out=$(sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir")
printf '%s\n' "$out" | grep -qx 'merge-pr: base moved under the review; the comparer judged the overlap independent, continuing'
printf '%s\n' "$out" | grep -qx "merge-pr: $fixture_owner/widgets#7 merged by rebase, branch deleted"
sed -i 's/^    a12 = 12$/    a12 = 120/' "$seed/src/app.py"
land nearer
rm -f "$stub"/pr-view.* "$stub/calls.log"
printf "$clean" >"$stub/pr-view.1"
rc=0
out=$(sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir") || rc=$?
[ "$rc" -eq 6 ]
! printf '%s\n' "$out" | grep -q '^verdict '
if grep -q '^pr merge' "$stub/calls.log"; then
	echo "a verdict on an older base must not carry a merge" >&2
	exit 1
fi
# A verdict other than independent is relayed and still asks.
printf 'verdict base duplicate: both set a12.\n' | sh "$REPO_ROOT/scripts/save-verdict.sh" "$dir" base >/dev/null
rm -f "$stub"/pr-view.* "$stub/calls.log"
printf "$clean" >"$stub/pr-view.1"
rc=0
out=$(sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir") || rc=$?
[ "$rc" -eq 6 ]
printf '%s\n' "$out" | grep -qx 'verdict duplicate: both set a12.'

# An independent verdict for an earlier base carries nothing when the base
# cannot be read this time: the drift of the earlier attempt is gone.
printf 'verdict base independent: unrelated.\n' | sh "$REPO_ROOT/scripts/save-verdict.sh" "$dir" base >/dev/null
mv "$remote" "$remote.gone"
git -C "$clone" update-ref -d refs/remotes/origin/main
rm -f "$stub"/pr-view.* "$stub/calls.log"
printf "$clean" >"$stub/pr-view.1"
rc=0
out=$(sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir") || rc=$?
mv "$remote.gone" "$remote"
[ "$rc" -eq 6 ]
if grep -q '^pr merge' "$stub/calls.log"; then
	echo "an unreadable base must not be waved through by an old verdict" >&2
	exit 1
fi
git -C "$clone" fetch --quiet origin "+refs/heads/main:refs/remotes/origin/main"

# Migrations are asked about before drift.
rm -f "$stub"/pr-view.* "$stub/calls.log"
printf 'state OPEN\ndraft false\nmergeable MERGEABLE\nmerge_state CLEAN\nchanged 2\nfile src/app.py\nfile db/migrate/001_x.rb\n' >"$stub/pr-view.1"
rc=0
out=$(sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir") || rc=$?
[ "$rc" -eq 4 ]

# Off skips the check entirely.
printf 'overlap_check off\n' | sh "$REPO_ROOT/scripts/resolve-settings.sh" "$dir" >/dev/null
rm -f "$stub"/pr-view.* "$stub/calls.log" "$dir/pr-context/drift.txt"
printf "$clean" >"$stub/pr-view.1"
printf 'MERGED\n' >"$stub/pr-view.2"
sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir" | grep -qx "merge-pr: $fixture_owner/widgets#7 merged by rebase, branch deleted"
[ ! -f "$dir/pr-context/drift.txt" ] || {
	echo "off must not run the drift check" >&2
	exit 1
}
