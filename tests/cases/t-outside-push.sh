#!/bin/sh
# checkout-pr follows a push made outside the run, or refuses one it cannot follow.
set -eu

. "$REPO_ROOT/tests/fixture-identity.sh"
remote="$SCRATCH/$fixture_owner/widgets.git"
mkdir -p "$SCRATCH/$fixture_owner"
git init --quiet --bare "$remote"

clone="$SCRATCH/clone"
git clone --quiet "$remote" "$clone" 2>/dev/null
git -C "$clone" config user.name "$fixture_name"
git -C "$clone" config user.email "$fixture_email"
printf 'one\n' >"$clone/file.txt"
git -C "$clone" add file.txt
git -C "$clone" commit --quiet -m "Root"
git -C "$clone" push --quiet origin HEAD:main
git -C "$clone" checkout --quiet -b feat-thing
printf 'two\n' >>"$clone/file.txt"
git -C "$clone" commit --quiet -am "Change"
git -C "$clone" push --quiet origin feat-thing
reviewed=$(git -C "$clone" rev-parse HEAD)
git -C "$clone" checkout --quiet main

author="$SCRATCH/author"
git clone --quiet --branch feat-thing "$remote" "$author" 2>/dev/null
git -C "$author" config user.name "$fixture_name"
git -C "$author" config user.email "$fixture_email"

dir="$SCRATCH/state"
mkdir -p "$dir"
printf 'owner %s\nrepo widgets\npr 7\nhead_branch feat-thing\nhead_sha %s\ncross_repo false\n' "$fixture_owner" "$reviewed" >"$dir/meta.txt"
cd "$clone"
wt=$(sh "$REPO_ROOT/scripts/checkout-pr.sh" "$dir" | head -n 1)
[ "$(git -C "$wt" rev-parse HEAD)" = "$reviewed" ]

# Someone else pushes two commits: the run moves to them and names both heads.
printf 'new\n' >"$author/added.txt"
git -C "$author" add added.txt
git -C "$author" commit --quiet -m "Add a file"
printf 'three\n' >>"$author/file.txt"
git -C "$author" commit --quiet -am "Change again"
git -C "$author" push --quiet origin feat-thing
outside=$(git -C "$author" rev-parse HEAD)
rc=0
sh "$REPO_ROOT/scripts/checkout-pr.sh" "$dir" >"$SCRATCH/out" 2>"$SCRATCH/err" || rc=$?
[ "$rc" -eq 3 ] || { cat "$SCRATCH/out" "$SCRATCH/err" >&2; exit 1; }
[ "$(head -n 1 "$SCRATCH/out")" = "$wt" ]
grep -qx "checkout-pr: advanced $reviewed $outside" "$SCRATCH/out"
[ "$(git -C "$wt" rev-parse HEAD)" = "$outside" ]
grep -qx "head_sha $outside" "$dir/meta.txt"
grep -qx "prev_head $reviewed" "$dir/meta.txt"
[ "$(grep -c '^head_sha ' "$dir/meta.txt")" -eq 1 ]

# The commits that arrived are listed for review, every file they touched.
rc=0
sh "$REPO_ROOT/scripts/round-diff.sh" "$dir" --all >"$SCRATCH/out" || rc=$?
[ "$rc" -eq 3 ]
printf 'unexpected added.txt\nunexpected file.txt\n' | cmp -s - "$SCRATCH/out"

# Once followed, a second call changes nothing.
sh "$REPO_ROOT/scripts/checkout-pr.sh" "$dir" >"$SCRATCH/out"
! grep -q advanced "$SCRATCH/out"
grep -qx "prev_head $reviewed" "$dir/meta.txt"

# A held run has no worktree: it is created at the commits that arrived.
sh "$REPO_ROOT/scripts/cleanup-state.sh" "$dir" >/dev/null
printf 'four\n' >>"$author/file.txt"
git -C "$author" commit --quiet -am "Change while held"
git -C "$author" push --quiet origin feat-thing
held=$(git -C "$author" rev-parse HEAD)
rc=0
sh "$REPO_ROOT/scripts/checkout-pr.sh" "$dir" >"$SCRATCH/out" || rc=$?
[ "$rc" -eq 3 ]
grep -qx "checkout-pr: advanced $outside $held" "$SCRATCH/out"
[ "$(git -C "$wt" rev-parse HEAD)" = "$held" ]
grep -qx "prev_head $outside" "$dir/meta.txt"

cp "$dir/meta.txt" "$SCRATCH/meta.before"
refused() {
	rc=0
	sh "$REPO_ROOT/scripts/checkout-pr.sh" "$dir" >/dev/null 2>"$SCRATCH/err" || rc=$?
	[ "$rc" -eq 4 ] || { echo "expected exit 4, got $rc" >&2; cat "$SCRATCH/err" >&2; exit 1; }
	grep -q "$1" "$SCRATCH/err" || { cat "$SCRATCH/err" >&2; exit 1; }
	cmp -s "$dir/meta.txt" "$SCRATCH/meta.before"
	[ "$(git -C "$wt" rev-parse HEAD)" = "$2" ]
}

# The branch went back past the head the ledger holds.
git -C "$author" push --quiet --force origin "$outside:refs/heads/feat-thing"
refused "is at $outside, behind $held" "$held"

# The branch was rewritten: the ledger's head is not in its history.
git -C "$author" reset --quiet --hard "$outside"
printf 'rewritten\n' >>"$author/file.txt"
git -C "$author" commit --quiet -am "Rewrite"
git -C "$author" push --quiet --force origin feat-thing
refused "has diverged from $held" "$held"

# The worktree holds commits nobody pushed while others pushed theirs.
git -C "$author" push --quiet --force origin "$held:refs/heads/feat-thing"
git -C "$wt" config user.name "$fixture_name"
git -C "$wt" config user.email "$fixture_email"
printf 'local\n' >>"$wt/file.txt"
git -C "$wt" commit --quiet -am "Address F001"
local_head=$(git -C "$wt" rev-parse HEAD)
git -C "$author" reset --quiet --hard "$held"
printf 'theirs\n' >"$author/theirs.txt"
git -C "$author" add theirs.txt
git -C "$author" commit --quiet -m "Push over the run"
git -C "$author" push --quiet origin feat-thing
refused "worktree at $local_head has diverged" "$local_head"
