#!/bin/sh
# Fork pull requests: fetch and push against the fork, review-only gating.
set -eu

mkdir -p "$SCRATCH/acme"
base="$SCRATCH/acme/widgets.git"
fork="$SCRATCH/fork.git"
git init --quiet --bare "$base"
git init --quiet --bare "$fork"

clone="$SCRATCH/clone"
git clone --quiet "$base" "$clone" 2>/dev/null
git -C "$clone" config user.name tester
git -C "$clone" config user.email tester@example.invalid
printf 'one\n' >"$clone/file.txt"
git -C "$clone" add file.txt
git -C "$clone" commit --quiet -m "Root"
git -C "$clone" push --quiet origin HEAD:main

work="$SCRATCH/forkwork"
git clone --quiet "$fork" "$work" 2>/dev/null
git -C "$work" fetch --quiet "$base" main
git -C "$work" checkout --quiet -b feat-fork FETCH_HEAD
git -C "$work" config user.name author
git -C "$work" config user.email author@example.invalid
printf 'two\n' >>"$work/file.txt"
git -C "$work" commit --quiet -am "Fork change"
git -C "$work" push --quiet origin feat-fork
sha=$(git -C "$work" rev-parse HEAD)

dir="$SCRATCH/state"
mkdir -p "$dir"
meta() {
	printf 'owner acme\nrepo widgets\npr 9\nhead_branch feat-fork\nhead_sha %s\ncross_repo true\nmaintainer_can_modify %s\nhead_repo_url %s\nrepo_root %s\n' \
		"$sha" "$1" "$2" "$clone" >"$dir/meta.txt"
}

meta true "$fork"
cd "$clone"
out=$(sh "$REPO_ROOT/scripts/checkout-pr.sh" "$dir")
printf '%s\n' "$out" | grep -qx "$dir/worktree"
printf '%s\n' "$out" | grep -qx 'mode read-write'
[ "$(git -C "$dir/worktree" rev-parse HEAD)" = "$sha" ]

git -C "$dir/worktree" config user.name tester
git -C "$dir/worktree" config user.email tester@example.invalid
printf 'three\n' >>"$dir/worktree/file.txt"
git -C "$dir/worktree" commit --quiet -am "Address F001"
sh "$REPO_ROOT/scripts/push-branch.sh" "$dir" >/dev/null
new_sha=$(git -C "$dir/worktree" rev-parse HEAD)
[ "$(git -C "$fork" rev-parse refs/heads/feat-fork)" = "$new_sha" ]
[ "$(git -C "$base" rev-parse refs/heads/main)" != "$new_sha" ]

sha=$new_sha
meta false "$fork"
out=$(sh "$REPO_ROOT/scripts/checkout-pr.sh" "$dir")
printf '%s\n' "$out" | grep -qx 'mode review-only'
rc=0
sh "$REPO_ROOT/scripts/push-branch.sh" "$dir" 2>"$SCRATCH/err" || rc=$?
[ "$rc" -eq 2 ]
grep -q "does not allow maintainer edits" "$SCRATCH/err"

sh "$REPO_ROOT/scripts/cleanup-state.sh" "$dir" >/dev/null
meta true ""
rc=0
sh "$REPO_ROOT/scripts/checkout-pr.sh" "$dir" 2>"$SCRATCH/err" || rc=$?
[ "$rc" -eq 2 ]
grep -q "fork this pull request comes from is gone" "$SCRATCH/err"
