#!/bin/sh
# pr-history: size statistics from one listing, per-author lines with the
# user always shown, the fork share, a REST fallback without sizes, and
# the limit clamped.
set -eu

stub="$SCRATCH/stub"
mkdir -p "$stub"
export GH_STUB_DIR="$stub"
export PATH="$REPO_ROOT/tests/stubs:$PATH"
dir="$SCRATCH/survey"
mkdir -p "$dir"
printf 'owner Paxton-Meny\nrepo widgets\nbase main\nrepo_root %s\n' "$SCRATCH" >"$dir/meta.txt"
printf 'Paxton-Meny 308824607\n' >"$stub/api-user"
history() { sh "$REPO_ROOT/scripts/pr-history.sh" "$@"; }

# Twenty uniform pull requests by one author: tight dispersion, no forks.
awk 'BEGIN { for (i = 1; i <= 20; i++) printf "%d Paxton-Meny %d %d 3 false 2026-0%d-1%dT10:00:00Z main feat-%d\n", i, 80 + i * 4, 20 + i, (i % 9) + 1, i % 10, i }' >"$stub/pr-list"
out=$(history "$dir")
printf '%s\n' "$out" | grep -qx 'history: source pr-list prs 20 merged since 2026-01-18'
printf '%s\n' "$out" | grep -qx 'history: self Paxton-Meny'
printf '%s\n' "$out" | grep -qx 'history: lines p50 150 p90 190 max 200 dispersion 1.3'
printf '%s\n' "$out" | grep -qx 'history: share over 300 0% over 800 0% over 1500 0% over 4000 0%'
printf '%s\n' "$out" | grep -qx 'history: forks 0% authors 1'
printf '%s\n' "$out" | grep -qx 'history: author Paxton-Meny prs 20 p50 150 p90 190 max 200 self yes'
[ "$(grep -c . "$dir/history.txt")" -eq 20 ]
[ "$(cat "$dir/history-summary.txt")" = "$out" ]
grep -q -- '--limit 100' "$stub/calls.log"

# Wide dispersion, a fork author, and more authors than the table shows.
{
	printf '1 Paxton-Meny 10 10 1 false 2026-03-01T00:00:00Z main topic-1\n'
	printf '2 Paxton-Meny 20 20 2 false 2026-03-02T00:00:00Z main topic-2\n'
	printf '3 Paxton-Meny 30 10 2 false 2026-03-03T00:00:00Z main topic-3\n'
	printf '4 other_owner 2000 1500 40 true 2026-03-04T00:00:00Z main topic-4\n'
	printf '5 other_owner 4000 1000 80 true 2026-03-05T00:00:00Z main topic-5\n'
	for a in a_1 a_2 a_3 a_4 a_5 a_6 a_7 a_8; do printf '9 %s 5 5 1 false 2026-03-06T00:00:00Z main topic-%s\n' "$a" "$a"; done
} >"$stub/pr-list"
rm -f "$stub/calls.log"
out=$(history "$dir" 500)
printf '%s\n' "$out" | grep -qx 'history: source pr-list prs 13 merged since 2026-03-01'
printf '%s\n' "$out" | grep -q '^history: lines p50 10 p90 3500 max 5000 dispersion 350.0$'
printf '%s\n' "$out" | grep -qx 'history: share over 300 15% over 800 15% over 1500 15% over 4000 8%'
printf '%s\n' "$out" | grep -qx 'history: forks 15% authors 10'
printf '%s\n' "$out" | grep -qx 'history: author Paxton-Meny prs 3 p50 40 p90 40 max 40 self yes'
printf '%s\n' "$out" | grep -qx 'history: author other_owner prs 2 p50 3500 p90 5000 max 5000 self no'
[ "$(printf '%s\n' "$out" | grep -c '^history: author ')" -eq 8 ]
grep -q -- '--limit 200' "$stub/calls.log"

# When the listing fails, the REST fallback gives counts without sizes.
printf '1\n' >"$stub/pr-list.exit"
printf '7 Paxton-Meny - - - false 2026-04-01T00:00:00Z main topic-7\n8 other_owner - - - true 2026-04-02T00:00:00Z main main\n' >"$stub/api-repos_Paxton-Meny_widgets_pulls"
out=$(history "$dir")
printf '%s\n' "$out" | grep -qx 'history: source api-fallback prs 2 merged since 2026-04-01'
printf '%s\n' "$out" | grep -qx 'history: sizes unavailable'
printf '%s\n' "$out" | grep -qx 'history: forks 50% authors 2'
! printf '%s\n' "$out" | grep -q 'dispersion'

# Only pull requests into the base count: releases into another branch
# and syncs from a long-lived branch are left out, while a stacked
# branch, the base of one pull request, and a fork's main branch stay.
rm -f "$stub/pr-list.exit"
{
	printf '20 Paxton-Meny 50 50 2 false 2026-05-01T00:00:00Z main topic-a\n'
	printf '21 Paxton-Meny 60 40 2 false 2026-05-02T00:00:00Z topic-a topic-b\n'
	printf '22 Paxton-Meny 30 30 2 false 2026-05-03T00:00:00Z main topic-b\n'
	printf '23 Paxton-Meny 900000 900000 4000 false 2026-05-04T00:00:00Z release main\n'
	printf '24 Paxton-Meny 800000 800000 4000 false 2026-05-05T00:00:00Z release main\n'
	printf '25 Paxton-Meny 700000 700000 4000 false 2026-05-06T00:00:00Z main release\n'
	printf '26 other_owner 10 10 1 true 2026-05-07T00:00:00Z main release\n'
} >"$stub/pr-list"
out=$(history "$dir")
printf '%s\n' "$out" | grep -qx 'history: source pr-list prs 3 merged since 2026-05-01'
printf '%s\n' "$out" | grep -qx 'history: excluded 4 merged into another base than main or syncing a long-lived branch'
printf '%s\n' "$out" | grep -qx 'history: lines p50 60 p90 100 max 100 dispersion 1.7'
[ "$(cut -d ' ' -f1 "$dir/history.txt" | tr '\n' ' ')" = '20 22 26 ' ] || {
	echo "kept: $(cut -d ' ' -f1 "$dir/history.txt" | tr '\n' ' ')" >&2
	exit 1
}

# Refusals: a bad limit, a missing survey.
if history "$dir" zero 2>/dev/null; then
	echo "expected refusal of a non-numeric limit" >&2
	exit 1
fi
if history "$SCRATCH/nowhere" 2>/dev/null; then
	echo "expected refusal without meta.txt" >&2
	exit 1
fi
