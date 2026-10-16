#!/bin/sh
# Merge the pull request by the method merge-method.sh decided, after proving it is mergeable.
# Usage: sh scripts/merge-pr.sh <state-dir> [--approve] [--migrations-checked]
# Exit 4: refused, writing nothing, because the pull request changes
# migration files (one "migration <path>" line each) or the forge listed
# fewer files than changed, unless --migrations-checked says a person
# has verified the migrations outside the pull request.
# Exit 5: refused, writing nothing, because the base branch moved: the
# pull request is conflicting or behind, and must be brought up to date.
# Exit 7: refused, writing nothing, under --approve when author-trust.sh
# does not trust the author: an automatic merge needs an author who can
# push to the repository, and anyone else's merge needs a person.
# Exit 6: refused, writing nothing, for one of two reasons. Either the
# ledger does not allow a merge, found before the forge is asked anything:
# one line each for a finding still open ("open <id>"), a wont-fix
# finding no person accepted ("unaccepted <id>"), a finding marked
# addressed that no verifier has judged ("unverified <id>"), each item of a
# review phase review-progress.sh reports incomplete ("review ...",
# "dedup ...", "gap ..."), and, when the check gate is armed, a head the
# check has not passed at ("check <reason>");
# or the head is not the one the review covered: someone pushed since,
# and reviewed-head.sh leads to reviewing those commits first.
# Exits 4 and 5 journal "merge migrations|moved <head>" in steps.txt for
# next-step.sh, the only write either makes.
# The head branch is deleted after the merge only when the repository
# does not delete it itself, no open pull request bases on it, and it
# is not a fork's; the result line says which.
set -eu

dir=${1:?usage: merge-pr.sh <state-dir> [--approve] [--migrations-checked]}
shift
approve=''
checked=0
for arg in "$@"; do
	case "$arg" in
	--approve) approve=--approve ;;
	--migrations-checked) checked=1 ;;
	*)
		echo "merge-pr: unknown argument: $arg" >&2
		exit 1
		;;
	esac
done
[ -f "$dir/meta.txt" ] || {
	echo "merge-pr: no meta.txt in $dir" >&2
	exit 1
}
owner=$(sed -n 's/^owner //p' "$dir/meta.txt")
repo=$(sed -n 's/^repo //p' "$dir/meta.txt")
pr=$(sed -n 's/^pr //p' "$dir/meta.txt")
author=$(sed -n 's/^author //p' "$dir/meta.txt")
self=$(sed -n 's/^self_login //p' "$dir/meta.txt")
head_branch=$(sed -n 's/^head_branch //p' "$dir/meta.txt")
head_sha=$(sed -n 's/^head_sha //p' "$dir/meta.txt")
reviewed=$(sed -n 's/^reviewed_head //p' "$dir/meta.txt")
[ -n "$reviewed" ] || reviewed=$head_sha
cross_repo=$(sed -n 's/^cross_repo //p' "$dir/meta.txt")

record="$dir/pr-context/merge-method.txt"
[ -f "$record" ] || {
	echo "merge-pr: no merge method decided, run merge-method.sh first" >&2
	exit 1
}
method=$(sed -n 's/^method //p' "$record")
case "$method" in
merge | squash | rebase) ;;
*)
	echo "merge-pr: the merge method is $method, decide it with merge-method.sh first" >&2
	exit 1
	;;
esac
delete_on_merge=$(sed -n 's/^delete_branch_on_merge //p' "$record")

# The ledger, not the session's memory, says whether the review allows
# a merge.
here=$(dirname -- "$0")
refused=''
rc=0
progress=$(sh "$here/review-progress.sh" "$dir") || rc=$?
case "$rc" in
0) ;;
3) refused="$refused
$(printf '%s\n' "$progress" | sed 1d)" ;;
*) exit 1 ;;
esac
if [ -d "$dir/findings" ]; then
	rc=0
	counts=$(sh "$here/count-findings.sh" "$dir" --list) || rc=$?
	[ "$rc" -eq 0 ] || [ "$rc" -eq 3 ] || exit 1
	for id in $(printf '%s\n' "$counts" | sed -n 's/^open_ids//p'); do
		refused="$refused
open $id"
	done
	for id in $(printf '%s\n' "$counts" | sed -n 's/^wont_fix_ids//p'); do
		sed '/^---$/q' "$dir/findings/$id" | grep -qx 'accepted: yes' ||
			refused="$refused
unaccepted $id"
	done
	for id in $(printf '%s\n' "$counts" | sed -n 's/^addressed_ids//p'); do
		refused="$refused
unverified $id"
	done
fi
# Armed means the baseline passed for the command now configured; then
# the head must have passed it, by the last gate run at that head or by
# a baseline taken there.
check=$(sh "$here/setting.sh" "$dir" check_command)
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
			refused="$refused
check failed at $head_sha"
			;;
		*)
			[ "$baseline" = "pass $check_hash $head_sha" ] || refused="$refused
check not run at $head_sha"
			;;
		esac
		;;
	*)
		refused="$refused
check has no baseline for the configured command"
		;;
	esac
fi
if [ -n "$refused" ]; then
	echo "merge-pr: the ledger does not allow a merge$refused"
	exit 6
fi

attempts=5
settle=${MERGE_PR_SETTLE_SECONDS:-3}
while :; do
	status=$(gh pr view "$pr" --repo "$owner/$repo" \
		--json state,isDraft,mergeable,mergeStateStatus,changedFiles,files,headRefOid \
		--jq '"state \(.state)\ndraft \(.isDraft)\nmergeable \(.mergeable)\nmerge_state \(.mergeStateStatus)\nchanged \(.changedFiles)\nhead \(.headRefOid)", (.files[] | "file \(.path)")')
	mergeable=$(printf '%s\n' "$status" | sed -n 's/^mergeable //p')
	[ "$mergeable" = "UNKNOWN" ] || break
	attempts=$((attempts - 1))
	if [ "$attempts" -eq 0 ]; then
		echo "merge-pr: mergeability still UNKNOWN after waiting, try again shortly" >&2
		exit 1
	fi
	sleep "$settle"
done
state=$(printf '%s\n' "$status" | sed -n 's/^state //p')
draft=$(printf '%s\n' "$status" | sed -n 's/^draft //p')
merge_state=$(printf '%s\n' "$status" | sed -n 's/^merge_state //p')

[ "$state" = "OPEN" ] || {
	echo "merge-pr: pull request is $state, not open" >&2
	exit 1
}
[ "$draft" = "false" ] || {
	echo "merge-pr: pull request is a draft" >&2
	exit 1
}
live=$(printf '%s\n' "$status" | sed -n 's/^head //p')
if [ -z "$reviewed" ] || [ "$live" != "$reviewed" ]; then
	echo "merge-pr: the head is ${live:-unknown}, not ${reviewed:-unknown} that the review covered; review what was pushed since first"
	exit 6
fi
moved=""
[ "$mergeable" = CONFLICTING ] && moved=CONFLICTING
[ "$merge_state" = BEHIND ] && moved=BEHIND
if [ -n "$moved" ]; then
	printf 'merge moved %s\n' "$head_sha" >>"$dir/steps.txt"
	echo "merge-pr: pull request is $moved, bring the branch up to date first"
	exit 5
fi
[ "$mergeable" = "MERGEABLE" ] || {
	echo "merge-pr: pull request is not mergeable: $mergeable" >&2
	exit 1
}
case "$merge_state" in
CLEAN) ;;
UNSTABLE)
	echo "merge-pr: merge state is UNSTABLE (a non-required check is failing), continuing" >&2
	;;
*)
	echo "merge-pr: merge state is $merge_state, refusing" >&2
	exit 1
	;;
esac

if [ "$checked" -eq 0 ]; then
	changed=$(printf '%s\n' "$status" | sed -n 's/^changed //p')
	listed=$(printf '%s\n' "$status" | grep -c '^file ' || true)
	if [ -n "$changed" ] && [ "$listed" -lt "$changed" ]; then
		printf 'merge migrations %s\n' "$head_sha" >>"$dir/steps.txt"
		echo "merge-pr: only $listed of $changed changed files listed, so migrations cannot be ruled out; a person decides"
		exit 4
	fi
	migrations=$(printf '%s\n' "$status" | sed -n 's/^file //p' | sh "$(dirname -- "$0")/match-paths.sh" "$dir" migration_paths)
	if [ -n "$migrations" ]; then
		printf 'merge migrations %s\n' "$head_sha" >>"$dir/steps.txt"
		echo "merge-pr: migrations changed, a person decides"
		printf '%s\n' "$migrations" | sed 's/^/migration /'
		exit 4
	fi
fi

if [ "$approve" = "--approve" ]; then
	trust=$(sh "$(dirname -- "$0")/author-trust.sh" "$dir") || {
		echo "merge-pr: ${trust:-the author could not be checked}; an automatic merge needs a person"
		exit 7
	}
fi

branch='branch deleted'
delete=--delete-branch
if [ "$cross_repo" = true ]; then
	branch='branch kept (it belongs to a fork)' delete=''
elif [ "$delete_on_merge" = true ]; then
	branch='branch kept (the repository deletes it)' delete=''
elif [ -n "$head_branch" ]; then
	if list=$(gh pr list --repo "$owner/$repo" --base "$head_branch" --state open --json number --jq '.[].number'); then
		dependents=$(printf '%s\n' "$list" | sed '/^$/d; s/^/#/' | tr '\n' ' ')
		dependents=${dependents% }
		[ -z "$dependents" ] || branch="branch kept ($dependents bases on it)" delete=''
	else
		branch='branch kept (dependents could not be checked)' delete=''
	fi
fi

if [ "$approve" = "--approve" ]; then
	credit=$(sh "$(dirname -- "$0")/attribution.sh" "$dir")
	[ -z "$credit" ] || credit=$(printf '\n\n%s' "$credit")
	if [ -n "$self" ] && [ "$author" != "$self" ]; then
		gh pr review "$pr" --repo "$owner/$repo" --approve \
			--body "Review converged: no open findings.$credit" >/dev/null
	else
		gh pr comment "$pr" --repo "$owner/$repo" \
			--body "Review converged: no open findings. Authors cannot approve their own pull requests, so this comment stands in for the approval.$credit" >/dev/null
	fi
fi

gh pr merge "$pr" --repo "$owner/$repo" "--$method" --match-head-commit "$reviewed" $delete >/dev/null

final=$(gh pr view "$pr" --repo "$owner/$repo" --json state --jq .state)
[ "$final" = "MERGED" ] || {
	echo "merge-pr: merge reported success but the pull request is $final" >&2
	exit 2
}
echo "merge-pr: $owner/$repo#$pr merged by $method, $branch"
