#!/bin/sh
# An editor batch that commits in the user's checkout fails loudly at every step.
set -eu

. "$REPO_ROOT/tests/fixture-identity.sh"
s="$REPO_ROOT/scripts"
stub="$SCRATCH/stub"
mkdir -p "$stub"
export GH_STUB_DIR="$stub"
export PATH="$REPO_ROOT/tests/stubs:$PATH"

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
head=$(git -C "$clone" rev-parse HEAD)

dir="$SCRATCH/state"
mkdir -p "$dir"
printf '1\n' >"$dir/round.txt"
printf 'owner %s\nrepo widgets\npr 7\nhead_branch feat-thing\nhead_sha %s\ncross_repo false\n' "$fixture_owner" "$head" >"$dir/meta.txt"
printf '=== finding\ncategory: correctness\nseverity: minor\npath: file.txt\nline: 2\nside: RIGHT\ntitle: Thing\n---\nFix: add a line.\nResolution: file.txt has three lines.\n' |
	sh "$s/save-findings.sh" "$dir" >/dev/null
sh "$s/update-finding.sh" "$dir" F001 comment_id=9001 placement=inline >/dev/null
replies="$stub/api-repos_${fixture_owner}_widgets_pulls_7_comments_9001_replies"
printf '5555\n' >"$replies"

cd "$clone"
wt=$(sh "$s/checkout-pr.sh" "$dir" | head -n 1)

refused() {
	# refused <exit code> <message part> <command...>: the command exits so and says so
	want=$1 says=$2
	shift 2
	rc=0
	"$@" >/dev/null 2>"$SCRATCH/err" || rc=$?
	[ "$rc" -eq "$want" ] || {
		echo "expected exit $want from: $*, got $rc" >&2
		cat "$SCRATCH/err" >&2
		exit 1
	}
	grep -q -- "$says" "$SCRATCH/err" || {
		echo "expected \"$says\" from: $*" >&2
		cat "$SCRATCH/err" >&2
		exit 1
	}
}

sh "$s/checkout-guard.sh" "$dir" before >/dev/null
printf 'three\n' >>"$clone/file.txt"
git -C "$clone" commit --quiet -am "Add the third line"
stray=$(git -C "$clone" rev-parse --short HEAD)

refused 3 "nothing to push" sh "$s/push-branch.sh" "$dir"
[ "$(git -C "$remote" rev-parse refs/heads/feat-thing)" = "$head" ]
grep -qx "head_sha $head" "$dir/meta.txt"

refused 1 "not in the review worktree" sh "$s/update-finding.sh" "$dir" F001 status=addressed "commit=$stray"
grep -qx 'status: open' "$dir/findings/F001"
grep -qx 'commit:' "$dir/findings/F001"

refused 1 "is open, not addressed" sh "$s/reply-thread.sh" "$dir" --addressed F001
refused 1 "use --addressed" sh -c "printf 'Addressed in $stray.\n' | sh '$s/reply-thread.sh' '$dir' 9001"
[ ! -f "$stub/calls.log" ]

refused 3 "now head $(git -C "$clone" rev-parse HEAD)" sh "$s/checkout-guard.sh" "$dir" after
grep -q "changed during the editor batch" "$SCRATCH/err"
grep -qx "checkout-guard: was branch refs/heads/feat-thing $head" "$SCRATCH/err"
[ "$(grep -c '^escape$' "$dir/escapes.txt")" -eq 1 ]

git -C "$clone" reset --quiet --hard "$head"
sh "$s/checkout-guard.sh" "$dir" before >/dev/null
printf 'stray\n' >>"$clone/file.txt"
refused 3 "now status  M file.txt" sh "$s/checkout-guard.sh" "$dir" after
sh "$s/checkout-guard.sh" "$dir" before >/dev/null
printf 'more\n' >>"$clone/file.txt"
refused 3 "now diff " sh "$s/checkout-guard.sh" "$dir" after
git -C "$clone" checkout --quiet -- file.txt
printf 'note\n' >"$clone/notes.txt"
sh "$s/checkout-guard.sh" "$dir" before >/dev/null
printf 'edit\n' >>"$clone/notes.txt"
refused 3 "now untracked " sh "$s/checkout-guard.sh" "$dir" after
rm "$clone/notes.txt"
[ "$(grep -c '^escape$' "$dir/escapes.txt")" -eq 4 ]

git -C "$clone" worktree add --quiet -b other "$SCRATCH/other"
sh "$s/checkout-guard.sh" "$dir" before >/dev/null
printf 'elsewhere\n' >>"$SCRATCH/other/file.txt"
git -C "$SCRATCH/other" commit --quiet -am "Work in another worktree"
sh "$s/checkout-guard.sh" "$dir" after | grep -qx 'checkout-guard: the user checkout is unchanged'
git -C "$clone" branch --quiet loose "$head"
sh "$s/checkout-guard.sh" "$dir" before >/dev/null
git -C "$clone" branch --quiet -f loose "$(git -C "$SCRATCH/other" rev-parse HEAD)"
refused 3 "now branch refs/heads/loose " sh "$s/checkout-guard.sh" "$dir" after
git -C "$clone" worktree remove --force "$SCRATCH/other"
git -C "$clone" branch --quiet -D other loose
[ "$(grep -c '^escape$' "$dir/escapes.txt")" -eq 5 ]

sh "$s/checkout-guard.sh" "$dir" before >/dev/null
printf 'three\n' >>"$wt/file.txt"
git -C "$wt" -c "user.name=$fixture_name" -c "user.email=$fixture_email" commit --quiet -am "Add the third line"
fix=$(git -C "$wt" rev-parse --short HEAD)
sh "$s/checkout-guard.sh" "$dir" after | grep -qx 'checkout-guard: the user checkout is unchanged'

sh "$s/update-finding.sh" "$dir" F001 status=addressed "commit=$fix" >/dev/null
grep -qx "commit: $fix" "$dir/findings/F001"
refused 1 "not on the pushed head" sh "$s/reply-thread.sh" "$dir" --addressed F001
[ ! -f "$stub/calls.log" ]
sh "$s/push-branch.sh" "$dir" | grep -q "^push-branch: feat-thing at "
sh "$s/reply-thread.sh" "$dir" --addressed F001 | grep -qx 'reply-thread: replied to 9001 as 5555'
grep -qx "Addressed in $fix (Add the third line)." "$stub/bodies.log"
refused 3 "nothing to push" sh "$s/push-branch.sh" "$dir"

pushed=$(git -C "$wt" rev-parse HEAD)
git -C "$wt" reset --quiet --hard "$head"
printf 'other\n' >>"$wt/file.txt"
git -C "$wt" -c "user.name=$fixture_name" -c "user.email=$fixture_email" commit --quiet -am "Change it another way"
refused 3 "F001 records commit $fix" sh "$s/push-branch.sh" "$dir"
[ "$(git -C "$remote" rev-parse refs/heads/feat-thing)" = "$pushed" ]

skill="$REPO_ROOT/skills/review-pr/SKILL.md"
grep -qx '  - Bash(sh ${CLAUDE_PLUGIN_ROOT}/scripts/checkout-guard.sh \*)' "$skill"
grep -A2 'Every `pr-review-workflow:editor` spawn below sits between two calls' "$skill" |
	grep -q 'checkout-guard.sh <dir> before'
grep -A4 'Every `pr-review-workflow:editor` spawn below sits between two calls' "$skill" |
	grep -q 'checkout-guard.sh <dir> after'
grep -q 'reply-thread.sh <state-dir> --addressed <id>' "$REPO_ROOT/agents/editor.md"
grep -q '^`<state-dir>/worktree`, written `<worktree>` below' "$REPO_ROOT/agents/editor.md"
grep -q '^there with its reason in your own words, carrying no filesystem path\.$' "$REPO_ROOT/agents/editor.md"
grep -q '^  name the script and its reason instead, carrying no filesystem path\.$' "$REPO_ROOT/agents/editor.md"
