#!/bin/sh
# pre-push: blocks main, allows branches and tags.
set -eu

remote="$SCRATCH/remote.git"
git init --quiet --bare "$remote"
clone="$SCRATCH/clone"
git clone --quiet "$remote" "$clone" 2>/dev/null
git -C "$clone" config user.name tester
git -C "$clone" config user.email tester@example.invalid
git -C "$clone" config core.hooksPath "$REPO_ROOT/.githooks"
printf 'one\n' >"$clone/file.txt"
git -C "$clone" add file.txt
git -C "$clone" -c core.hooksPath=/dev/null commit --quiet -m "Root"

if git -C "$clone" push --quiet origin HEAD:main 2>"$SCRATCH/err"; then
	echo "expected the push to main to be refused" >&2
	exit 1
fi
grep -q "refusing direct push to main" "$SCRATCH/err"

git -C "$clone" push --quiet origin HEAD:feat/allowed 2>"$SCRATCH/err"
git -C "$clone" tag -a v9.9.9 -m "Tag"
git -C "$clone" push --quiet origin v9.9.9 2>"$SCRATCH/err"
