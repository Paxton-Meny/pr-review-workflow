#!/bin/sh
# Put a settings file in place for the clone this runs in, once the
# resolver's lint accepts it.
# Usage: sh scripts/write-settings.sh shared|personal|local [--replace] <<'END'
#        <key> <value>
#        ...
#        END
#
# shared writes .claude/pr-review-workflow.conf for the team to commit,
# and refuses when the repository ignores that path, since an ignored
# file can never reach the base branch. personal writes the same path
# as the user's own; local writes .claude/pr-review-workflow.local.conf.
# Both refuse a path the repository tracks, and add the path to the
# clone's git info/exclude when nothing ignores it yet. From a linked
# worktree, which may be a disposable one, both are written in the main
# worktree instead, where the resolver reads them for every worktree of
# the clone, unless this worktree already holds the file or tracks its
# path, since the resolver reads this worktree first; a bare main
# worktree leaves them here, and the output says so. The shared file belongs to the branch, so it is always written
# here. An existing file is replaced only with --replace. The file is
# linted first as the source it will become, written whole and
# atomically, then read back. Prints the lint's lines, the absolute
# path written, one "write-settings: wrote" line, and a
# "write-settings: next:" line saying what remains to do.
set -eu

usage='usage: write-settings.sh shared|personal|local [--replace]'
audience=${1:?$usage}
replace=0
case "${2:-}" in
'') ;;
--replace) replace=1 ;;
*)
	echo "write-settings: $usage" >&2
	exit 1
	;;
esac
[ $# -le 2 ] || {
	echo "write-settings: $usage" >&2
	exit 1
}
case "$audience" in
shared)
	path=.claude/pr-review-workflow.conf
	lint_as=shared
	;;
personal)
	path=.claude/pr-review-workflow.conf
	lint_as=personal
	;;
local)
	path=.claude/pr-review-workflow.local.conf
	lint_as=personal
	;;
*)
	echo "write-settings: audience must be shared, personal, or local: $audience" >&2
	exit 1
	;;
esac

clone=$(git rev-parse --show-toplevel 2>/dev/null) || {
	echo "write-settings: run it from inside a clone" >&2
	exit 1
}
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

work=$(mktemp -d)
tmp=''
trap 'rm -rf "$work" "$tmp"' EXIT

# A file of your own goes where every worktree reads it: the main one.
root=$clone
where=''
if [ "$audience" != shared ]; then
	git_dir=$(git -C "$clone" rev-parse --path-format=absolute --git-dir)
	common_dir=$(git -C "$clone" rev-parse --path-format=absolute --git-common-dir)
	# The resolver reads this worktree's file first, so one already here,
	# or a path this branch tracks, keeps the write here.
	if [ "$git_dir" != "$common_dir" ] && [ ! -e "$clone/$path" ] && [ ! -L "$clone/$path" ] &&
		! git -C "$clone" ls-files --error-unmatch "$path" >/dev/null 2>&1; then
		git -C "$clone" worktree list --porcelain >"$work/worktrees" 2>/dev/null || :
		main=$(sed -n '1s/^worktree //p' "$work/worktrees")
		bare=$(awk 'NR > 1 && /^$/ { exit } $0 == "bare" { print "yes" }' "$work/worktrees")
		if [ -n "$main" ] && [ -z "$bare" ] && [ -d "$main" ]; then
			root=$main
			where="in the main worktree $main, where every worktree of this clone reads it"
		else
			where="in this worktree, since the main one is bare; other worktrees will not read it"
		fi
	fi
fi

tr -d '\r' >"$work/new"
grep -qvE '^[[:space:]]*(#|$)' "$work/new" || {
	echo "write-settings: nothing to write: no settings arrived on stdin" >&2
	exit 1
}
if ! sh "$here/resolve-settings.sh" --lint "$lint_as" "$work/new" >"$work/lint"; then
	cat "$work/lint"
	echo "write-settings: refused: the lint found entries a $lint_as file cannot set" >&2
	exit 1
fi
cat "$work/lint"

target="$root/$path"
[ ! -L "$target" ] || {
	echo "write-settings: refusing to write through a symlink at $path" >&2
	exit 1
}
if [ -e "$target" ] && [ "$replace" -eq 0 ]; then
	echo "write-settings: $path exists; read it, then pass --replace to overwrite it" >&2
	exit 1
fi
tracked=0
git -C "$root" ls-files --error-unmatch "$path" >/dev/null 2>&1 && tracked=1
ignored=0
git -C "$root" check-ignore -q "$path" 2>/dev/null && ignored=1
case "$audience" in
shared)
	[ "$ignored" -eq 0 ] || {
		echo "write-settings: the repository ignores $path, so a shared file there could never be committed; un-ignore it, or write a personal file" >&2
		exit 1
	}
	;;
*)
	[ "$tracked" -eq 0 ] || {
		echo "write-settings: the repository tracks $path, so it is the team's; write shared to change it, or local for your own overrides" >&2
		exit 1
	}
	;;
esac

mkdir -p "$(dirname -- "$target")"
tmp=$(mktemp "$target.XXXXXX")
cat "$work/new" >"$tmp"
mv "$tmp" "$target"
tmp=''
cmp -s "$work/new" "$target" || {
	echo "write-settings: $path does not read back as written" >&2
	exit 1
}

if [ "$audience" != shared ] && [ "$ignored" -eq 0 ]; then
	exclude=$(git -C "$root" rev-parse --path-format=absolute --git-path info/exclude)
	mkdir -p "$(dirname -- "$exclude")"
	printf '%s\n' "$path" >>"$exclude"
	git -C "$root" check-ignore -q "$path" || {
		echo "write-settings: $path is still not ignored after adding it to $exclude" >&2
		exit 1
	}
	echo "write-settings: excluded $path through git's info/exclude"
fi

count=$(grep -cvE '^[[:space:]]*(#|$)' "$target" || true)
echo "write-settings: path $target"
[ -z "$where" ] || echo "write-settings: written $where"
echo "write-settings: wrote $path as the $audience file, $count settings"
if [ "$audience" = shared ]; then
	echo "write-settings: next: commit and push $path; each teammate approves its commands once, on their first review"
else
	echo "write-settings: next: nothing; the file is yours and git ignores it"
fi
