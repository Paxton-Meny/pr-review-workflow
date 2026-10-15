#!/bin/sh
# Decide whether the pull request's author is trusted with the repository.
# Usage: sh scripts/author-trust.sh <state-dir> [--exec | --approve]
# Trusted (exit 0): the signed-in account's own pull request, or an
# author whose permission on the repository, as init-state.sh recorded
# it, is write, maintain, or admin. When GitHub could not say, as for a
# bot or a failed call, a branch in the repository itself counts, since
# only an account that can push makes one; a fork's does not.
# Untrusted (exit 3) otherwise. An automatic merge needs a trusted
# author: the review is a model reading text the author wrote. Prints
# "author-trust: trusted|untrusted <author> <reason>", and, for an
# untrusted author on a run whose check command or contract prefixes
# are set, a second line saying they will not run on this code unless
# approved.
#
# --exec answers whether the pull request's code may execute here: the
# check command, suggestion proving, and contracts all run it. Exit 0
# for a trusted author or one approved for this pull request, exit 3
# otherwise, with one line. --approve records the user's yes for this
# pull request's author (exec-approved.txt); only the user gives it.
set -eu

dir=${1:?usage: author-trust.sh <state-dir> [--exec | --approve]}
mode=${2:-}
case "$mode" in
'' | --exec | --approve) ;;
*)
	echo "author-trust: unknown argument: $mode" >&2
	exit 1
	;;
esac
[ -f "$dir/meta.txt" ] || {
	echo "author-trust: no meta.txt in $dir" >&2
	exit 1
}
meta() { sed -n "s/^$1 //p" "$dir/meta.txt" | head -n 1; }
author=$(meta author)
self=$(meta self_login)
permission=$(meta author_permission)
cross_repo=$(meta cross_repo)

if [ "$mode" = --approve ]; then
	[ -n "$author" ] || {
		echo "author-trust: no author recorded to approve" >&2
		exit 1
	}
	tmp=$(mktemp "$dir/.approve.XXXXXX")
	printf 'approved %s\n' "$author" >"$tmp"
	mv "$tmp" "$dir/exec-approved.txt"
	echo "author-trust: approved running $author's code for this pull request"
	exit 0
fi

approved() { [ -n "$author" ] && grep -qxF "approved $author" "$dir/exec-approved.txt" 2>/dev/null; }

verdict() {
	# verdict trusted|untrusted <reason>
	if [ "$mode" = --exec ]; then
		if [ "$1" = trusted ]; then
			echo "author-trust: code runs, ${author:-unknown} $2"
			exit 0
		fi
		if approved; then
			echo "author-trust: code runs, approved for ${author:-unknown}"
			exit 0
		fi
		echo "author-trust: code does not run, ${author:-unknown} $2"
		exit 3
	fi
	echo "author-trust: $1 ${author:-unknown} $2"
	[ "$1" = trusted ] && exit 0
	if approved; then
		echo "author-trust: you approved running this author's code here"
	elif [ -f "$dir/settings.txt" ] &&
		[ -n "$(sh "$(dirname -- "$0")/setting.sh" "$dir" check_command)$(sh "$(dirname -- "$0")/setting.sh" "$dir" contract_commands)" ]; then
		echo "author-trust: the check command and contracts will not run on this code unless you approve it"
	fi
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
