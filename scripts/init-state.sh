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

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
	echo "init-state: run from inside a clone of $owner/$repo" >&2
	exit 1
}
url=$(git -C "$repo_root" remote get-url origin 2>/dev/null) || {
	echo "init-state: the clone at $repo_root has no origin remote" >&2
	exit 1
}
case "$url" in
*[/:]"$owner/$repo" | *[/:]"$owner/$repo/" | *[/:]"$owner/$repo.git" | *[/:]"$owner/$repo.git/") ;;
*)
	echo "init-state: origin of $repo_root is $url, not $owner/$repo; run from a clone of the reviewed repository" >&2
	exit 1
	;;
esac

meta=$(gh pr view "$number" --repo "$owner/$repo" \
	--json author,headRefName,baseRefName,headRefOid,url,state,isCrossRepository,maintainerCanModify,headRepository,headRepositoryOwner \
	--jq '"author \(.author.login)\nhead_branch \(.headRefName)\nbase_branch \(.baseRefName)\nhead_sha \(.headRefOid)\nurl \(.url)\ncross_repo \(.isCrossRepository)\nmaintainer_can_modify \(.maintainerCanModify)\nhead_repo_url \(if .headRepository then "https://github.com/\(.headRepositoryOwner.login)/\(.headRepository.name).git" else "" end)\nstate \(.state)"')
state=$(printf '%s\n' "$meta" | sed -n 's/^state //p')
if [ "$state" != "OPEN" ]; then
	echo "init-state: pull request $owner/$repo#$number is $state, not open" >&2
	exit 1
fi
self=$(gh api user --jq '"\(.login) \(.id)"')
self_login=${self%% *}
self_id=${self##* }
case "$self_id" in
'' | *[!0-9]*) self_email="${self_login}@users.noreply.github.com" ;;
*) self_email="${self_id}+${self_login}@users.noreply.github.com" ;;
esac

dir="$data_root/state/${owner}__${repo}__${number}"
mkdir -p "$dir"
tmp=$(mktemp "$dir/.meta.XXXXXX")
{
	printf 'owner %s\nrepo %s\npr %s\n' "$owner" "$repo" "$number"
	printf '%s\n' "$meta" | sed '/^state /d'
	printf 'self_login %s\nself_email %s\n' "$self_login" "$self_email"
} >"$tmp"
mv "$tmp" "$dir/meta.txt"
if [ ! -f "$dir/round.txt" ]; then
	tmp=$(mktemp "$dir/.round.XXXXXX")
	printf '0\n' >"$tmp"
	mv "$tmp" "$dir/round.txt"
fi

printf '%s\n' "$dir"
