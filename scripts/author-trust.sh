#!/bin/sh
# Decide whether the pull request's author is trusted with the repository.
# Usage: sh scripts/author-trust.sh <state-dir>
# Trusted (exit 0): the signed-in account's own pull request, or an
# author whose permission on the repository, as init-state.sh recorded
# it, is write, maintain, or admin. When GitHub could not say, as for a
# bot or a failed call, a branch in the repository itself counts, since
# only an account that can push makes one; a fork's does not.
# Untrusted (exit 3) otherwise. An automatic merge needs a trusted
# author: the review is a model reading text the author wrote. Prints
# "author-trust: trusted|untrusted <author> <reason>".
set -eu

dir=${1:?usage: author-trust.sh <state-dir>}
[ -f "$dir/meta.txt" ] || {
	echo "author-trust: no meta.txt in $dir" >&2
	exit 1
}
meta() { sed -n "s/^$1 //p" "$dir/meta.txt" | head -n 1; }
author=$(meta author)
self=$(meta self_login)
permission=$(meta author_permission)
cross_repo=$(meta cross_repo)

verdict() {
	# verdict trusted|untrusted <reason>
	echo "author-trust: $1 ${author:-unknown} $2"
	[ "$1" = trusted ] && exit 0
	exit 3
}

[ -n "$author" ] || verdict untrusted "no author recorded"
[ -n "$self" ] && [ "$author" = "$self" ] && verdict trusted "own pull request"
case "${permission:-unknown}" in
admin | maintain | write) verdict trusted "$permission permission" ;;
unknown)
	[ "$cross_repo" = false ] && verdict trusted "branch in the repository, permission unknown"
	verdict untrusted "fork, permission unknown"
	;;
*) verdict untrusted "$permission permission" ;;
esac
