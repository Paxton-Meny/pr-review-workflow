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
# Exit 6: refused, writing nothing, because the head is not the one the
# review covered: someone pushed since, and reviewed-head.sh leads to
# reviewing those commits first.
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
		echo "merge-pr: only $listed of $changed changed files listed, so migrations cannot be ruled out; a person decides"
		exit 4
	fi
	migrations=$(printf '%s\n' "$status" | sed -n 's/^file //p' | sh "$(dirname -- "$0")/match-paths.sh" "$dir" migration_paths)
	if [ -n "$migrations" ]; then
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
