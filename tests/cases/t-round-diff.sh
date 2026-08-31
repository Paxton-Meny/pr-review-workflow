#!/bin/sh
# round-diff: clean when only finding paths changed, exit 3 otherwise.
set -eu

repo="$SCRATCH/repo"
git init --quiet "$repo"
git -C "$repo" config user.name tester
git -C "$repo" config user.email tester@example.invalid
mkdir -p "$repo/src"
printf 'a\n' >"$repo/src/named.txt"
printf 'b\n' >"$repo/src/other.txt"
git -C "$repo" add -A
git -C "$repo" commit --quiet -m "Root"
base=$(git -C "$repo" rev-parse HEAD)

dir="$SCRATCH/state"
mkdir -p "$dir/findings"
ln -s "$repo" "$dir/worktree"
printf 'id: F001\nstatus: addressed\npath: src/named.txt\n---\nBody.\n' >"$dir/findings/F001"

printf 'owner acme\nrepo widgets\npr 7\nhead_sha %s\n' "$base" >"$dir/meta.txt"
sh "$REPO_ROOT/scripts/round-diff.sh" "$dir" | grep -qx 'round-diff: no push recorded yet'

printf 'c\n' >>"$repo/src/named.txt"
git -C "$repo" commit --quiet -am "Address F001"
head1=$(git -C "$repo" rev-parse HEAD)
printf 'owner acme\nrepo widgets\npr 7\nhead_sha %s\nprev_head %s\n' "$head1" "$base" >"$dir/meta.txt"
sh "$REPO_ROOT/scripts/round-diff.sh" "$dir" | grep -qx 'round-diff: clean'

printf 'd\n' >>"$repo/src/other.txt"
git -C "$repo" commit --quiet -am "Drive-by change"
head2=$(git -C "$repo" rev-parse HEAD)
printf 'owner acme\nrepo widgets\npr 7\nhead_sha %s\nprev_head %s\n' "$head2" "$base" >"$dir/meta.txt"
rc=0
out=$(sh "$REPO_ROOT/scripts/round-diff.sh" "$dir") || rc=$?
[ "$rc" -eq 3 ]
printf '%s\n' "$out" | grep -qx 'unexpected src/other.txt'
printf '%s\n' "$out" | grep -cx 'unexpected src/named.txt' | grep -qx 0
