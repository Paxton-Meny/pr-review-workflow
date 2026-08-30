#!/bin/sh
# init-state: creates the ledger, validates refs, refuses non-open PRs, idempotent.
set -eu

stub="$SCRATCH/stub"
mkdir -p "$stub"
export GH_STUB_DIR="$stub"
export PATH="$REPO_ROOT/tests/stubs:$PATH"
data="$SCRATCH/data"

printf 'author octocat\nhead_branch feat-thing\nbase_branch main\nhead_sha abc123\nurl https://github.com/acme/widgets/pull/7\ncross_repo false\nstate OPEN\n' >"$stub/pr-view"
printf 'octocat\n' >"$stub/api-user"

dir=$(sh "$REPO_ROOT/scripts/init-state.sh" "$data" "acme/widgets#7")
[ "$dir" = "$data/state/acme__widgets__7" ]
grep -qx 'owner acme' "$dir/meta.txt"
grep -qx 'head_sha abc123' "$dir/meta.txt"
grep -qx 'self_login octocat' "$dir/meta.txt"
grep -qx 'cross_repo false' "$dir/meta.txt"
grep -qx '0' "$dir/round.txt"
! grep -q '^state ' "$dir/meta.txt"

url_dir=$(sh "$REPO_ROOT/scripts/init-state.sh" "$data" "https://github.com/acme/widgets/pull/7")
[ "$url_dir" = "$dir" ]

printf '2\n' >"$dir/round.txt"
sh "$REPO_ROOT/scripts/init-state.sh" "$data" "acme/widgets#7" >/dev/null
grep -qx '2' "$dir/round.txt"

if sh "$REPO_ROOT/scripts/init-state.sh" "$data" "acme/widgets#nope" 2>"$SCRATCH/err"; then
	echo "expected failure on a bad number" >&2
	exit 1
fi
grep -q "no pull request number" "$SCRATCH/err"

if sh "$REPO_ROOT/scripts/init-state.sh" "$data" "not a ref" 2>"$SCRATCH/err"; then
	echo "expected failure on a bad ref" >&2
	exit 1
fi

printf 'author octocat\nhead_branch feat-thing\nbase_branch main\nhead_sha abc123\nurl u\nstate MERGED\n' >"$stub/pr-view"
if sh "$REPO_ROOT/scripts/init-state.sh" "$data" "acme/widgets#7" 2>"$SCRATCH/err"; then
	echo "expected failure on a merged pull request" >&2
	exit 1
fi
grep -q "MERGED, not open" "$SCRATCH/err"
