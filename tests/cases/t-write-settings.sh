#!/bin/sh
# write-settings: linted before anything is written, placed atomically
# under the audience's path, replaced only on request, refused where
# the audience and git disagree, and excluded from git when it is yours.
set -eu

remote="$SCRATCH/remote.git"
git init --quiet --bare "$remote"
clone="$SCRATCH/clone"
git clone --quiet "$remote" "$clone" 2>/dev/null
git -C "$clone" config user.name tester
git -C "$clone" config user.email tester@example.invalid
printf 'readme\n' >"$clone/README.md"
git -C "$clone" add -A
git -C "$clone" commit --quiet -m root
git -C "$clone" push --quiet origin HEAD:main
shared=.claude/pr-review-workflow.conf
local=.claude/pr-review-workflow.local.conf
write() { sh "$REPO_ROOT/scripts/write-settings.sh" "$@"; }

cd "$clone"
# A refused lint writes nothing.
if printf 'auto_approve true\ncheck_command make check\n' | write shared >"$SCRATCH/out" 2>&1; then
	echo "a shared file setting auto_approve must be refused" >&2
	exit 1
fi
grep -q 'ignored project auto_approve' "$SCRATCH/out"
grep -q 'write-settings: refused' "$SCRATCH/out"
[ ! -e "$clone/.claude" ]

# Nothing to write is refused too.
if printf '# only a comment\n\n' | write shared 2>/dev/null; then
	echo "a file without settings must be refused" >&2
	exit 1
fi

# The shared file lands, with the lint's lines and what to do next.
out=$(printf '# profile: careful\ncheck_command make check\ndouble_review always\n' | write shared)
printf '%s\n' "$out" | grep -q '^settings: trust pending [0-9a-f]* check_command make check$'
printf '%s\n' "$out" | grep -qx 'settings: lint shared file 1 set, 0 refused'
printf '%s\n' "$out" | grep -qx "write-settings: wrote $shared as the shared file, 2 settings"
printf '%s\n' "$out" | grep -qx "write-settings: next: commit and push $shared; each teammate approves its commands once, on their first review"
[ "$(cat "$clone/$shared")" = "$(printf '# profile: careful\ncheck_command make check\ndouble_review always')" ]
! git -C "$clone" check-ignore -q "$shared"
[ "$(ls -A "$(dirname -- "$clone/$shared")")" = "$(basename -- "$shared")" ]

# An existing file is kept unless --replace is passed.
if printf 'double_review off\n' | write shared 2>/dev/null; then
	echo "an existing file must not be overwritten without --replace" >&2
	exit 1
fi
grep -qx 'double_review always' "$clone/$shared"
printf 'double_review always\nreview_samples 2\n' | write shared --replace >/dev/null
grep -qx 'review_samples 2' "$clone/$shared"

# Once the team tracks the project file, it cannot be written as yours.
git -C "$clone" add "$shared"
git -C "$clone" commit --quiet -m shared
if printf 'cost_posture economy\n' | write personal --replace 2>"$SCRATCH/err"; then
	echo "a tracked project file must not be written as personal" >&2
	exit 1
fi
grep -q 'the repository tracks' "$SCRATCH/err"

# The local file is yours: written, then hidden from git.
out=$(printf 'cost_posture economy\nauto_approve true\n' | write local)
printf '%s\n' "$out" | grep -qx 'settings: lint personal file 2 set, 0 refused'
printf '%s\n' "$out" | grep -qx "write-settings: excluded $local through git's info/exclude"
printf '%s\n' "$out" | grep -qx "write-settings: wrote $local as the local file, 2 settings"
printf '%s\n' "$out" | grep -qx 'write-settings: next: nothing; the file is yours and git ignores it'
git -C "$clone" check-ignore -q "$local"
[ -z "$(git -C "$clone" status --porcelain)" ]
# Writing it again adds no second exclude line.
printf 'cost_posture quality\n' | write local --replace | grep -qx "write-settings: wrote $local as the local file, 1 settings"
[ "$(grep -cx "$local" "$clone/.git/info/exclude")" -eq 1 ]

# A symlink at the target is never written through.
rm "$clone/$local"
ln -s "$SCRATCH/elsewhere" "$clone/$local"
if printf 'cost_posture quality\n' | write local --replace 2>/dev/null; then
	echo "a symlink must be refused" >&2
	exit 1
fi
rm "$clone/$local"

# A repository that ignores the project file's path cannot hold a shared file.
other_remote="$SCRATCH/other.git"
git init --quiet --bare "$other_remote"
other="$SCRATCH/other"
git clone --quiet "$other_remote" "$other" 2>/dev/null
git -C "$other" config user.name tester
git -C "$other" config user.email tester@example.invalid
printf '%s\n' "$shared" >"$other/.gitignore"
git -C "$other" add -A
git -C "$other" commit --quiet -m root
cd "$other"
if printf 'double_review always\n' | write shared 2>"$SCRATCH/err"; then
	echo "an ignored path must not take a shared file" >&2
	exit 1
fi
grep -q 'the repository ignores' "$SCRATCH/err"
[ ! -e "$other/.claude" ]
# The same path works as the user's own, already ignored, so nothing is added.
out=$(printf 'double_review always\n' | write personal)
printf '%s\n' "$out" | grep -qx "write-settings: wrote $shared as the personal file, 1 settings"
! printf '%s\n' "$out" | grep -q excluded
[ ! -e "$other/.git/info/exclude" ] || ! grep -q "$shared" "$other/.git/info/exclude"

# Bad arguments and a missing clone refuse before reading stdin.
if printf 'x\n' | write team 2>/dev/null; then
	echo "expected refusal of an unknown audience" >&2
	exit 1
fi
if printf 'x\n' | write shared --force 2>/dev/null; then
	echo "expected refusal of an unknown flag" >&2
	exit 1
fi
cd "$SCRATCH"
if printf 'double_review always\n' | write shared 2>/dev/null; then
	echo "expected refusal outside a clone" >&2
	exit 1
fi
