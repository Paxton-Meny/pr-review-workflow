#!/bin/sh
# Resolve a pull request reference against the clone in the working directory.
# Usage: sh scripts/resolve-ref.sh <pr-ref>
# Prints "owner repo number". Fails when the reference is malformed or the
# clone's origin is a different repository.
set -eu

ref=${1:?usage: resolve-ref.sh <pr-ref>}

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
	case "$number" in
	'' | *[!0-9]*) ;;
	*)
		repo_line=$(gh repo view --json owner,name --jq '"\(.owner.login) \(.name)"') || {
			echo "resolve-ref: not inside a GitHub repository and no owner/repo in: $ref" >&2
			exit 1
		}
		owner=${repo_line%% *}
		repo=${repo_line##* }
		;;
	esac
	;;
esac

case "$number" in
'' | *[!0-9]*)
	echo "resolve-ref: no pull request number in: $ref" >&2
	exit 1
	;;
esac
for name in "$owner" "$repo"; do
	case "$name" in
	'' | . | .. | *[!A-Za-z0-9_.-]*)
		echo "resolve-ref: unsafe repository name: $name" >&2
		exit 1
		;;
	esac
done

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
	echo "resolve-ref: run from inside a clone of $owner/$repo" >&2
	exit 1
}
url=$(git -C "$repo_root" remote get-url origin 2>/dev/null) || {
	echo "resolve-ref: the clone at $repo_root has no origin remote" >&2
	exit 1
}
case "$url" in
*[/:]"$owner/$repo" | *[/:]"$owner/$repo/" | *[/:]"$owner/$repo.git" | *[/:]"$owner/$repo.git/") ;;
*)
	echo "resolve-ref: origin of $repo_root is $url, not $owner/$repo; run from a clone of the reviewed repository" >&2
	exit 1
	;;
esac

printf '%s %s %s\n' "$owner" "$repo" "$number"
