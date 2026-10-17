#!/bin/sh
# Prove an editor batch left the user's own checkout as it found it.
# Usage: sh scripts/checkout-guard.sh <state-dir> before|after
# before records the checkout's head, branch, the local branches no other
# worktree has checked out, status, tracked changes, and untracked
# contents; after compares, and exits 3 naming what changed, appending
# one "escape" line to escapes.txt.
set -eu
LC_ALL=C
export LC_ALL

dir=${1:?usage: checkout-guard.sh <state-dir> before|after}
phase=${2:?usage: checkout-guard.sh <state-dir> before|after}
case "$phase" in
before | after) ;;
*)
	echo "checkout-guard: phase must be before or after: $phase" >&2
	exit 1
	;;
esac
[ -f "$dir/meta.txt" ] || {
	echo "checkout-guard: no meta.txt in $dir" >&2
	exit 1
}
root=$(sed -n 's/^repo_root //p' "$dir/meta.txt")
[ -n "$root" ] && [ -d "$root" ] || {
	echo "checkout-guard: meta.txt records no user checkout, run checkout-pr.sh first" >&2
	exit 1
}
snapshot="$dir/checkout-guard.txt"
max_lines=20

look() {
	git -C "$root" --no-optional-locks -c core.quotepath=off "$@"
}

take() {
	printf 'head %s\n' "$(look rev-parse -q --verify HEAD || echo none)"
	printf 'ref %s\n' "$(look symbolic-ref -q HEAD || echo detached)"
	# A branch another worktree has out moves with that worktree's own
	# commits, often a concurrent session's, so it is left out.
	{
		look worktree list --porcelain
		echo '#refs'
		look for-each-ref --format='branch %(refname) %(objectname)' refs/heads
	} | SELF=$(look rev-parse --show-toplevel) awk '
		/^#refs$/ { refs = 1; next }
		!refs && /^worktree / { path = substr($0, 10); next }
		!refs && /^branch / { if (path != ENVIRON["SELF"]) other[substr($0, 8)] = 1; next }
		refs && !($2 in other)
	'
	look status --porcelain=v1 --untracked-files=all | sed 's/^/status /'
	printf 'diff %s\n' "$(look diff --no-ext-diff --no-textconv --binary HEAD 2>/dev/null | cksum)"
	look ls-files --others --exclude-standard | while IFS= read -r path; do
		printf 'untracked %s %s\n' "$(look hash-object -- "$path" 2>/dev/null || echo unreadable)" "$path"
	done
}

if [ "$phase" = before ]; then
	tmp=$(mktemp "$dir/.guard.XXXXXX")
	take >"$tmp"
	mv "$tmp" "$snapshot"
	echo "checkout-guard: recorded the user checkout at $(sed -n 's/^head //p' "$snapshot")"
	exit 0
fi

[ -f "$snapshot" ] || {
	echo "checkout-guard: nothing recorded, run checkout-guard.sh $dir before first" >&2
	exit 1
}
now=$(mktemp "$dir/.guard.XXXXXX")
was=$(mktemp "$dir/.guard.XXXXXX")
trap 'rm -f "$now" "$was"' EXIT
take | sort >"$now"
sort "$snapshot" >"$was"
if cmp -s "$was" "$now"; then
	echo "checkout-guard: the user checkout is unchanged"
	exit 0
fi

printf 'escape\n' >>"$dir/escapes.txt"
{
	echo "checkout-guard: the user checkout at $root changed during the editor batch; inspect it before anything else"
	{
		comm -23 "$was" "$now" | sed 's/^/was /'
		comm -13 "$was" "$now" | sed 's/^/now /'
	} | head -n "$max_lines" | sed 's/^/checkout-guard: /'
} >&2
exit 3
