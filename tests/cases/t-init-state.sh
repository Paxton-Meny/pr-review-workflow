#!/bin/sh
# init-state: creates the ledger, validates refs, refuses non-open PRs, idempotent.
set -eu

stub="$SCRATCH/stub"
mkdir -p "$stub"
export GH_STUB_DIR="$stub"
export PATH="$REPO_ROOT/tests/stubs:$PATH"
data="$SCRATCH/data"

printf 'author octocat\nhead_branch feat-thing\nbase_branch main\nhead_sha abc123\nurl https://github.com/acme/widgets/pull/7\ncross_repo false\nmaintainer_can_modify true\nhead_repo_url https://github.com/acme/widgets.git\nstate OPEN\n' >"$stub/pr-view"
printf 'octocat 583231\n' >"$stub/api-user"

clone="$SCRATCH/clone"
git init -q "$clone"
git -C "$clone" remote add origin https://github.com/acme/widgets.git
cd "$clone"

dir=$(sh "$REPO_ROOT/scripts/init-state.sh" "$data" "acme/widgets#7")
[ "$dir" = "$data/state/acme__widgets__7" ]
grep -qx 'owner acme' "$dir/meta.txt"
grep -qx 'head_sha abc123' "$dir/meta.txt"
grep -qx 'self_login octocat' "$dir/meta.txt"
grep -qx 'self_email 583231+octocat@users.noreply.github.com' "$dir/meta.txt"
grep -qx 'cross_repo false' "$dir/meta.txt"
grep -qx 'maintainer_can_modify true' "$dir/meta.txt"
grep -q '^head_repo_url https://github.com/acme/widgets.git$' "$dir/meta.txt"
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

other="$SCRATCH/other-clone"
git init -q "$other"
git -C "$other" remote add origin git@github.com:acme/other-widgets.git
cd "$other"
if sh "$REPO_ROOT/scripts/init-state.sh" "$data" "acme/widgets#7" 2>"$SCRATCH/err"; then
	echo "expected refusal from a clone of the wrong repository" >&2
	exit 1
fi
grep -q "origin of .* is .*not acme/widgets" "$SCRATCH/err"
[ ! -d "$data/state/acme__widgets__7.wrong" ]

plain="$SCRATCH/plain"
mkdir -p "$plain"
cd "$plain"
if sh "$REPO_ROOT/scripts/init-state.sh" "$data" "acme/widgets#7" 2>"$SCRATCH/err"; then
	echo "expected refusal outside any clone" >&2
	exit 1
fi
grep -q "run from inside a clone" "$SCRATCH/err"
