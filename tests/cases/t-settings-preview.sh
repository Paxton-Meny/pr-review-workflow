#!/bin/sh
# resolve-settings --preview: resolves for the clone it runs in, against
# origin/HEAD as last fetched, fetching and writing nothing.
set -eu

remote="$SCRATCH/remote.git"
git init --quiet --bare "$remote"
clone="$SCRATCH/clone"
git clone --quiet "$remote" "$clone" 2>/dev/null
git -C "$clone" config user.name tester
git -C "$clone" config user.email tester@example.invalid
mkdir -p "$clone/.claude"
printf 'double_review always\ncheck_command make check\n' >"$clone/.claude/pr-review-workflow.conf"
git -C "$clone" add -A
git -C "$clone" commit --quiet -m shared
git -C "$clone" push --quiet origin HEAD:main
git -C "$clone" remote set-url origin https://github.com/Paxton-Meny/widgets.git
git -C "$clone" update-ref refs/remotes/origin/main HEAD
git -C "$clone" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
printf 'cost_posture economy\n' >"$clone/.claude/pr-review-workflow.local.conf"

data="$SCRATCH/data"
cd "$clone"
out=$(printf 'review_samples 2\n' | sh "$REPO_ROOT/scripts/resolve-settings.sh" --preview "$data")
printf '%s\n' "$out" | grep -qx 'settings: project file as-of-last-fetch, local file present'
printf '%s\n' "$out" | grep -qx 'settings: double_review always from project'
printf '%s\n' "$out" | grep -qx 'settings: cost_posture economy from local'
printf '%s\n' "$out" | grep -qx 'settings: review_samples 2 from user'
printf '%s\n' "$out" | grep -qx 'settings: check_command (empty) from default'
printf '%s\n' "$out" | grep -q '^settings: trust pending [0-9a-f]* check_command make check$'

# Nothing was written: no state, no pending approval, no run hash.
[ ! -e "$data" ]
! printf '%s\n' "$out" | grep -q 'unsubstituted'

# --save keeps the same lines in the survey directory, and only there.
mkdir -p "$SCRATCH/sv"
if printf 'review_samples 2\n' | sh "$REPO_ROOT/scripts/resolve-settings.sh" --preview "$data" --save "$SCRATCH/sv" 2>/dev/null; then
	echo "expected refusal of a survey directory without meta.txt" >&2
	exit 1
fi
printf 'owner Paxton-Meny\n' >"$SCRATCH/sv/meta.txt"
saved=$(printf 'review_samples 2\n' | sh "$REPO_ROOT/scripts/resolve-settings.sh" --preview "$data" --save "$SCRATCH/sv")
[ "$saved" = "$out" ]
[ "$saved" = "$(cat "$SCRATCH/sv/preview.txt")" ]
[ "$(ls -A "$SCRATCH/sv" | tr '\n' ' ')" = 'meta.txt preview.txt ' ]
[ ! -e "$data" ]

# With origin/HEAD unset, origin/main stands in as the base; with neither,
# the shared file is unavailable, not an error.
git -C "$clone" symbolic-ref --delete refs/remotes/origin/HEAD
out=$(sh "$REPO_ROOT/scripts/resolve-settings.sh" --preview "$data" </dev/null)
printf '%s\n' "$out" | grep -qx 'settings: project file as-of-last-fetch, local file present'
git -C "$clone" update-ref -d refs/remotes/origin/main
out=$(sh "$REPO_ROOT/scripts/resolve-settings.sh" --preview "$data" </dev/null)
printf '%s\n' "$out" | grep -qx 'settings: project file absent, local file present'
