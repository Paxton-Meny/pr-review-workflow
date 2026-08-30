#!/bin/sh
# Create or refresh the review state directory for one pull request.
# Usage: sh scripts/init-state.sh <data-root> <pr-ref>
set -eu

data_root=${1:?usage: init-state.sh <data-root> <pr-ref>}
ref=${2:?usage: init-state.sh <data-root> <pr-ref>}

owner='' repo='' number=''
case "$ref" in
https://github.com/*/pull/*)
	rest=${ref#https://github.com/}
	owner=${rest%%/*}
	rest=${rest#*/}
	repo=${rest%%/*}
	number=$(printf '%s' "${rest#*/pull/}" | sed 's/[^0-9].*//')
	;;
*/*\#*)
	owner=${ref%%/*}
	rest=${ref#*/}
	repo=${rest%%\#*}
	number=${rest#*\#}
	;;
*)
	number=$ref
	repo_line=$(gh repo view --json owner,name --jq '"\(.owner.login) \(.name)"') || {
		echo "init-state: not inside a GitHub repository and no owner/repo in: $ref" >&2
		exit 1
	}
	owner=${repo_line%% *}
	repo=${repo_line##* }
	;;
esac

case "$number" in
'' | *[!0-9]*)
	echo "init-state: no pull request number in: $ref" >&2
	exit 1
	;;
esac
for name in "$owner" "$repo"; do
	case "$name" in
	'' | . | .. | *[!A-Za-z0-9_.-]*)
		echo "init-state: unsafe repository name: $name" >&2
		exit 1
		;;
	esac
done

meta=$(gh pr view "$number" --repo "$owner/$repo" \
	--json author,headRefName,baseRefName,headRefOid,url,state \
	--jq '"author \(.author.login)\nhead_branch \(.headRefName)\nbase_branch \(.baseRefName)\nhead_sha \(.headRefOid)\nurl \(.url)\nstate \(.state)"')
state=$(printf '%s\n' "$meta" | sed -n 's/^state //p')
if [ "$state" != "OPEN" ]; then
	echo "init-state: pull request $owner/$repo#$number is $state, not open" >&2
	exit 1
fi
self=$(gh api user --jq .login)

dir="$data_root/state/${owner}__${repo}__${number}"
mkdir -p "$dir"
tmp=$(mktemp "$dir/.meta.XXXXXX")
{
	printf 'owner %s\nrepo %s\npr %s\n' "$owner" "$repo" "$number"
	printf '%s\n' "$meta" | sed '/^state /d'
	printf 'self_login %s\n' "$self"
} >"$tmp"
mv "$tmp" "$dir/meta.txt"
[ -f "$dir/round.txt" ] || printf '0\n' >"$dir/round.txt"

printf '%s\n' "$dir"
