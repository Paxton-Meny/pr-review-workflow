#!/bin/sh
# sweep-state: reaps closed stale runs, retains newest ledgers, isolates repos.
set -eu

stub="$SCRATCH/stub"
mkdir -p "$stub"
export GH_STUB_DIR="$stub"
export PATH="$REPO_ROOT/tests/stubs:$PATH"

root="$SCRATCH/state"
mk() {
	mkdir -p "$root/$1"
	printf 'owner acme\nrepo widgets\npr %s\n' "$2" >"$root/$1/meta.txt"
	mkdir -p "$root/$1/findings"
	touch -t "$3" "$root/$1"
}
mk acme__widgets__1 1 202501010000
mk acme__widgets__2 2 202502010000
mk acme__widgets__3 3 202503010000
mkdir -p "$root/other__repo__9/findings"
printf 'owner other\nrepo repo\npr 9\n' >"$root/other__repo__9/meta.txt"

mkdir -p "$root/acme__widgets__4/worktree" "$root/acme__widgets__4/pr-context"
printf 'owner acme\nrepo widgets\npr 4\n' >"$root/acme__widgets__4/meta.txt"
mkdir -p "$root/acme__widgets__5/worktree"
printf 'owner acme\nrepo widgets\npr 5\n' >"$root/acme__widgets__5/meta.txt"

printf 'MERGED\n' >"$stub/pr-view.1"
printf 'OPEN\n' >"$stub/pr-view.2"

dir="$root/acme__widgets__3"
out=$(sh "$REPO_ROOT/scripts/sweep-state.sh" "$dir" 3)
[ "$out" = "sweep-state: 1 stale runs cleaned, 1 old ledgers pruned, 3 kept" ]
[ ! -d "$root/acme__widgets__4/worktree" ]
[ -f "$root/acme__widgets__4/meta.txt" ]
[ -d "$root/acme__widgets__5/worktree" ]
[ ! -d "$root/acme__widgets__1" ]
[ -d "$root/acme__widgets__2" ]
[ -d "$root/other__repo__9" ]

if sh "$REPO_ROOT/scripts/sweep-state.sh" "$dir" 0 2>"$SCRATCH/err"; then
	echo "expected refusal of keep zero" >&2
	exit 1
fi
grep -q "keep must be a positive number" "$SCRATCH/err"
