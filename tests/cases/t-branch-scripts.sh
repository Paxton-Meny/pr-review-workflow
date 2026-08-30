#!/bin/sh
# checkout-pr, push-branch, cleanup-state against a local bare remote.
set -eu

remote="$SCRATCH/remote.git"
git init --quiet --bare "$remote"
clone="$SCRATCH/clone"
git clone --quiet "$remote" "$clone" 2>/dev/null
git -C "$clone" config user.name tester
git -C "$clone" config user.email tester@example.invalid
printf 'one\n' >"$clone/file.txt"
git -C "$clone" add file.txt
git -C "$clone" commit --quiet -m "Root"
git -C "$clone" push --quiet origin HEAD:main
git -C "$clone" checkout --quiet -b feat-thing
printf 'two\n' >>"$clone/file.txt"
git -C "$clone" commit --quiet -am "Change"
git -C "$clone" push --quiet origin feat-thing
sha=$(git -C "$clone" rev-parse HEAD)
git -C "$clone" checkout --quiet main

dir="$SCRATCH/state"
mkdir -p "$dir"
printf 'owner acme\nrepo widgets\npr 7\nhead_branch feat-thing\nhead_sha %s\ncross_repo false\n' "$sha" >"$dir/meta.txt"

cd "$clone"
git remote set-url origin "$remote"
if sh "$REPO_ROOT/scripts/checkout-pr.sh" "$dir" 2>"$SCRATCH/err"; then
	echo "expected refusal when origin does not match owner/repo" >&2
	exit 1
fi
grep -q "not acme/widgets" "$SCRATCH/err"

git remote set-url origin "$SCRATCH/acme/widgets.git"
mv "$remote" "$SCRATCH/widgets.git"
mkdir -p "$SCRATCH/acme"
mv "$SCRATCH/widgets.git" "$SCRATCH/acme/widgets.git"

wt=$(sh "$REPO_ROOT/scripts/checkout-pr.sh" "$dir")
[ "$wt" = "$dir/worktree" ]
[ "$(git -C "$wt" rev-parse HEAD)" = "$sha" ]
grep -q "^repo_root $clone\$" "$dir/meta.txt"

wt2=$(sh "$REPO_ROOT/scripts/checkout-pr.sh" "$dir")
[ "$wt2" = "$wt" ]

git -C "$wt" config user.name tester
git -C "$wt" config user.email tester@example.invalid
printf 'three\n' >>"$wt/file.txt"
git -C "$wt" commit --quiet -am "Address F001"
sh "$REPO_ROOT/scripts/push-branch.sh" "$dir" | grep -q "^push-branch: feat-thing at "
new_sha=$(git -C "$wt" rev-parse HEAD)
[ "$(git -C "$SCRATCH/acme/widgets.git" rev-parse refs/heads/feat-thing)" = "$new_sha" ]
grep -qx "head_sha $new_sha" "$dir/meta.txt"

sh "$REPO_ROOT/scripts/cleanup-state.sh" "$dir" | grep -q "ledger kept"
[ ! -d "$dir/worktree" ]
[ -f "$dir/meta.txt" ]
git -C "$clone" worktree list | grep -qv "$dir/worktree"

printf 'owner acme\nrepo widgets\npr 8\nhead_branch other\nhead_sha abc\ncross_repo true\n' >"$dir/meta.txt"
rc=0
sh "$REPO_ROOT/scripts/checkout-pr.sh" "$dir" 2>"$SCRATCH/err" || rc=$?
[ "$rc" -eq 2 ]
grep -q "fork pull requests" "$SCRATCH/err"
