#!/bin/sh
# compare-hunks: same on intersection, near by distance or by a shared
# function, disjoint otherwise, the worst level per file, and the sum line.
set -eu

cmp_hunks() { sh "$REPO_ROOT/scripts/compare-hunks.sh" "$SCRATCH/ours" "$SCRATCH/theirs"; }

# No shared file at all.
printf 'a.py\t10\t20\t10\t20\tdef a():\n' >"$SCRATCH/ours"
printf 'b.py\t10\t20\t10\t20\tdef b():\n' >"$SCRATCH/theirs"
[ "$(cmp_hunks)" = "level none files 0 near 0 same 0" ]

# Same file, ranges far apart, different functions: disjoint.
printf 'a.py\t10\t20\t10\t20\tdef a():\n' >"$SCRATCH/ours"
printf 'a.py\t100\t110\t100\t110\tdef z():\n' >"$SCRATCH/theirs"
[ "$(cmp_hunks)" = "$(printf 'disjoint\ta.py\t10-20\t100-110\t\nlevel disjoint files 1 near 0 same 0')" ]

# Within twelve lines: near. Thirteen apart: disjoint.
printf 'a.py\t100\t110\t100\t110\t\n' >"$SCRATCH/ours"
printf 'a.py\t122\t130\t122\t130\t\n' >"$SCRATCH/theirs"
[ "$(cmp_hunks | head -n 1)" = "$(printf 'near\ta.py\t100-110\t122-130\t')" ]
printf 'a.py\t123\t130\t123\t130\t\n' >"$SCRATCH/theirs"
[ "$(cmp_hunks | head -n 1)" = "$(printf 'disjoint\ta.py\t100-110\t123-130\t')" ]

# Far apart but the headers name the same function: near, naming it.
printf 'a.py\t10\t12\t10\t12\tdef handle(req):\n' >"$SCRATCH/ours"
printf 'a.py\t80\t82\t80\t82\tdef handle(req):\n' >"$SCRATCH/theirs"
[ "$(cmp_hunks)" = "$(printf 'near\ta.py\t10-12\t80-82\tdef handle(req):\nlevel near files 1 near 1 same 0')" ]
# An empty function name never matches another empty one.
printf 'a.py\t10\t12\t10\t12\t\n' >"$SCRATCH/ours"
printf 'a.py\t80\t82\t80\t82\t\n' >"$SCRATCH/theirs"
[ "$(cmp_hunks | tail -n 1)" = "level disjoint files 1 near 0 same 0" ]

# Intersection: same, including a pure insertion inside our range.
printf 'a.py\t10\t20\t10\t20\t\n' >"$SCRATCH/ours"
printf 'a.py\t15\t15\t15\t17\t\n' >"$SCRATCH/theirs"
[ "$(cmp_hunks)" = "$(printf 'same\ta.py\t10-20\t15-15\t\nlevel same files 1 near 0 same 1')" ]

# The worst pair wins per file, and the sum counts files by level.
cat >"$SCRATCH/ours" <<'R'
a.py	10	20	10	20	def a():
a.py	200	210	200	210	def q():
b.py	5	6	5	6
c.py	1	2	1	2
R
cat >"$SCRATCH/theirs" <<'R'
a.py	300	310	300	310	def far():
a.py	18	25	18	25	def a():
b.py	10	11	10	11
c.py	500	501	500	501
d.py	1	1	1	1
R
[ "$(cmp_hunks)" = "$(printf 'same\ta.py\t10-20\t18-25\tdef a():\nnear\tb.py\t5-6\t10-11\t\ndisjoint\tc.py\t1-2\t500-501\t\nlevel same files 3 near 1 same 1')" ]

if sh "$REPO_ROOT/scripts/compare-hunks.sh" "$SCRATCH/ours" "$SCRATCH/nope" 2>"$SCRATCH/err"; then
	echo "expected failure on a missing range file" >&2
	exit 1
fi
grep -q "both range files must exist" "$SCRATCH/err"
