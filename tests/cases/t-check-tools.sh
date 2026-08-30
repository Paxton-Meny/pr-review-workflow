#!/bin/sh
# check-tools: fails without tools, passes with an authenticated stub.
set -eu

bin="$SCRATCH/bin"
mkdir -p "$bin" "$SCRATCH/stub"
ln -s "$(command -v sh)" "$bin/sh"
ln -s "$(command -v cat)" "$bin/cat"

if PATH="$bin" sh "$REPO_ROOT/scripts/check-tools.sh" 2>"$SCRATCH/err"; then
	echo "expected failure without git" >&2
	exit 1
fi
grep -q "git not found" "$SCRATCH/err"

ln -s "$(command -v git)" "$bin/git"
if PATH="$bin" sh "$REPO_ROOT/scripts/check-tools.sh" 2>"$SCRATCH/err"; then
	echo "expected failure without gh" >&2
	exit 1
fi
grep -q "gh not found" "$SCRATCH/err"

ln -s "$REPO_ROOT/tests/stubs/gh" "$bin/gh"
if GH_STUB_DIR="$SCRATCH/stub" PATH="$bin" sh "$REPO_ROOT/scripts/check-tools.sh" 2>"$SCRATCH/err"; then
	echo "expected failure while unauthenticated" >&2
	exit 1
fi
grep -q "not authenticated" "$SCRATCH/err"

: >"$SCRATCH/stub/auth-status"
GH_STUB_DIR="$SCRATCH/stub" PATH="$bin" sh "$REPO_ROOT/scripts/check-tools.sh" | grep -q "ready"
