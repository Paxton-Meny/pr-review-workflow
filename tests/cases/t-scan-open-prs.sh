#!/bin/sh
# scan-open-prs: open pull requests on the same base that share files are
# compared hunk by hunk; stacked, other-base, and excluded-only overlaps
# are dropped; the closest candidates are fetched in order and capped;
# draft, same-author, and linked are marked; a failed listing is advisory.
set -eu

stub="$SCRATCH/stub"
mkdir -p "$stub"
export GH_STUB_DIR="$stub"
export PATH="$REPO_ROOT/tests/stubs:$PATH"

# One base tree; every diff is taken against it.
repo="$SCRATCH/repo"
git init --quiet "$repo"
git -C "$repo" config user.name tester
git -C "$repo" config user.email tester@example.invalid
mkdir -p "$repo/src" "$repo/docs"
awk 'BEGIN { print "def alpha():"; for (i = 2; i <= 30; i++) print "    a" i " = " i; print "def beta():"; for (i = 32; i <= 60; i++) print "    b" i " = " i }' >"$repo/src/app.py"
printf 'lock v1\n' >"$repo/package-lock.json"
printf 'doc\n' >"$repo/docs/x.md"
git -C "$repo" add .
git -C "$repo" commit --quiet -m base
diff_for() {
	# diff_for <sed expression> [<extra file content>]: a diff of the base
	# with src/app.py edited and, when given, the lockfile changed
	git -C "$repo" checkout --quiet -- .
	sed -i "$1" "$repo/src/app.py"
	[ -z "${2:-}" ] || printf '%s\n' "$2" >"$repo/package-lock.json"
	git -C "$repo" diff
	git -C "$repo" checkout --quiet -- .
}

data="$SCRATCH/data"
dir="$data/state/o__r__7"
ctx="$dir/pr-context"
mkdir -p "$ctx"
printf 'owner o\nrepo r\npr 7\nauthor alice\nbase_branch main\nhead_branch feat\n' >"$dir/meta.txt"
diff_for 's/^    a10 = 10$/    a10 = 100/; s/^    a11 = 11$/    a11 = 110/; s/^    a12 = 12$/    a12 = 120/' 'lock v2' >"$ctx/diff.patch"
printf 'src/app.py\t3\t3\npackage-lock.json\t1\t1\n' >"$ctx/files.txt"
printf 'Fixes the alpha constants. Follows up on #8.\n' >"$ctx/body.txt"
sh "$REPO_ROOT/scripts/split-diff.sh" "$dir" >/dev/null
: | sh "$REPO_ROOT/scripts/resolve-settings.sh" "$dir" >/dev/null
scan() { sh "$REPO_ROOT/scripts/scan-open-prs.sh" "$dir"; }

# The listing, as the jq filter shapes it: 7 is us; 8 is ours too, older;
# 9 is bob's, near; 10 is stacked on us; 11 targets another base; 12 is
# erin's draft that names us, same lines; 13 shares nothing; 14 shares
# only the lockfile; 15 to 17 share app.py but are older than the cap.
cat >"$stub/pr-list" <<'LIST'
pr 7	alice	false	main	feat	2026-10-14T10:00:00Z	false
file src/app.py
file package-lock.json
pr 8	alice	false	main	alice-2	2026-10-13T09:00:00Z	false
file src/app.py
pr 9	bob	false	main	bob-fix	2026-10-14T08:00:00Z	false
file src/app.py
file package-lock.json
pr 10	carol	false	feat	carol-on-top	2026-10-14T09:00:00Z	false
file src/app.py
pr 11	dave	false	release	dave-backport	2026-10-14T09:30:00Z	false
file src/app.py
pr 12	erin	true	main	erin-wip	2026-10-14T09:45:00Z	true
file src/app.py
pr 13	frank	false	main	frank-docs	2026-10-14T09:50:00Z	false
file docs/x.md
pr 14	gail	false	main	gail-lock	2026-10-14T09:55:00Z	false
file package-lock.json
pr 15	hal	false	main	hal-1	2026-10-12T09:00:00Z	false
file src/app.py
pr 16	ida	false	main	ida-1	2026-10-11T09:00:00Z	false
file src/app.py
pr 17	jon	false	main	jon-1	2026-10-10T09:00:00Z	false
file src/app.py
LIST
# Diffs are fetched in candidate order: most shared files first, then
# most recently updated: 12, 9, 8, 15, 16; 17 is past the cap.
diff_for 's/^    a11 = 11$/    a11 = 1100/' >"$stub/pr-diff.1"
diff_for 's/^    a20 = 20$/    a20 = 200/' 'lock v9' >"$stub/pr-diff.2"
diff_for 's/^    b40 = 40$/    b40 = 400/' >"$stub/pr-diff.3"
diff_for 's/^    b45 = 45$/    b45 = 450/' >"$stub/pr-diff.4"
diff_for 's/^    b50 = 50$/    b50 = 500/' >"$stub/pr-diff.5"

out=$(scan)
[ "$out" = "$(printf 'candidate 12 by erin same files 1 draft linked\ncandidate 9 by bob near files 1\nscan-open-prs: overlap: 5 candidates, 1 near, 1 same, approximate')" ]
grep -qx 'candidate 12 erin same files 1 draft linked' "$ctx/overlap.txt"
grep -qx 'candidate 9 bob near files 1' "$ctx/overlap.txt"
grep -qx 'candidate 8 alice disjoint files 1 same-author linked' "$ctx/overlap.txt"
grep -qx 'candidate 15 hal disjoint files 1' "$ctx/overlap.txt"
grep -qx 'candidate 16 ida disjoint files 1' "$ctx/overlap.txt"
! grep -q 'candidate 1[0134]\|candidate 17\|unavailable' "$ctx/overlap.txt"
grep -q "^file	9	near	src/app.py	10-12	20-20	def alpha():$" "$ctx/overlap.txt"
grep -q "^file	12	same	src/app.py	10-12	11-11	def alpha():$" "$ctx/overlap.txt"
grep -qx 'overlap: 5 candidates, 1 near, 1 same, approximate' "$ctx/overlap.txt"
[ "$(grep -c '^pr diff' "$stub/calls.log")" -eq 5 ]
grep -q '^pr list --repo o/r --state open --limit 100' "$stub/calls.log"
[ "$(grep -c '^pr list' "$stub/calls.log")" -eq 1 ]

# Bundles exist for near and same only, restricted to the shared file.
[ -d "$ctx/overlap/pr-9" ] && [ -d "$ctx/overlap/pr-12" ]
[ ! -d "$ctx/overlap/pr-8" ] && [ ! -d "$ctx/overlap/pr-15" ]
grep -qx 'label pr-9' "$ctx/overlap/pr-9/summary.txt"
grep -qx 'flags none' "$ctx/overlap/pr-9/summary.txt"
grep -qx 'flags draft linked' "$ctx/overlap/pr-12/summary.txt"
grep -qx 'level near files 1 near 1 same 0' "$ctx/overlap/pr-9/summary.txt"
grep -qx '+    a20 = 200' "$ctx/overlap/pr-9/theirs.diff"
! grep -q 'package-lock' "$ctx/overlap/pr-9/theirs.diff"
grep -qx 'path: src/app.py' "$ctx/overlap/pr-9/ours.diff"
grep -qx 'R10 +    a10 = 100' "$ctx/overlap/pr-9/ours.diff"
! grep -q 'package-lock' "$ctx/overlap/pr-9/ours.diff"

# A rerun clears the earlier bundles before writing new ones.
rm -f "$stub"/pr-diff.* "$stub/calls.log"
printf 'pr 9\tbob\tfalse\tmain\tbob-fix\t2026-10-14T08:00:00Z\tfalse\nfile src/app.py\n' >"$stub/pr-list"
diff_for 's/^    b40 = 40$/    b40 = 400/' >"$stub/pr-diff.1"
[ "$(scan)" = "scan-open-prs: overlap: 1 candidates, 0 near, 0 same, approximate" ]
[ ! -d "$ctx/overlap/pr-12" ] && [ ! -d "$ctx/overlap/pr-9" ]

# A diff that cannot be fetched is noted, not fatal.
rm -f "$stub"/pr-diff.* "$stub/calls.log"
printf '1\n' >"$stub/pr-diff.exit"
[ "$(scan)" = "scan-open-prs: overlap: 1 candidates, 0 near, 0 same, approximate" ]
grep -qx 'candidate 9 bob unavailable files 1' "$ctx/overlap.txt"
rm -f "$stub/pr-diff.exit"

# A listing that fails is advisory.
rm -f "$stub/pr-list" "$stub/calls.log"
printf '1\n' >"$stub/pr-list.exit"
[ "$(scan)" = "scan-open-prs: could not list open pull requests for o/r; nothing compared" ]
[ "$(cat "$ctx/overlap.txt")" = "overlap: unavailable" ]
rm -f "$stub/pr-list.exit"

# Off lists nothing.
printf 'overlap_check off\n' | sh "$REPO_ROOT/scripts/resolve-settings.sh" "$dir" >/dev/null
rm -f "$stub/calls.log"
[ "$(scan)" = "scan-open-prs: overlap check off" ]
[ ! -f "$stub/calls.log" ]
