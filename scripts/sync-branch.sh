#!/bin/sh
# Bring the pull request branch up to date with its base when the forge
# says it must be: conflicting, or behind a base that requires it.
# Usage: sh scripts/sync-branch.sh <state-dir> [--continue | --abort]
#
# The mechanism follows the merge method merge-method.sh decided: under
# rebase merging the worktree is rebased onto origin/<base> and pushed
# with a lease on the head the run last saw; under merge or squash
# merging origin/<base> is merged into the head and pushed plainly, so
# nothing is rewritten. With branch_sync off a moved base is reported
# (exit 4) and nothing is touched. Conflicts stop the update: under
# update it is aborted and the paths are printed (exit 3) for a person;
# under resolve the worktree is left mid-way with the paths in
# pr-context/conflicts.txt, each followed by the base commits that
# touched it, for the editor, which then runs --continue. --continue
# refuses (exit 3) while a conflicted path still holds a marker,
# stages the rest, continues the rebase or commits the merge, and
# pushes; --abort restores the worktree. After any update,
# pr-context/sync-changed.txt lists the changed files whose patch
# against the base is no longer what it was, which is empty after a
# clean update and names the resolved files after a resolution, and
# sync.txt in the state directory gains "update <method> <old> <new>" or
# "conflicts <n> files". After SYNC_CAP updates on one pull request a
# moved base is reported like off (exit 4): a base that keeps moving
# is for a person.
# Paths are read with core.quotepath=off, so non-ASCII names pass through
# whole; names with quotes, tabs, or backslashes stay quoted by git and
# are not supported.
set -eu
export GIT_EDITOR=true

dir=${1:?usage: sync-branch.sh <state-dir> [--continue | --abort]}
mode=${2:-}
case "$mode" in
'' | --continue | --abort) ;;
*)
	echo "sync-branch: unknown argument: $mode" >&2
	exit 1
	;;
esac
[ -f "$dir/meta.txt" ] || {
	echo "sync-branch: no meta.txt in $dir" >&2
	exit 1
}
worktree="$dir/worktree"
ctx="$dir/pr-context"
[ -d "$worktree" ] && [ -d "$ctx" ] || {
	echo "sync-branch: state in $dir is incomplete, run checkout-pr.sh first" >&2
	exit 1
}
record="$ctx/merge-method.txt"
[ -f "$record" ] || {
	echo "sync-branch: no merge method decided, run merge-method.sh first" >&2
	exit 1
}
method=$(sed -n 's/^method //p' "$record")
case "$method" in
merge | squash | rebase) ;;
*)
	echo "sync-branch: the merge method is $method, decide it with merge-method.sh first" >&2
	exit 1
	;;
esac
owner=$(sed -n 's/^owner //p' "$dir/meta.txt")
repo=$(sed -n 's/^repo //p' "$dir/meta.txt")
pr=$(sed -n 's/^pr //p' "$dir/meta.txt")
base=$(sed -n 's/^base_branch //p' "$dir/meta.txt")
repo_root=$(sed -n 's/^repo_root //p' "$dir/meta.txt")
self_login=$(sed -n 's/^self_login //p' "$dir/meta.txt")
self_email=$(sed -n 's/^self_email //p' "$dir/meta.txt")
setting=$(sh "$(dirname -- "$0")/setting.sh" "$dir" branch_sync)
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

SYNC_CAP=3
mechanism=merge
[ "$method" = rebase ] && mechanism=rebase

in_progress() {
	git_dir=$(git -C "$worktree" rev-parse --git-dir)
	[ -d "$git_dir/rebase-merge" ] || [ -d "$git_dir/rebase-apply" ] || [ -f "$git_dir/MERGE_HEAD" ]
}

conflicted() {
	git -C "$worktree" -c core.quotepath=off diff --name-only --diff-filter=U
}

patch_hashes() {
	# patch_hashes: one "hash path" line per file changed against the base
	git -C "$worktree" -c core.quotepath=off diff --name-only "origin/$base...HEAD" | while read -r path; do
		# patch-id of the changed lines alone: index lines, hunk headers and
		# context a moved base shifts do not count
		hash=$(git -C "$worktree" -c core.quotepath=off diff -U0 "origin/$base...HEAD" -- "$path" | git patch-id --stable | cut -d' ' -f1)
		printf '%s %s\n' "${hash:-none}" "$path"
	done
}

old_head=$(sed -n 's/^head_sha //p' "$dir/meta.txt")

finish() {
	# finish: push, record, and list the files whose patch changed
	pushed=yes
	if [ "$mechanism" = rebase ]; then
		sh "$here/push-branch.sh" "$dir" --force-with-lease >/dev/null || pushed=no
	else
		sh "$here/push-branch.sh" "$dir" >/dev/null || pushed=no
	fi
	if [ "$pushed" = no ]; then
		git -C "$worktree" reset --hard --quiet "$old_head"
		rm -f "$ctx/sync-before.txt" "$ctx/conflicts.txt"
		echo "sync-branch: the push was refused, the worktree is back at $old_head" >&2
		exit 1
	fi
	new_head=$(git -C "$worktree" rev-parse HEAD)
	patch_hashes >"$ctx/sync-after.txt"
	changed=$(mktemp "$ctx/.sync.XXXXXX")
	awk 'NR == FNR { before[$2] = $1; next } !($2 in before) || before[$2] != $1 { print $2 }' \
		"$ctx/sync-before.txt" "$ctx/sync-after.txt" >"$changed"
	mv "$changed" "$ctx/sync-changed.txt"
	rm -f "$ctx/sync-before.txt" "$ctx/sync-after.txt"
	printf 'update %s %s %s\n' "$method" "$old_head" "$new_head" >>"$dir/sync.txt"
	verb=merged
	[ "$mechanism" = rebase ] && verb=rebased
	echo "sync-branch: $verb onto $base at $new_head, pushed, $(grep -c . "$ctx/sync-changed.txt" || true) files changed by the resolution"
}

stopped() {
	# stopped: the update hit conflicts; report by the setting
	paths=$(conflicted)
	count=$(printf '%s\n' "$paths" | grep -c . || true)
	if [ "$count" -eq 0 ]; then
		# git failed for another reason: leave nothing half done
		if in_progress; then
			if [ "$mechanism" = rebase ]; then
				git -C "$worktree" rebase --abort
			else
				git -C "$worktree" merge --abort
			fi
		fi
		rm -f "$ctx/sync-before.txt" "$ctx/conflicts.txt"
		echo "sync-branch: the update failed without conflicts, a person decides" >&2
		exit 1
	fi
	printf 'conflicts %s files\n' "$count" >>"$dir/sync.txt"
	if [ "$setting" = resolve ]; then
		tmp=$(mktemp "$ctx/.sync.XXXXXX")
		merge_base=$(git -C "$worktree" merge-base "origin/$base" "$old_head")
		printf '%s\n' "$paths" | while read -r path; do
			printf 'path %s\n' "$path"
			git -C "$worktree" -c core.quotepath=off log --format='  base %h %s' "$merge_base..origin/$base" -- "$path"
		done >"$tmp"
		mv "$tmp" "$ctx/conflicts.txt"
		echo "sync-branch: conflicts in $count files, the worktree holds the $mechanism"
		printf '%s\n' "$paths" | sed 's/^/conflict /'
		exit 3
	fi
	if [ "$mechanism" = rebase ]; then
		git -C "$worktree" rebase --abort
	else
		git -C "$worktree" merge --abort
	fi
	echo "sync-branch: conflicts in $count files, a person decides"
	printf '%s\n' "$paths" | sed 's/^/conflict /'
	exit 3
}

identity() {
	# identity <git args>: as the signed-in account, whatever the environment says
	GIT_AUTHOR_NAME=$self_login GIT_AUTHOR_EMAIL=$self_email GIT_COMMITTER_NAME=$self_login GIT_COMMITTER_EMAIL=$self_email \
		git -C "$worktree" "$@"
}

if [ "$mode" = --abort ]; then
	in_progress || {
		echo "sync-branch: nothing to abort"
		exit 0
	}
	if [ "$mechanism" = rebase ]; then
		git -C "$worktree" rebase --abort
	else
		git -C "$worktree" merge --abort
	fi
	rm -f "$ctx/conflicts.txt" "$ctx/sync-before.txt"
	echo "sync-branch: aborted, the worktree is back at $(git -C "$worktree" rev-parse HEAD)"
	exit 0
fi

if [ "$mode" = --continue ]; then
	in_progress || {
		echo "sync-branch: no update in progress" >&2
		exit 1
	}
	[ -f "$ctx/sync-before.txt" ] || {
		echo "sync-branch: no record of the update's start in $ctx" >&2
		exit 1
	}
	marked=$(conflicted | while read -r path; do
		grep -Eq '^(<{7}|={7}|>{7})' "$worktree/$path" 2>/dev/null && printf '%s\n' "$path"
	done || true)
	if [ -n "$marked" ]; then
		echo "sync-branch: conflict markers remain in $(printf '%s\n' "$marked" | grep -c .) files"
		printf '%s\n' "$marked" | sed 's/^/conflict /'
		exit 3
	fi
	conflicted | while read -r path; do
		git -C "$worktree" add -- "$path"
	done
	if [ "$mechanism" = rebase ]; then
		if ! identity rebase --continue >/dev/null 2>&1; then
			stopped
		fi
	else
		identity commit --quiet --no-edit
	fi
	rm -f "$ctx/conflicts.txt"
	finish
	exit 0
fi

in_progress && {
	echo "sync-branch: an update is in progress, continue or abort it first" >&2
	exit 1
}

attempts=5
settle=${MERGE_PR_SETTLE_SECONDS:-3}
while :; do
	status=$(gh pr view "$pr" --repo "$owner/$repo" --json mergeable,mergeStateStatus \
		--jq '"mergeable \(.mergeable)\nmerge_state \(.mergeStateStatus)"')
	mergeable=$(printf '%s\n' "$status" | sed -n 's/^mergeable //p')
	[ "$mergeable" = UNKNOWN ] || break
	attempts=$((attempts - 1))
	if [ "$attempts" -eq 0 ]; then
		echo "sync-branch: mergeability still UNKNOWN after waiting, try again shortly" >&2
		exit 1
	fi
	sleep "$settle"
done
merge_state=$(printf '%s\n' "$status" | sed -n 's/^merge_state //p')
moved=''
[ "$merge_state" = BEHIND ] && moved=BEHIND
[ "$mergeable" = CONFLICTING ] && moved=CONFLICTING
if [ -z "$moved" ]; then
	echo "sync-branch: current"
	exit 0
fi
updates=0
[ -f "$dir/sync.txt" ] && updates=$(grep -c '^update ' "$dir/sync.txt" || true)
if [ "$updates" -ge "$SYNC_CAP" ]; then
	echo "sync-branch: updated $updates times already, pull request is $moved, a person decides"
	exit 4
fi
if [ "$setting" = off ]; then
	echo "sync-branch: off, pull request is $moved, a person decides"
	exit 4
fi
[ -n "$repo_root" ] && [ -d "$repo_root" ] || {
	echo "sync-branch: meta.txt records no clone to fetch the base into" >&2
	exit 1
}
sh "$here/fetch-base.sh" "$repo_root" "$base" >/dev/null || {
	echo "sync-branch: origin/$base is unavailable" >&2
	exit 1
}
[ -z "$(git -C "$worktree" status --porcelain --untracked-files=no)" ] || {
	echo "sync-branch: the worktree has uncommitted changes" >&2
	exit 1
}
patch_hashes >"$ctx/sync-before.txt"
if [ "$mechanism" = rebase ]; then
	identity rebase --quiet "origin/$base" >/dev/null 2>&1 || stopped
else
	identity merge --quiet --no-edit "origin/$base" >/dev/null 2>&1 || stopped
fi
finish
