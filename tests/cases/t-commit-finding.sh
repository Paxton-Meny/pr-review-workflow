#!/bin/sh
# commit-finding: one call commits a fix as the signed-in account and
# records it, so the ledger is current the moment each fix lands.
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
git -C "$clone" config user.name "Someone Else"
git -C "$clone" config user.email "else@example.invalid"
printf 'one\n' >"$clone/file.txt"
printf 'a\n' >"$clone/other.txt"
git -C "$clone" add file.txt other.txt
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
printf 'owner %s\nrepo widgets\npr 7\nhead_branch feat-thing\nhead_sha %s\ncross_repo false\nself_login %s\nself_email %s\n' \
	"$fixture_owner" "$head" "$fixture_name" "$fixture_email" >"$dir/meta.txt"
for n in 1 2 3; do
	printf '=== finding\ncategory: correctness\nseverity: minor\npath: file.txt\nline: %s\nside: RIGHT\ntitle: Thing %s\n---\nFix: add a line.\nResolution: done.\n' "$n" "$n" |
		sh "$s/save-findings.sh" "$dir" >/dev/null
done
sh "$s/update-finding.sh" "$dir" F001 comment_id=9001 placement=inline >/dev/null
sh "$s/update-finding.sh" "$dir" F002 comment_id=9002 placement=inline >/dev/null
printf '5551\n' >"$stub/api-repos_${fixture_owner}_widgets_pulls_7_comments_9001_replies"
printf '5552\n' >"$stub/api-repos_${fixture_owner}_widgets_pulls_7_comments_9002_replies"

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
commit() {
	# commit <subject> <id> <path>...: the subject piped in, as the editor does
	subject=$1
	shift
	printf '%s\n' "$subject" | sh "$s/commit-finding.sh" "$dir" "$@"
}

# Nothing changed yet: no commit, and the finding stays open.
refused 3 "nothing to commit for F001" commit "Add the third line" F001 file.txt
grep -qx 'status: open' "$dir/findings/F001"

# Bad input is refused before anything is staged.
printf 'three\n' >>"$wt/file.txt"
printf 'b\n' >>"$wt/other.txt"
refused 1 "unknown finding: F009" commit "Add the third line" F009 file.txt
refused 1 "stay inside it: ../clone/file.txt" commit "Add the third line" F001 ../clone/file.txt
refused 1 "stay inside it: /etc/passwd" commit "Add the third line" F001 /etc/passwd
refused 1 "stay inside it: -A" commit "Add the third line" F001 -A
refused 1 "ends with a period" commit "Add the third line." F001 file.txt
refused 1 "exactly one line" sh -c "printf 'a\nb\n' | sh '$s/commit-finding.sh' '$dir' F001 file.txt"
refused 1 "exactly one line" sh -c "sh '$s/commit-finding.sh' '$dir' F001 file.txt </dev/null"
refused 1 "over 72" commit "$(printf '%073d' 0)" F001 file.txt
refused 1 "usage: commit-finding.sh" commit "Add the third line" F001
[ -z "$(git -C "$wt" diff --cached --name-only)" ]

# One call commits only the named paths, as the signed-in account, and
# marks the finding addressed with that commit.
out=$(commit "Add the third line" F001 file.txt)
fix=$(git -C "$wt" rev-parse --short HEAD)
[ "$out" = "commit-finding: F001 addressed in $fix" ]
grep -qx 'status: addressed' "$dir/findings/F001"
grep -qx "commit: $fix" "$dir/findings/F001"
[ "$(git -C "$wt" log -1 --format='%an <%ae>|%s|%b')" = "$fixture_name <$fixture_email>|Add the third line|Addresses F001." ]
[ "$(git -C "$wt" show --format= --name-only HEAD)" = file.txt ]
[ "$(git -C "$wt" status --porcelain)" = " M other.txt" ]

# A finding already addressed is not committed twice.
refused 1 "F001 is addressed, not open" commit "Add it again" F001 other.txt

out=$(commit "Extend the other file" F002 other.txt)
fix2=$(git -C "$wt" rev-parse --short HEAD)
grep -qx "commit: $fix2" "$dir/findings/F002"

# The replies wait for the push, then one call covers every finding; one
# without a thread is named and skipped.
printf 'c\n' >>"$wt/other.txt"
commit "Extend it once more" F003 other.txt >/dev/null
refused 1 "not on the pushed head" sh "$s/reply-thread.sh" "$dir" --addressed F001 F002 F003
[ ! -f "$stub/calls.log" ]
sh "$s/push-branch.sh" "$dir" >/dev/null
out=$(sh "$s/reply-thread.sh" "$dir" --addressed F001 F002 F003)
[ "$out" = "reply-thread: replied to 9001 as 5551
reply-thread: replied to 9002 as 5552
reply-thread: F003 has no thread, nothing to reply to" ]
grep -qx "Addressed in $fix (Add the third line)." "$stub/bodies.log"
grep -qx "Addressed in $fix2 (Extend the other file)." "$stub/bodies.log"
refused 1 "usage: reply-thread.sh" sh "$s/reply-thread.sh" "$dir" --addressed

# The editor's definition names the calls, and the scope hook lets it run them.
grep -q 'commit-finding.sh <state-dir> <id> <paths>' "$REPO_ROOT/agents/editor.md"
grep -q "scripts='run-contract append-note reply-thread push-branch update-finding sync-branch commit-finding'" "$s/agent-scope.sh"
