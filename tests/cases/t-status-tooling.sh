#!/bin/sh
# list-runs and stats-report: filtering, counts, empty-state behavior.
set -eu

data="$SCRATCH/data"
mkdir -p "$data/state"

out=$(sh "$REPO_ROOT/scripts/stats-report.sh" "$data")
[ "$out" = "stats-report: no finished runs recorded" ]

printf 'run o/r#7 outcome merged rounds 2 findings 6 verified 6 wont-fix 0 unresolved 0 reopens 1 demoted 1 contracts 2 samples 1 kind code groups 2 seams 1\nrun o/r#9 outcome parked rounds 4 findings 3 verified 1 wont-fix 0 unresolved 2 reopens 3 demoted 0 contracts 0 samples 1 kind code groups 1 seams 0\n' >"$data/state/stats.txt"
out=$(sh "$REPO_ROOT/scripts/stats-report.sh" "$data")
printf '%s\n' "$out" | grep -qx 'stats-report: runs 2 merged 1 parked 1 held 0 review-only 0'
printf '%s\n' "$out" | grep -qx 'stats-report: rounds 0:0 1:0 2:1 3:0 4:1 runs-with-reopens 2'
printf '%s\n' "$out" | grep -qx 'stats-report: findings 9 verified 7 wont-fix 0 demoted 1 contracts 2 seams 1'

d1="$data/state/o__r__7"
mkdir -p "$d1/findings"
printf 'owner o\nrepo r\npr 7\n' >"$d1/meta.txt"
printf '2\n' >"$d1/rounds.txt"
printf 'id: F001\nstatus: verified\nreopens: 0\n---\nbody\n' >"$d1/findings/F001"
printf 'id: F002\nstatus: open\nreopens: 0\n---\nbody\n' >"$d1/findings/F002"
d2="$data/state/x__y__3"
mkdir -p "$d2/worktree"
printf 'owner x\nrepo y\npr 3\n' >"$d2/meta.txt"

cd "$SCRATCH"
out=$(sh "$REPO_ROOT/scripts/list-runs.sh" "$data" all)
printf '%s\n' "$out" | grep -qx 'run o/r#7 rounds 2 open 1 addressed 0 verified 1 wont-fix 0 resumable no'
printf '%s\n' "$out" | grep -qx 'run x/y#3 rounds 0 open 0 addressed 0 verified 0 wont-fix 0 resumable yes'
printf '%s\n' "$out" | grep -qx 'list-runs: 2 runs'

out=$(sh "$REPO_ROOT/scripts/list-runs.sh" "$data" o/r)
printf '%s\n' "$out" | grep -qx 'list-runs: 1 runs for o/r'
printf '%s\n' "$out" | grep -q 'run o/r#7'

clone="$SCRATCH/clone"
git init -q "$clone"
git -C "$clone" remote add origin https://github.com/x/y.git
cd "$clone"
out=$(sh "$REPO_ROOT/scripts/list-runs.sh" "$data")
printf '%s\n' "$out" | grep -qx 'list-runs: 1 runs for x/y'
printf '%s\n' "$out" | grep -q 'resumable yes'
