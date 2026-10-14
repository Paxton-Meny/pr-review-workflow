#!/bin/sh
# sync-branch: current, off, a clean rebase with a leased push, a clean
# merge update, conflicts handed to a person, conflicts resolved and
# continued under both mechanisms, a stale lease, abort, and refusals.
set -eu

export PATH="$REPO_ROOT/tests/stubs:$PATH"
export MERGE_PR_SETTLE_SECONDS=0
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

setup() {
	# setup <name> <behind|conflict|region> <method> <branch_sync>: a bare origin
	# whose main moved under a feat branch, a clone, the run's state, and
	# the worktree checkout-pr.sh makes; sets origin, clone, dir, wt, stub
	root="$SCRATCH/$1"
	mkdir -p "$root/o" "$root/stub"
	stub="$root/stub"
	export GH_STUB_DIR="$stub"
	origin="$root/o/r.git"
	git init -q --bare "$origin"
	clone="$root/clone"
	git clone -q "$origin" "$clone" 2>/dev/null
	g() { git -C "$clone" "$@"; }
	printf 'base\n2\n3\n4\n5\n6\n7\n8\n9\n10\n' >"$clone/a.txt"
	printf 'base\n' >"$clone/b.txt"
	g add a.txt b.txt && g commit -q -m "Start" && g push -q origin HEAD:main
	g checkout -q -b feat
	sed '1s/.*/feat/' "$clone/a.txt" >"$clone/a.new" && mv "$clone/a.new" "$clone/a.txt"
	g commit -q -am "Change a on feat" && g push -q origin feat
	head=$(g rev-parse HEAD)
	g checkout -q main
	if [ "$2" = conflict ]; then
		sed '1s/.*/main/' "$clone/a.txt" >"$clone/a.new" && mv "$clone/a.new" "$clone/a.txt"
		g commit -q -am "Change a on main"
	elif [ "$2" = region ]; then
		sed '10s/.*/main/' "$clone/a.txt" >"$clone/a.new" && mv "$clone/a.new" "$clone/a.txt"
		g commit -q -am "Change the end of a on main"
	else
		printf 'new\n' >"$clone/c.txt"
		g add c.txt && g commit -q -m "Add c on main"
	fi
	g push -q origin HEAD:main
	base_tip=$(g rev-parse HEAD)
	dir="$root/data/state/o__r__7"
	mkdir -p "$dir/pr-context"
	printf 'owner o\nrepo r\npr 7\nhead_branch feat\nhead_sha %s\nbase_branch main\ncross_repo false\nself_login tester\nself_email tester@example.invalid\n' "$head" >"$dir/meta.txt"
	printf 'sync %s\n' "$4" >"$dir/overrides.txt"
	: | sh "$REPO_ROOT/scripts/resolve-settings.sh" "$dir" >/dev/null
	printf 'method %s\nreason setting\nallowed merge squash rebase\ndelete_branch_on_merge false\nhistory merge 0 squash 0 rebase 0 either 0\n' "$3" >"$dir/pr-context/merge-method.txt"
	wt=$(cd "$clone" && sh "$REPO_ROOT/scripts/checkout-pr.sh" "$dir" | head -n 1)
	printf 'mergeable MERGEABLE\nmerge_state BEHIND\n' >"$stub/pr-view"
}
sync() { sh "$REPO_ROOT/scripts/sync-branch.sh" "$dir" "$@"; }
origin_feat() { git -C "$origin" rev-parse refs/heads/feat; }

# Nothing to do when the forge is content; off reports a moved base
# and touches nothing.
setup current behind rebase update
printf 'mergeable MERGEABLE\nmerge_state CLEAN\n' >"$stub/pr-view"
[ "$(sync)" = "sync-branch: current" ]
[ "$(origin_feat)" = "$head" ]
setup off conflict rebase off
printf 'mergeable CONFLICTING\nmerge_state DIRTY\n' >"$stub/pr-view"
rc=0
out=$(sync) || rc=$?
[ "$rc" -eq 4 ]
[ "$out" = "sync-branch: off, pull request is CONFLICTING, a person decides" ]
[ "$(origin_feat)" = "$head" ]
[ "$(git -C "$wt" rev-parse HEAD)" = "$head" ]
[ ! -f "$dir/sync.txt" ]

# A clean rebase under rebase merging: the branch is replayed onto the
# base, pushed with a lease, and nothing about its change moved.
setup rebase behind rebase update
out=$(sync)
new=$(git -C "$wt" rev-parse HEAD)
[ "$out" = "sync-branch: rebased onto main at $new, pushed, 0 files changed by the resolution" ]
[ "$(origin_feat)" = "$new" ]
[ "$(git -C "$wt" rev-parse HEAD~1)" = "$base_tip" ]
[ "$(git -C "$wt" rev-list --count --merges HEAD)" -eq 0 ]
grep -qx "head_sha $new" "$dir/meta.txt"
grep -qx "prev_head $head" "$dir/meta.txt"
[ ! -s "$dir/pr-context/sync-changed.txt" ]
grep -qx "update rebase $head $new" "$dir/sync.txt"
printf 'mergeable MERGEABLE\nmerge_state CLEAN\n' >"$stub/pr-view"
[ "$(sync)" = "sync-branch: current" ]
[ "$(grep -c '^update ' "$dir/sync.txt")" -eq 1 ]

# The base editing another region of a file the branch changed leaves
# that file out of the list, under both mechanisms.
for method in rebase squash; do
	setup region-$method region $method update
	out=$(sync)
	new=$(git -C "$wt" rev-parse HEAD)
	case "$out" in
	*"$new, pushed, 0 files changed by the resolution") ;;
	*) echo "unexpected line: $out" >&2; exit 1 ;;
	esac
	[ "$(git -C "$wt" show HEAD:a.txt | sed -n '1p;10p' | tr '\n' ' ')" = "feat main " ]
	[ ! -s "$dir/pr-context/sync-changed.txt" ]
done

# A clean update under squash merging merges the base in: a merge
# commit, a plain push, the old head still in the history.
setup merge behind squash update
out=$(sync)
new=$(git -C "$wt" rev-parse HEAD)
[ "$out" = "sync-branch: merged onto main at $new, pushed, 0 files changed by the resolution" ]
[ "$(origin_feat)" = "$new" ]
[ "$(git -C "$wt" rev-list --count --merges HEAD)" -eq 1 ]
[ "$(git -C "$wt" rev-parse HEAD^1)" = "$head" ]
[ "$(git -C "$wt" rev-parse HEAD^2)" = "$base_tip" ]
[ "$(git -C "$wt" log -1 --format=%an)" = tester ]
grep -qx "update squash $head $new" "$dir/sync.txt"

# Conflicts under update are aborted and handed to a person.
setup handoff conflict rebase update
printf 'mergeable CONFLICTING\nmerge_state DIRTY\n' >"$stub/pr-view"
rc=0
out=$(sync) || rc=$?
[ "$rc" -eq 3 ]
[ "$out" = "$(printf 'sync-branch: conflicts in 1 files, a person decides\nconflict a.txt')" ]
[ "$(git -C "$wt" rev-parse HEAD)" = "$head" ]
[ -z "$(git -C "$wt" status --porcelain)" ]
[ "$(origin_feat)" = "$head" ]
grep -qx 'conflicts 1 files' "$dir/sync.txt"
[ ! -f "$dir/pr-context/conflicts.txt" ]

# Under resolve the worktree holds the rebase for the editor; continue
# refuses markers, then finishes, pushes with the lease, and names the
# resolved file as changed by the resolution.
setup resolve conflict rebase resolve
printf 'mergeable CONFLICTING\nmerge_state DIRTY\n' >"$stub/pr-view"
rc=0
out=$(sync) || rc=$?
[ "$rc" -eq 3 ]
[ "$out" = "$(printf 'sync-branch: conflicts in 1 files, the worktree holds the rebase\nconflict a.txt')" ]
grep -qx 'path a.txt' "$dir/pr-context/conflicts.txt"
grep -q '^  base [0-9a-f]* Change a on main$' "$dir/pr-context/conflicts.txt"
grep -q '^<<<<<<<' "$wt/a.txt"
rc=0
out=$(sync --continue) || rc=$?
[ "$rc" -eq 3 ]
[ "$out" = "$(printf 'sync-branch: conflict markers remain in 1 files\nconflict a.txt')" ]
printf 'main and feat\n' >"$wt/a.txt"
out=$(sync --continue)
new=$(git -C "$wt" rev-parse HEAD)
[ "$out" = "sync-branch: rebased onto main at $new, pushed, 1 files changed by the resolution" ]
[ "$(origin_feat)" = "$new" ]
[ "$(git -C "$wt" rev-parse HEAD~1)" = "$base_tip" ]
[ "$(cat "$dir/pr-context/sync-changed.txt")" = a.txt ]
[ ! -f "$dir/pr-context/conflicts.txt" ]
grep -qx "update rebase $head $new" "$dir/sync.txt"
if sync --continue 2>"$SCRATCH/err"; then
	echo "expected refusal to continue when no update is in progress" >&2
	exit 1
fi
grep -q "no update in progress" "$SCRATCH/err"

# The same under merge merging commits the merge as the signed-in account.
setup resolve-merge conflict merge resolve
printf 'mergeable CONFLICTING\nmerge_state DIRTY\n' >"$stub/pr-view"
rc=0
out=$(sync) || rc=$?
[ "$rc" -eq 3 ]
[ "$out" = "$(printf 'sync-branch: conflicts in 1 files, the worktree holds the merge\nconflict a.txt')" ]
printf 'main and feat\n' >"$wt/a.txt"
out=$(sync --continue)
new=$(git -C "$wt" rev-parse HEAD)
[ "$out" = "sync-branch: merged onto main at $new, pushed, 1 files changed by the resolution" ]
[ "$(git -C "$wt" rev-list --count --merges HEAD)" -eq 1 ]
[ "$(git -C "$wt" log -1 --format=%ae)" = tester@example.invalid ]
[ "$(origin_feat)" = "$new" ]
[ "$(cat "$dir/pr-context/sync-changed.txt")" = a.txt ]

# Abort restores the worktree.
setup abort conflict rebase resolve
printf 'mergeable CONFLICTING\nmerge_state DIRTY\n' >"$stub/pr-view"
sync >/dev/null || true
[ "$(sync --abort)" = "sync-branch: aborted, the worktree is back at $head" ]
[ -z "$(git -C "$wt" status --porcelain)" ]
[ ! -f "$dir/pr-context/conflicts.txt" ]
[ "$(sync --abort)" = "sync-branch: nothing to abort" ]

# A push someone else made since the run last looked refuses the lease.
setup stale behind rebase update
other="$SCRATCH/stale/other"
git clone -q "$origin" "$other" 2>/dev/null
git -C "$other" checkout -q feat
printf 'theirs\n' >"$other/b.txt"
git -C "$other" commit -q -am "Someone else's push" && git -C "$other" push -q origin feat
theirs=$(git -C "$other" rev-parse HEAD)
if sync >/dev/null 2>"$SCRATCH/err"; then
	echo "expected the leased push to refuse a moved branch" >&2
	exit 1
fi
[ "$(origin_feat)" = "$theirs" ]

# Refusals: no decided method, an undecided one, an unknown argument.
setup refuse behind rebase update
rm "$dir/pr-context/merge-method.txt"
if sync 2>"$SCRATCH/err"; then
	echo "expected refusal without a merge method" >&2
	exit 1
fi
grep -q "run merge-method.sh first" "$SCRATCH/err"
if sync --wat 2>"$SCRATCH/err"; then
	echo "expected refusal of an unknown argument" >&2
	exit 1
fi
grep -q "unknown argument: --wat" "$SCRATCH/err"
if sh "$REPO_ROOT/scripts/sync-branch.sh" "$SCRATCH/nowhere" 2>"$SCRATCH/err"; then
	echo "expected failure without meta.txt" >&2
	exit 1
fi
grep -q "no meta.txt" "$SCRATCH/err"

# A base that keeps moving is for a person after three updates.
setup capped behind rebase update
printf 'update rebase a b\nupdate rebase b c\nupdate rebase c d\n' >"$dir/sync.txt"
rc=0
out=$(sync) || rc=$?
[ "$rc" -eq 4 ]
[ "$out" = "sync-branch: updated 3 times already, pull request is BEHIND, a person decides" ]
[ "$(origin_feat)" = "$head" ]
