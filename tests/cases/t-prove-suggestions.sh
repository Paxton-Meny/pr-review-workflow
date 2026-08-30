#!/bin/sh
# prove-suggestions: proves an applying fence, withdraws failing or invalid ones.
set -eu

remote="$SCRATCH/acme/widgets.git"
mkdir -p "$SCRATCH/acme"
git init --quiet --bare "$remote"
clone="$SCRATCH/clone"
git clone --quiet "$remote" "$clone" 2>/dev/null
git -C "$clone" config user.name tester
git -C "$clone" config user.email tester@example.invalid
printf 'alpha\nbravo\ncharlie\n' >"$clone/file.txt"
git -C "$clone" add file.txt
git -C "$clone" commit --quiet -m "Root"
git -C "$clone" push --quiet origin HEAD:main
sha=$(git -C "$clone" rev-parse HEAD)

dir="$SCRATCH/state"
mkdir -p "$dir"
printf '0\n' >"$dir/round.txt"
printf 'owner acme\nrepo widgets\npr 7\nhead_branch main\nhead_sha %s\ncross_repo false\nrepo_root %s\n' "$sha" "$clone" >"$dir/meta.txt"
git -C "$clone" worktree add --quiet --detach "$dir/worktree" "$sha"

sh "$REPO_ROOT/scripts/save-findings.sh" "$dir" >/dev/null <<'REC'
=== finding
category: correctness
severity: minor
path: file.txt
line: 2
side: RIGHT
title: Wrong word
---
Should be delta.
```suggestion
delta
```
=== finding
category: correctness
severity: minor
path: file.txt
line: 2
side: LEFT
title: Deleted line suggestion
---
Invalid by construction.
```suggestion
echo
```
=== finding
category: correctness
severity: minor
path: file.txt
line: 99
side: RIGHT
title: Out of range
---
Beyond the file.
```suggestion
zulu
```
REC

out=$(sh "$REPO_ROOT/scripts/prove-suggestions.sh" "$dir" "grep -q delta file.txt")
[ "$out" = "prove-suggestions: 1 proven, 2 withdrawn" ]
grep -q '^```suggestion$' "$dir/findings/F001"
if grep -q '^```suggestion$' "$dir/findings/F002"; then
	echo "left-side suggestion must be withdrawn" >&2
	exit 1
fi
grep -q 'cannot replace deleted lines' "$dir/findings/F002"
grep -q 'does not exist at the pull request head' "$dir/findings/F003"
grep -qx 'alpha' "$dir/worktree/file.txt"
[ ! -d "$dir/.prove" ]

out=$(sh "$REPO_ROOT/scripts/prove-suggestions.sh" "$dir" "grep -q nothere file.txt")
[ "$out" = "prove-suggestions: 0 proven, 1 withdrawn" ]
grep -q 'check command failed' "$dir/findings/F001"

printf 'no-newline' >"$dir/worktree/tail.txt"
git -C "$dir/worktree" add tail.txt
git -C "$dir/worktree" -c user.name=tester -c user.email=tester@example.invalid commit --quiet -m "Tail"
tail_sha=$(git -C "$dir/worktree" rev-parse HEAD)
sed "s/^head_sha .*/head_sha $tail_sha/" "$dir/meta.txt" >"$dir/meta.txt.new"
mv "$dir/meta.txt.new" "$dir/meta.txt"
sh "$REPO_ROOT/scripts/save-findings.sh" "$dir" >/dev/null <<'REC'
=== finding
category: correctness
severity: nit
path: tail.txt
line: 1
side: RIGHT
title: Last line without newline
---
Rename it.
```suggestion
renamed
```
REC
out=$(sh "$REPO_ROOT/scripts/prove-suggestions.sh" "$dir")
[ "$out" = "prove-suggestions: 1 proven, 0 withdrawn" ]
