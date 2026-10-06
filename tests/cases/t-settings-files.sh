#!/bin/sh
# The shared and personal settings files: read from the right place,
# limited by the trust line, commands trusted on first use, and every
# refusal reported.
set -eu

remote="$SCRATCH/remote.git"
git init --quiet --bare "$remote"
clone="$SCRATCH/clone"
git clone --quiet "$remote" "$clone" 2>/dev/null
git -C "$clone" config user.name tester
git -C "$clone" config user.email tester@example.invalid
mkdir -p "$clone/.claude"
cat >"$clone/.claude/pr-review-workflow.conf" <<'CONF'
# shared
check_command npm test -- --ci
prefixes npx vitest
double_review always
finding_filter false
cost_posture quality
samples 2
auto_approve true
standards .env
CONF
git -C "$clone" add -A
git -C "$clone" commit --quiet -m shared
git -C "$clone" push --quiet origin HEAD:main

data="$SCRATCH/data"
dir="$data/state/acme__widgets__7"
mkdir -p "$dir"
printf 'owner acme\nrepo widgets\npr 7\nbase_branch main\nrepo_root %s\n' "$clone" >"$dir/meta.txt"
resolve() { sh "$REPO_ROOT/scripts/resolve-settings.sh" "$dir"; }
value() { sed -n "s/^$1 //p" "$dir/settings.txt"; }
source_of() { sed -n "s/^$1 //p" "$dir/sources.txt"; }

# The pull request's own copy of the file on disk is never read.
printf 'cost_posture economy\n' >"$clone/.claude/pr-review-workflow.conf"

out=$(printf 'finding_filter true\n' | resolve)
printf '%s\n' "$out" | grep -qx 'settings: project file fresh, local file absent'
# Raised settings apply; a lowered one is refused.
[ "$(value double_review)" = always ] && [ "$(source_of double_review)" = project ]
[ "$(value cost_posture)" = quality ]
[ "$(value review_samples)" = 2 ]
[ "$(value finding_filter)" = true ]
printf '%s\n' "$out" | grep -qx 'settings: ignored project finding_filter: would lower true to false; a project may only raise it'
# Keys a project may never set.
[ "$(value auto_approve)" = false ]
[ -z "$(value local_standards)" ]
printf '%s\n' "$out" | grep -qx 'settings: ignored project auto_approve: only you can set this, in your own configuration or local file'
printf '%s\n' "$out" | grep -qx 'settings: ignored project local_standards: only you can set this, in your own configuration or local file'
# Commands wait for approval, and say what they are.
[ -z "$(value check_command)" ]
hash=$(printf '%s\n' "$out" | sed -n 's/^settings: trust pending \([0-9a-f]*\) check_command npm test -- --ci$/\1/p')
[ -n "$hash" ]
printf '%s\n' "$out" | grep -qx "settings: trust pending $hash contract_commands npx vitest"

# Only the pending hash can be approved; then the commands apply.
if sh "$REPO_ROOT/scripts/resolve-settings.sh" "$dir" --approve deadbeef 2>/dev/null; then
	echo "expected refusal of a hash that is not pending" >&2
	exit 1
fi
sh "$REPO_ROOT/scripts/resolve-settings.sh" "$dir" --approve "$hash" | grep -qx "resolve-settings: approved $hash for acme/widgets"
out=$(resolve </dev/null)
[ "$(value check_command)" = "npm test -- --ci" ] && [ "$(source_of check_command)" = project ]
[ "$(value contract_commands)" = "npx vitest" ]
! printf '%s\n' "$out" | grep -q 'trust pending'

# Changing the commands on the base branch asks again.
git -C "$clone" checkout --quiet -- .claude/pr-review-workflow.conf
sed -i 's/npm test -- --ci/npm test/' "$clone/.claude/pr-review-workflow.conf"
git -C "$clone" commit --quiet -am changed
git -C "$clone" push --quiet origin HEAD:main
out=$(resolve </dev/null)
[ -z "$(value check_command)" ]
printf '%s\n' "$out" | grep -q '^settings: trust pending [0-9a-f]* check_command npm test$'

# The personal file outranks the shared one and may lower or set anything.
printf 'cost_posture economy\nauto_approve yes\ncheck\n' >"$clone/.claude/pr-review-workflow.local.conf"
out=$(resolve </dev/null)
printf '%s\n' "$out" | grep -qx 'settings: project file fresh, local file present'
[ "$(value cost_posture)" = economy ] && [ "$(source_of cost_posture)" = local ]
[ "$(value auto_approve)" = true ]
grep -qx 'check_command' "$dir/settings.txt"

# Per-run overrides outrank both files.
printf 'posture balanced\n' >"$dir/overrides.txt"
resolve </dev/null >/dev/null
[ "$(value cost_posture)" = balanced ] && [ "$(source_of cost_posture)" = run ]
: >"$dir/overrides.txt"

# A personal file the repository tracks, or a symlink, is refused.
git -C "$clone" add -f .claude/pr-review-workflow.local.conf
out=$(resolve </dev/null)
printf '%s\n' "$out" | grep -qx 'settings: project file fresh, local file refused'
printf '%s\n' "$out" | grep -q 'ignored local file: the repository tracks it'
git -C "$clone" rm --quiet --cached .claude/pr-review-workflow.local.conf
mv "$clone/.claude/pr-review-workflow.local.conf" "$SCRATCH/elsewhere.conf"
ln -s "$SCRATCH/elsewhere.conf" "$clone/.claude/pr-review-workflow.local.conf"
out=$(resolve </dev/null)
printf '%s\n' "$out" | grep -q 'ignored local file: it is a symlink'
rm "$clone/.claude/pr-review-workflow.local.conf"

# A personal file in the main worktree is found from a linked worktree.
printf 'review_samples 3\n' >"$clone/.claude/pr-review-workflow.local.conf"
git -C "$clone" worktree add --quiet --detach "$SCRATCH/linked" 2>/dev/null
printf 'owner acme\nrepo widgets\npr 7\nbase_branch main\nrepo_root %s\n' "$SCRATCH/linked" >"$dir/meta.txt"
resolve </dev/null >/dev/null
[ "$(value review_samples)" = 3 ] && [ "$(source_of review_samples)" = local ]

# Offline, the last fetched base is still read; never fetched, it is unavailable.
mv "$remote" "$remote.gone"
resolve </dev/null | grep -qx 'settings: project file stale, local file present'
printf 'owner acme\nrepo widgets\npr 7\nbase_branch release\nrepo_root %s\n' "$clone" >"$dir/meta.txt"
resolve </dev/null | grep -qx 'settings: project file unavailable, local file present'

# The trust store sits outside state/, where retention never looks.
[ -f "$data/trust/acme__widgets.trusted" ]
