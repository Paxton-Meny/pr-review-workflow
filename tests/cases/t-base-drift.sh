#!/bin/sh
# base-drift: commits landing on the base since the review are compared
# hunk by hunk against the reviewed change, in the merge base's
# coordinates; only near or same refuses, and the overlap bundle is
# written for a person or the comparer.
set -eu

remote="$SCRATCH/remote.git"
git init --quiet --bare "$remote"
seed="$SCRATCH/seed"
git clone --quiet "$remote" "$seed" 2>/dev/null
git -C "$seed" config user.name tester
git -C "$seed" config user.email tester@example.invalid
mkdir -p "$seed/src"
{
	echo 'def alpha():'
	i=2
	while [ "$i" -le 30 ]; do
		echo "    a$i = $i"
		i=$((i + 1))
	done
	echo 'def beta():'
	i=32
	while [ "$i" -le 60 ]; do
		echo "    b$i = $i"
		i=$((i + 1))
	done
} >"$seed/src/app.py"
printf 'lock v1\n' >"$seed/package-lock.json"
printf 'intro\nbody\n' >"$seed/notes.md"
git -C "$seed" add .
git -C "$seed" commit --quiet -m base
git -C "$seed" push --quiet origin HEAD:main

# The pull request: lines 10 to 12 of alpha, and the lockfile.
git -C "$seed" checkout --quiet -b feature
sed -i 's/^    a10 = 10$/    a10 = 100/; s/^    a11 = 11$/    a11 = 110/; s/^    a12 = 12$/    a12 = 120/' "$seed/src/app.py"
printf 'lock v2\n' >"$seed/package-lock.json"
printf 'intro\nbody changed\n' >"$seed/notes.md"
git -C "$seed" commit --quiet -am feature
git -C "$seed" push --quiet origin feature
head=$(git -C "$seed" rev-parse HEAD)
git -C "$seed" checkout --quiet main

clone="$SCRATCH/clone"
git clone --quiet "$remote" "$clone" 2>/dev/null
git -C "$clone" fetch --quiet origin feature

data="$SCRATCH/data"
dir="$data/state/o__r__1"
ctx="$dir/pr-context"
mkdir -p "$ctx"
base_sha=$(git -C "$clone" rev-parse origin/main)
printf 'owner o\nrepo r\npr 1\nbase_branch main\nhead_sha %s\nrepo_root %s\nbase_sha %s\n' "$head" "$clone" "$base_sha" >"$dir/meta.txt"
refetch() {
	git -C "$clone" diff "origin/main...$(sed -n 's/^head_sha //p' "$dir/meta.txt")" >"$ctx/diff.patch"
	git -C "$clone" diff --numstat "origin/main...$(sed -n 's/^head_sha //p' "$dir/meta.txt")" | awk -F '\t' '{ printf "%s\t%s\t%s\n", $3, $1, $2 }' >"$ctx/files.txt"
	sh "$REPO_ROOT/scripts/split-diff.sh" "$dir" >/dev/null
}
refetch
: | sh "$REPO_ROOT/scripts/resolve-settings.sh" "$dir" >/dev/null
drift() { sh "$REPO_ROOT/scripts/base-drift.sh" "$dir"; }
land() {
	# land <message>: commit the seed's working tree to main and push
	git -C "$seed" commit --quiet -am "$1"
	git -C "$seed" push --quiet origin main
}

# Nothing landed.
[ "$(drift)" = "base-drift: 0 commits landed, 0 files shared, level none" ]
grep -qx 'level none files 0' "$ctx/drift.txt"
grep -qx "snapshot $base_sha" "$ctx/drift.txt"

# A commit to another file: nothing shared.
printf 'other\n' >"$seed/other.txt"
git -C "$seed" add other.txt
land other
[ "$(drift)" = "base-drift: 1 commits landed, 0 files shared, level none" ]

# Only the lockfile shared: excluded, so still nothing.
printf 'lock v3\n' >"$seed/package-lock.json"
land lock
[ "$(drift)" = "base-drift: 2 commits landed, 0 files shared, level none" ]

# A docs file shared on the same lines: set aside, since a changelog or a
# note is where every concurrent change meets.
printf 'intro changed\nbody\n' >"$seed/notes.md"
land notes
[ "$(drift)" = "base-drift: 3 commits landed, 0 files shared, 1 docs or config set aside, level none" ]
grep -qx 'level none files 0' "$ctx/drift.txt"

# A change in beta, far from alpha's lines: disjoint passes.
sed -i 's/^    b50 = 50$/    b50 = 500/' "$seed/src/app.py"
land far
[ "$(drift)" = "base-drift: 4 commits landed, 1 files shared, 1 docs or config set aside, level disjoint" ]
grep -q "^file	disjoint	src/app.py	10-12	50-50	$" "$ctx/drift.txt"
[ ! -d "$ctx/overlap" ]

# A change in alpha sixteen lines down: not within twelve, but the hunk
# header names the same function, so near, and the merge waits.
sed -i 's/^    a28 = 28$/    a28 = 280/' "$seed/src/app.py"
land near-fn
# The clone's own diff config must not change what is read.
git -C "$clone" config diff.mnemonicPrefix true
git -C "$clone" config diff.noprefix true
rc=0
out=$(drift) || rc=$?
[ "$rc" -eq 5 ]
[ "$out" = "$(printf 'base-drift: 5 commits landed, 1 files shared, 1 docs or config set aside, level near\ndrift near src/app.py ours 10-12 theirs 28-28 in def alpha():')" ]
grep -q "^file	near	src/app.py	10-12	28-28	def alpha():$" "$ctx/drift.txt"
grep -qx 'level near files 1' "$ctx/drift.txt"
grep -qx 'path: src/app.py' "$ctx/overlap/base/ours.diff"
grep -qx 'R10 +    a10 = 100' "$ctx/overlap/base/ours.diff"
grep -qx '+    a28 = 280' "$ctx/overlap/base/theirs.diff"
if grep -q 'package-lock' "$ctx/overlap/base/theirs.diff"; then echo "a lockfile must not reach the landed diff" >&2; exit 1; fi
grep -qx 'label base' "$ctx/overlap/base/summary.txt"
grep -qx 'level near files 1 near 1 same 0' "$ctx/overlap/base/summary.txt"

# A change inside the reviewed lines: same.
sed -i 's/^    a11 = 11$/    a11 = 1100/' "$seed/src/app.py"
land same
rc=0
out=$(drift) || rc=$?
[ "$rc" -eq 5 ]
printf '%s\n' "$out" | grep -qx 'base-drift: 6 commits landed, 1 files shared, 1 docs or config set aside, level same'
printf '%s\n' "$out" | grep -qx 'drift same src/app.py ours 10-12 theirs 11-11 in def alpha():'

# The branch is brought up to date with the moved base (by the author
# or by base sync): the merge base now sits past the snapshot and would
# hide everything that landed, so the comparison runs from the snapshot
# instead, approximately, and still refuses.
git -C "$seed" checkout --quiet -b feature2 main
sed -i 's/^    a10 = 10$/    a10 = 100/; s/^    a12 = 12$/    a12 = 120/' "$seed/src/app.py"
git -C "$seed" commit --quiet -am rebased
git -C "$seed" push --quiet origin feature2
head2=$(git -C "$seed" rev-parse HEAD)
git -C "$seed" checkout --quiet main
git -C "$clone" fetch --quiet origin feature2
sed -i "s/^head_sha .*/head_sha $head2/" "$dir/meta.txt"
refetch
rc=0
out=$(drift) || rc=$?
[ "$rc" -eq 5 ]
printf '%s\n' "$out" | grep -qx 'base-drift: 6 commits landed, 1 files shared, level same, approximate: the branch was brought up to date since the review'
grep -qx "landed_from $base_sha" "$ctx/drift.txt"
sed -i 's/^    a20 = 20$/    a20 = 200/' "$seed/src/app.py"
land after-rebase
rc=0
out=$(drift) || rc=$?
[ "$rc" -eq 5 ]
printf '%s\n' "$out" | grep -q '^base-drift: 7 commits landed, 1 files shared, level same, approximate'
printf '%s\n' "$out" | grep -q '^drift same src/app.py ours 10-12 theirs 11-11 in def alpha():$'

# The snapshot never changes on a resume, and off skips everything.
grep -qx "snapshot $base_sha" "$ctx/drift.txt"
printf 'overlap_check off\n' | sh "$REPO_ROOT/scripts/resolve-settings.sh" "$dir" >/dev/null
[ "$(drift)" = "base-drift: overlap check off" ]
: | sh "$REPO_ROOT/scripts/resolve-settings.sh" "$dir" >/dev/null

# A base that can no longer be fetched is read from the earlier fetch
# and says so; one never fetched cannot prove anything.
mv "$remote" "$remote.gone"
rc=0
out=$(drift) || rc=$?
[ "$rc" -eq 5 ]
printf '%s\n' "$out" | grep -q 'level same, approximate: the branch was brought up to date since the review, base read from an earlier fetch$'
# A stale read that shows nothing close is refused too, since a failed
# fetch cannot show that the base did not move.
cp "$ctx/files.txt" "$SCRATCH/files.keep"
printf 'unrelated.txt\t1\t0\n' >"$ctx/files.txt"
rc=0
out=$(drift) || rc=$?
[ "$rc" -eq 5 ]
printf '%s\n' "$out" | grep -q 'level none, approximate: the branch was brought up to date since the review, base read from an earlier fetch$'
cp "$SCRATCH/files.keep" "$ctx/files.txt"
git -C "$clone" update-ref -d refs/remotes/origin/main
rc=0
out=$(drift) || rc=$?
[ "$rc" -eq 5 ]
[ "$out" = "base-drift: base main unreadable, so nothing landed there can be ruled out" ]
mv "$remote.gone" "$remote"

# A ledger that never checked out has no clone to read.
printf 'owner o\nrepo r\npr 2\nbase_branch main\nhead_sha %s\n' "$head" >"$data/state/o__r__2.meta"
mkdir -p "$data/state/o__r__2/pr-context"
mv "$data/state/o__r__2.meta" "$data/state/o__r__2/meta.txt"
cp "$ctx/diff.patch" "$ctx/files.txt" "$data/state/o__r__2/pr-context/"
: | sh "$REPO_ROOT/scripts/resolve-settings.sh" "$data/state/o__r__2" >/dev/null
if sh "$REPO_ROOT/scripts/base-drift.sh" "$data/state/o__r__2" 2>"$SCRATCH/err"; then
	echo "expected failure without a clone" >&2
	exit 1
fi
grep -q "names no clone" "$SCRATCH/err"
