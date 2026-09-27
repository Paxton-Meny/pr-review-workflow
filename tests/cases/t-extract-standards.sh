#!/bin/sh
# extract-standards: gathers matching clone files, refuses escapes, cleans up.
set -eu

clone="$SCRATCH/clone"
mkdir -p "$clone/sub"
git init --quiet "$clone"
printf 'Rule one.\nRule two.\n' >"$clone/HOUSE_RULES.md"
printf 'Pin everything.\n' >"$clone/DEPS_RULES.md"
printf 'tracked\n' >"$clone/README.md"
printf 'secret\n' >"$SCRATCH/outside.md"
ln -s "$SCRATCH/outside.md" "$clone/LINKED_RULES.md"

dir="$SCRATCH/state"
mkdir -p "$dir/pr-context"
printf 'owner acme\nrepo widgets\npr 7\nrepo_root %s\n' "$clone" >"$dir/meta.txt"

out=$(sh "$REPO_ROOT/scripts/extract-standards.sh" "$dir" 'HOUSE_RULES.md' '*_RULES.md')
[ "$out" = "extract-standards: 2 files, 5 lines" ]
grep -qx '===== HOUSE_RULES.md =====' "$dir/pr-context/standards.txt"
grep -qx 'Pin everything.' "$dir/pr-context/standards.txt"
if grep -q 'secret' "$dir/pr-context/standards.txt"; then
	echo "symlinked files must be skipped" >&2
	exit 1
fi
[ "$(grep -cx '===== HOUSE_RULES.md =====' "$dir/pr-context/standards.txt")" -eq 1 ]

out=$(sh "$REPO_ROOT/scripts/extract-standards.sh" "$dir")
[ "$out" = "extract-standards: none configured" ]
[ ! -f "$dir/pr-context/standards.txt" ]

out=$(sh "$REPO_ROOT/scripts/extract-standards.sh" "$dir" 'NOPE_*.md')
[ "$out" = "extract-standards: no files matched" ]
[ ! -f "$dir/pr-context/standards.txt" ]

if sh "$REPO_ROOT/scripts/extract-standards.sh" "$dir" '../outside.md' 2>"$SCRATCH/err"; then
	echo "expected refusal of a path escape" >&2
	exit 1
fi
grep -q "outside the clone" "$SCRATCH/err"

if sh "$REPO_ROOT/scripts/extract-standards.sh" "$dir" '/etc/passwd' 2>"$SCRATCH/err"; then
	echo "expected refusal of an absolute path" >&2
	exit 1
fi
grep -q "outside the clone" "$SCRATCH/err"

cd "$SCRATCH"
out=$(sh "$REPO_ROOT/scripts/extract-standards.sh" state 'HOUSE_RULES.md')
[ "$out" = "extract-standards: 1 files, 3 lines" ]
[ -f "$SCRATCH/state/pr-context/standards.txt" ]
[ ! -e "$clone/state" ]
