#!/bin/sh
# sweep-state: reaps closed runs in every repository, retains newest ledgers per repository.
set -eu

stub="$SCRATCH/stub"
mkdir -p "$stub"
export GH_STUB_DIR="$stub"
export PATH="$REPO_ROOT/tests/stubs:$PATH"

root="$SCRATCH/state"
mk() {
	mkdir -p "$root/$1"
	printf 'owner Paxton-Meny\nrepo widgets\npr %s\n' "$2" >"$root/$1/meta.txt"
	mkdir -p "$root/$1/findings"
	touch -t "$3" "$root/$1"
}
mk Paxton-Meny__widgets__1 1 202501010000
mk Paxton-Meny__widgets__2 2 202502010000
mk Paxton-Meny__widgets__3 3 202503010000
mkdir -p "$root/other__repo__9/findings"
printf 'owner other\nrepo repo\npr 9\n' >"$root/other__repo__9/meta.txt"

mkdir -p "$root/Paxton-Meny__widgets__4/worktree" "$root/Paxton-Meny__widgets__4/pr-context"
printf 'owner Paxton-Meny\nrepo widgets\npr 4\n' >"$root/Paxton-Meny__widgets__4/meta.txt"
mkdir -p "$root/Paxton-Meny__widgets__5/worktree"
printf 'owner Paxton-Meny\nrepo widgets\npr 5\n' >"$root/Paxton-Meny__widgets__5/meta.txt"

# A held run has no worktree but stays live until its pull request closes.
mkdir -p "$root/Paxton-Meny__widgets__6/findings"
printf 'owner Paxton-Meny\nrepo widgets\npr 6\n' >"$root/Paxton-Meny__widgets__6/meta.txt"
printf 'held\n' >"$root/Paxton-Meny__widgets__6/outcome.txt"
touch -t 202504010000 "$root/Paxton-Meny__widgets__6"
# A held run in another repository whose pull request closed since.
mkdir -p "$root/other__repo__8/findings"
printf 'owner other\nrepo repo\npr 8\n' >"$root/other__repo__8/meta.txt"
printf 'held\n' >"$root/other__repo__8/outcome.txt"

printf 'MERGED\n' >"$stub/pr-view.1"
printf 'OPEN\n' >"$stub/pr-view.2"
printf 'OPEN\n' >"$stub/pr-view.3"
printf 'CLOSED\n' >"$stub/pr-view.4"

dir="$root/Paxton-Meny__widgets__3"
out=$(sh "$REPO_ROOT/scripts/sweep-state.sh" "$dir" 3)
[ "$out" = "sweep-state: stale 2 pruned 1 kept 5" ]
[ ! -d "$root/Paxton-Meny__widgets__4/worktree" ]
[ -f "$root/Paxton-Meny__widgets__4/meta.txt" ]
[ "$(cat "$root/Paxton-Meny__widgets__4/outcome.txt")" = closed ]
[ -d "$root/Paxton-Meny__widgets__5/worktree" ]
[ ! -f "$root/Paxton-Meny__widgets__5/outcome.txt" ]
[ -d "$root/Paxton-Meny__widgets__6" ]
[ "$(cat "$root/Paxton-Meny__widgets__6/outcome.txt")" = held ]
[ ! -d "$root/Paxton-Meny__widgets__1" ]
[ -d "$root/Paxton-Meny__widgets__2" ]
[ -d "$root/other__repo__9" ]
[ "$(cat "$root/other__repo__8/outcome.txt")" = closed ]
grep -c '^pr view' "$stub/calls.log" | grep -qx 4

# The current run is counted but never pruned, even when it is oldest.
touch -t 202001010000 "$dir"
out=$(sh "$REPO_ROOT/scripts/sweep-state.sh" "$dir" 1)
[ "$out" = "sweep-state: stale 0 pruned 2 kept 3" ]
[ -d "$dir" ]
[ -d "$root/Paxton-Meny__widgets__4" ]
[ ! -d "$root/Paxton-Meny__widgets__2" ]
[ -d "$root/Paxton-Meny__widgets__6" ]
[ -d "$root/other__repo__8" ]
[ ! -d "$root/other__repo__9" ]

if sh "$REPO_ROOT/scripts/sweep-state.sh" "$dir" 0 2>"$SCRATCH/err"; then
	echo "expected refusal of keep zero" >&2
	exit 1
fi
grep -q "keep must be a positive number" "$SCRATCH/err"
