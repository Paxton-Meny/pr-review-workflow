#!/bin/sh
# merge-method: the setting, the one allowed method, the history of
# merged pull requests classified by their merge commits, the shape
# rule, an undecided record for a person, --set, and reuse.
set -eu

stub="$SCRATCH/stub"
mkdir -p "$stub"
export GH_STUB_DIR="$stub"
export PATH="$REPO_ROOT/tests/stubs:$PATH"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

# A clone whose main holds one merge of each shape: a merge commit, a
# squash with the "(#n)" subject, a rebase of a two-commit branch, and
# two single-commit branches kept as they were.
clone="$SCRATCH/clone"
git init -q -b main "$clone"
g() { git -C "$clone" "$@"; }
printf 'base\n' >"$clone/a.txt"
g add a.txt && g commit -q -m "Start"
branch() {
	# branch <name> <subject>...: one commit per subject on a branch off main
	name=$1
	shift
	g checkout -q -b "$name" main
	for subject in "$@"; do
		printf '%s\n' "$subject" >>"$clone/$name.txt"
		g add "$name.txt" && g commit -q -m "$subject"
	done
	g checkout -q main
}
branch b1 "Add one"
g merge -q --no-ff -m "Merge pull request #1 from o/b1" b1
m1=$(g rev-parse HEAD)
branch b2 "Add two" "Fix two"
g merge -q --squash b2 >/dev/null && g commit -q -m "Add two (#2)"
m2=$(g rev-parse HEAD)
branch b3 "Add three" "Fix three"
g rebase -q b3 main 2>/dev/null || g rebase -q main b3 >/dev/null
g checkout -q main && g merge -q --ff-only b3
m3=$(g rev-parse HEAD)
branch b4 "Add four"
g merge -q --ff-only b4
m4=$(g rev-parse HEAD)
branch b5 "Add five"
g merge -q --ff-only b5
m5=$(g rev-parse HEAD)
branch b6 "Add six" "Fix six"
g merge -q --squash b6 >/dev/null && g commit -q -m "Add six"
m6=$(g rev-parse HEAD)

dir="$SCRATCH/data/state/o__r__7"
mkdir -p "$dir/pr-context"
printf 'owner o\nrepo r\npr 7\nbase_branch main\nrepo_root %s\n' "$clone" >"$dir/meta.txt"
printf 'commits 2\n' >"$dir/pr-context/meta-full.txt"
: | sh "$REPO_ROOT/scripts/resolve-settings.sh" "$dir" >/dev/null
rs=$(printf '\036')
history() {
	# history <lines>: the merged list, number, merge commit, count, subjects
	printf '%s\n' "$@" >"$stub/pr-list"
}
record() { sed -n "s/^$1 //p" "$dir/pr-context/merge-method.txt"; }
run() { sh "$REPO_ROOT/scripts/merge-method.sh" "$dir" "$@"; }

# Every shape is read from the clone; two multi-commit samples are too
# few, and over every shape squash and rebase tie, so a person decides
# with the counts in the record.
printf 'true true true false\n' >"$stub/api-repos_o_r"
history "1	$m1	1	Add one" "2	$m2	2	Add two${rs}Fix two" "3	$m3	2	Add three${rs}Fix three" "4	$m4	1	Add four" "5	$m5	1	Add five"
rc=0
out=$(run) || rc=$?
[ "$rc" -eq 4 ]
[ "$out" = "merge-method: undecided among merge squash rebase, history merge 1 squash 1 rebase 1 either 2; set merge_method" ]
[ "$(record method)" = undecided ]
[ "$(record allowed)" = "merge squash rebase" ]
[ "$(record delete_branch_on_merge)" = false ]
grep -qx "pr list --repo o/r --state merged --limit 30 --base main --json number,mergeCommit,commits --jq .*" "$stub/calls.log"

# A person's choice is recorded against the allowed list.
if run --set rebase-merge 2>"$SCRATCH/err"; then
	echo "expected refusal of an unknown method" >&2
	exit 1
fi
[ "$(run --set squash)" = "merge-method: squash reason asked" ]
[ "$(record method)" = squash ]
[ "$(record reason)" = asked ]
[ "$(run)" = "merge-method: squash reason asked" ]

# A clear majority within the pull request's own shape wins; "either"
# counts for both squash and rebase, so with merge disallowed the
# single-commit history settles a single-commit pull request.
rm -f "$stub/calls.log"
history "2	$m2	2	Add two${rs}Fix two" "6	$m6	2	Add six${rs}Fix six" "3	$m3	2	Add three${rs}Fix three" "9	$m2	2	Add two${rs}Fix two"
[ "$(run --refresh)" = "merge-method: squash reason history-multi 3/4" ]
[ "$(record history)" = "merge 0 squash 3 rebase 1 either 0" ]
printf 'commits 1\n' >"$dir/pr-context/meta-full.txt"
printf 'false true true false\n' >"$stub/api-repos_o_r"
history "4	$m4	1	Add four" "5	$m5	1	Add five" "1	$m1	1	Add one" "6	$m6	2	Add six${rs}Fix six" "3	$m3	2	Add three${rs}Fix three"
rc=0
out=$(run --refresh) || rc=$?
[ "$rc" -eq 4 ]
[ "$out" = "merge-method: undecided among squash rebase, history merge 1 squash 1 rebase 1 either 2; set merge_method" ]
history "4	$m4	1	Add four" "5	$m5	1	Add five" "2	$m2	2	Add two${rs}Fix two" "6	$m6	2	Add six${rs}Fix six"
[ "$(run --refresh)" = "merge-method: squash reason history-all 4/4" ]

# Fewer than three with this base widens to every base.
rm -f "$stub/calls.log"
printf '4	%s	1	Add four\n' "$m4" >"$stub/pr-list.1"
printf '4	%s	1	Add four\n5	%s	1	Add five\n2	%s	2	Add two%sFix two\n' "$m4" "$m5" "$m2" "$rs" >"$stub/pr-list.2"
[ "$(run --refresh)" = "merge-method: squash reason history-all 3/3" ]
[ "$(grep -c '^pr list' "$stub/calls.log")" -eq 2 ]
grep -q -- '--state merged --limit 30 --json' "$stub/calls.log"

# One allowed method needs no history; a setting wins when allowed and
# is refused when not.
rm -f "$stub/pr-list" "$stub/calls.log"
printf 'false false true true\n' >"$stub/api-repos_o_r"
[ "$(run --refresh)" = "merge-method: rebase reason allowed-only" ]
[ "$(record delete_branch_on_merge)" = true ]
[ ! -f "$stub/calls.log" ] || ! grep -q '^pr list' "$stub/calls.log"
printf 'method squash\n' >"$dir/overrides.txt"
: | sh "$REPO_ROOT/scripts/resolve-settings.sh" "$dir" >/dev/null
if run --refresh 2>"$SCRATCH/err"; then
	echo "expected refusal of a setting the repository does not allow" >&2
	exit 1
fi
grep -q "names squash, which o/r does not allow; it allows rebase" "$SCRATCH/err"
printf 'true true true false\n' >"$stub/api-repos_o_r"
[ "$(run --refresh)" = "merge-method: squash reason setting" ]
[ "$(record reason)" = setting ]

# A missing merge commit in the clone is left out, never guessed.
: >"$dir/overrides.txt"
: | sh "$REPO_ROOT/scripts/resolve-settings.sh" "$dir" >/dev/null
history "1	$m1	1	Add one" "8	0000000000000000000000000000000000000000	1	Gone" "4	$m4	1	Add four" "5	$m5	1	Add five"
rc=0
out=$(run --refresh) || rc=$?
[ "$rc" -eq 4 ]
[ "$(record history)" = "merge 1 squash 0 rebase 0 either 2" ]

if sh "$REPO_ROOT/scripts/merge-method.sh" "$SCRATCH/nowhere" 2>"$SCRATCH/err"; then
	echo "expected failure without meta.txt" >&2
	exit 1
fi
grep -q "no meta.txt" "$SCRATCH/err"
if run --wat 2>"$SCRATCH/err"; then
	echo "expected refusal of an unknown argument" >&2
	exit 1
fi
grep -q "unknown argument: --wat" "$SCRATCH/err"
