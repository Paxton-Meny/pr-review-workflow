#!/bin/sh
# classify-change: kinds by file class, line sums, class.txt, failure without state.
set -eu

dir="$SCRATCH/state"
ctx="$dir/pr-context"
mkdir -p "$ctx"

printf '001\tREADME.md\n002\tdocs/guide.rst\n' >"$ctx/diff-index.txt"
printf 'README.md\t10\t2\ndocs/guide.rst\t30\t8\n' >"$ctx/files.txt"
out=$(sh "$REPO_ROOT/scripts/classify-change.sh" "$dir")
[ "$out" = "classify-change: kind docs-only files 2 lines 50" ]
[ "$(cat "$ctx/class.txt")" = "$out" ]

printf '001\tsrc/app.py\n002\tREADME.md\n' >"$ctx/diff-index.txt"
printf 'src/app.py\t5\t1\nREADME.md\t3\t0\n' >"$ctx/files.txt"
out=$(sh "$REPO_ROOT/scripts/classify-change.sh" "$dir")
[ "$out" = "classify-change: kind code files 2 lines 9" ]

printf '001\ttests/test_app.py\n002\tsrc/util.spec.ts\n' >"$ctx/diff-index.txt"
printf 'tests/test_app.py\t4\t1\nsrc/util.spec.ts\t2\t2\n' >"$ctx/files.txt"
out=$(sh "$REPO_ROOT/scripts/classify-change.sh" "$dir")
[ "$out" = "classify-change: kind tests-only files 2 lines 9" ]

printf '001\tconfig.yaml\n002\t.gitignore\n003\trequirements-dev.txt\n' >"$ctx/diff-index.txt"
printf 'config.yaml\t2\t1\n.gitignore\t1\t0\nrequirements-dev.txt\t1\t1\n' >"$ctx/files.txt"
out=$(sh "$REPO_ROOT/scripts/classify-change.sh" "$dir")
[ "$out" = "classify-change: kind config-only files 3 lines 6" ]

printf '001\tREADME.md\n002\tconfig.yaml\n' >"$ctx/diff-index.txt"
printf 'README.md\t1\t0\nconfig.yaml\t1\t0\n' >"$ctx/files.txt"
out=$(sh "$REPO_ROOT/scripts/classify-change.sh" "$dir")
[ "$out" = "classify-change: kind mixed files 2 lines 2" ]

printf '001\tnew/path.md\n' >"$ctx/diff-index.txt"
printf 'other.md\t1\t0\n' >"$ctx/files.txt"
out=$(sh "$REPO_ROOT/scripts/classify-change.sh" "$dir")
[ "$out" = "classify-change: kind docs-only files 1 lines 0" ]

if sh "$REPO_ROOT/scripts/classify-change.sh" "$SCRATCH/empty" 2>"$SCRATCH/err"; then
	echo "expected failure without a diff index" >&2
	exit 1
fi
grep -q "no diff-index.txt" "$SCRATCH/err"
