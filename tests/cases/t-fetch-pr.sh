#!/bin/sh
# fetch-pr: fetches context, splits the diff, reports counts, fails loudly.
set -eu

stub="$SCRATCH/stub"
mkdir -p "$stub"
export GH_STUB_DIR="$stub"
export PATH="$REPO_ROOT/tests/stubs:$PATH"

dir="$SCRATCH/data/state/acme__widgets__7"
mkdir -p "$dir"
printf 'owner acme\nrepo widgets\npr 7\nhead_sha abc123\n' >"$dir/meta.txt"

cp "$REPO_ROOT/tests/fixtures/two-files.patch" "$stub/pr-diff"
printf 'title Add things\nadditions 4\ndeletions 2\nchanged_files 2\nlabels bug,ready\n' >"$stub/pr-view.1"
printf 'The body of the pull request.\n' >"$stub/pr-view.2"
printf 'src/app.py\t3\t2\ndocs/readme.md\t1\t0\n' >"$stub/pr-view.3"

out=$(sh "$REPO_ROOT/scripts/fetch-pr.sh" "$dir")
printf '%s\n' "$out" | grep -qx 'fetch-pr: 2 files, 4 additions, 2 deletions'
printf '%s\n' "$out" | grep -qx 'split-diff: 2 files, 9 commentable lines'

grep -qx 'title Add things' "$dir/pr-context/meta-full.txt"
grep -qx 'The body of the pull request.' "$dir/pr-context/body.txt"
grep -qx 'src/app.py	3	2' "$dir/pr-context/files.txt"
[ -f "$dir/pr-context/files/002.diff" ]

if sh "$REPO_ROOT/scripts/fetch-pr.sh" "$SCRATCH/nostate" 2>"$SCRATCH/err"; then
	echo "expected failure without meta.txt" >&2
	exit 1
fi
grep -q "no meta.txt" "$SCRATCH/err"

rm -rf "$dir/pr-context"
printf '1\n' >"$stub/pr-diff.exit"
rm "$stub/pr-diff"
printf 'pull request too large\n' >"$stub/pr-diff.err"
if sh "$REPO_ROOT/scripts/fetch-pr.sh" "$dir" 2>"$SCRATCH/err"; then
	echo "expected failure on a failing diff fetch" >&2
	exit 1
fi
grep -q "diff fetch failed" "$SCRATCH/err"
grep -q "fetch-pr: pull request too large" "$SCRATCH/err"
[ ! -f "$dir/pr-context/diff.patch" ]
