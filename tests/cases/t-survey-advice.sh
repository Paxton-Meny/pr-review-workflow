#!/bin/sh
# survey-advice: the audience decided once, the pin-or-auto table, stakes
# over variance, economy only for a file of the user's own, model advice
# as a recommendation only. The survey and preview lines come from the
# files setup saved in the survey directory.
set -eu

dir="$SCRATCH/survey"
mkdir -p "$dir"
advise() { sh "$REPO_ROOT/scripts/survey-advice.sh" "$@"; }
# lines <survey lines> <preview lines>: what setup saved before advising.
lines() { printf "$1" >"$dir/survey.txt"; printf "${2:-}" >"$dir/preview.txt"; }

# Wide variance, one author, nothing sensitive: leave the depth to routing,
# recommend a strong model, and the file is yours.
printf 'inventory: tier medium\ninventory: codeowners none\n' >"$dir/inventory.txt"
cat >"$dir/history-summary.txt" <<'H'
history: source pr-list prs 40 merged since 2026-01-01
history: self Paxton-Meny
history: lines p50 60 p90 900 max 5000 dispersion 15.0
history: share over 300 20% over 800 12% over 1500 5% over 4000 2%
history: forks 0% authors 1
history: author Paxton-Meny prs 40 p50 60 p90 900 max 5000 self yes
H
lines 'survey: authors 1 in the last year, codeowners no\nsurvey: project file absent, local file absent\n' 'settings: strong_model (empty) from default\n'
out=$(advise "$dir")
printf '%s\n' "$out" | grep -qx 'advice: double_review auto because pull request sizes vary 15.0-fold (p50 60, p90 900); the risky default lets each run decide'
printf '%s\n' "$out" | grep -q '^advice: cost_posture auto because '
printf '%s\n' "$out" | grep -q '^advice: review_samples auto because '
printf '%s\n' "$out" | grep -qx 'advice: strong_model recommend because 12% of merged pull requests exceed 800 changed lines and no strong model is configured; set one in /plugin configure so routing can climb'
printf '%s\n' "$out" | grep -qx 'advice: audience personal because no CODEOWNERS file, no forks, and fewer than 3 people at work here, so the file is yours'
! printf '%s\n' "$out" | grep -q 'economy'
printf '%s\n' "$out" | grep -qx 'advice: 5 lines'

# Tight, small, solo history: economy for a personal file, never for a team.
cat >"$dir/history-summary.txt" <<'H'
history: source pr-list prs 25 merged since 2026-01-01
history: self Paxton-Meny
history: lines p50 80 p90 150 max 280 dispersion 1.9
history: share over 300 0% over 800 0% over 1500 0% over 4000 0%
history: forks 0% authors 1
history: author Paxton-Meny prs 25 p50 80 p90 150 max 280 self yes
H
lines '' 'settings: strong_model opus from user\n'
out=$(advise "$dir" personal)
printf '%s\n' "$out" | grep -qx 'advice: cost_posture economy because 25 merged pull requests by you alone, p90 150 lines, no sensitive code; cheap fixes once a check command gates the round'
printf '%s\n' "$out" | grep -qx 'advice: audience personal because you named it'
printf '%s\n' "$out" | grep -qx 'advice: 2 lines'
lines ''
out=$(advise "$dir" team)
[ "$out" = "$(printf 'advice: audience team because you named it\nadvice: 1 lines')" ]
# The settings file already there decides when nothing was named: a
# tracked one is the team's, so no economy for it.
lines 'survey: project file tracked, local file absent\n'
out=$(advise "$dir")
printf '%s\n' "$out" | grep -qx "advice: audience team because the project file is tracked, so it is the team's"
! printf '%s\n' "$out" | grep -q 'economy'
lines 'survey: project file untracked, local file absent\n'
advise "$dir" | grep -qx 'advice: audience personal because the project file is untracked, so it is already yours'
lines 'survey: project file absent, local file present\n'
advise "$dir" | grep -qx 'advice: audience local because only a local file exists'
lines 'survey: authors 4 in the last year, codeowners no\nsurvey: project file absent, local file absent\n'
advise "$dir" | grep -qx "advice: audience team because 4 people committed in the last year, so the file is the team's"

# Stakes outrank variance: sensitive code, forks, and a CODEOWNERS file.
cat >"$dir/inventory.txt" <<'I'
inventory: tier large
inventory: codeowners .github/CODEOWNERS rules 4 owners 3
inventory: sensitive-dir src/auth hits 9 of 20 files
inventory: sensitive-dir src/payments hits 4 of 10 files
inventory: sensitive-dir src/crypto hits 3 of 3 files
inventory: sensitive-dir app/Services hits 40 of 120 files
I
cat >"$dir/history-summary.txt" <<'H'
history: source pr-list prs 100 merged since 2025-11-01
history: self Paxton-Meny
history: lines p50 100 p90 2000 max 9000 dispersion 20.0
history: share over 300 40% over 800 25% over 1500 15% over 4000 4%
history: forks 35% authors 12
history: author other_owner prs 30 p50 90 p90 1800 max 9000 self no
history: author Paxton-Meny prs 20 p50 120 p90 2200 max 4000 self yes
H
lines 'survey: sensitive src/billing/**\nsurvey: sensitive src/auth/**\nsurvey: sensitive app/Services/Vault/**\n' 'settings: strong_model opus from user\n'
out=$(advise "$dir")
printf '%s\n' "$out" | grep -qx "advice: audience team because a CODEOWNERS file names owners, so the file is the team's"
printf '%s\n' "$out" | grep -q '^advice: sensitive_paths .*src/auth/\*\*.*because '
printf '%s\n' "$out" | grep -q '^advice: sensitive_paths .*src/billing/\*\*.*because '
[ "$(printf '%s\n' "$out" | grep -o 'src/auth/\*\*' | wc -l | tr -d ' ')" -eq 1 ]
# A broad directory dense enough to qualify keeps its coverage beside a
# narrower one named inside it.
printf '%s\n' "$out" | grep -q '^advice: sensitive_paths .*app/Services/\*\*.*because '
printf '%s\n' "$out" | grep -q '^advice: sensitive_paths .*app/Services/Vault/\*\*.*because '
printf '%s\n' "$out" | grep -qx 'advice: double_review always because 4 directories hold sensitive code, so every change gets the gap pass'
printf '%s\n' "$out" | grep -qx 'advice: cost_posture quality because 4 sensitive directories and 25% of pull requests over 800 lines; only proven fixes start cheap'
printf '%s\n' "$out" | grep -q '^advice: review_samples 2 because '
! printf '%s\n' "$out" | grep -q 'strong_model'
! printf '%s\n' "$out" | grep -q ' auto '

# Too few pull requests, or none with sizes: nothing is pinned from size.
printf 'history: source pr-list prs 4 merged since 2026-05-01\nhistory: self Paxton-Meny\nhistory: lines p50 10 p90 4000 max 4000 dispersion 400.0\nhistory: share over 300 25%% over 800 25%% over 1500 25%% over 4000 25%%\nhistory: forks 0%% authors 1\n' >"$dir/history-summary.txt"
printf 'inventory: tier small\ninventory: codeowners none\n' >"$dir/inventory.txt"
lines ''
out=$(advise "$dir")
printf '%s\n' "$out" | grep -qx 'advice: sizes unknown because only 4 merged pull requests, fewer than 10, so no setting is pinned from their size'
printf '%s\n' "$out" | grep -qx 'advice: 2 lines'
printf 'history: source api-fallback prs 50 merged since 2026-05-01\nhistory: self Paxton-Meny\nhistory: sizes unavailable\nhistory: forks 40%% authors 6\n' >"$dir/history-summary.txt"
out=$(advise "$dir")
printf '%s\n' "$out" | grep -qx 'advice: sizes unknown because the listing carried no sizes, so no setting is pinned from pull request size'
printf '%s\n' "$out" | grep -qx 'advice: double_review always because 40% of merged pull requests came from forks, so every change gets the gap pass'
printf '%s\n' "$out" | grep -q "^advice: audience team because 40% of merged pull requests came from forks"

# A verified check command fills a gap the survey left.
rm "$dir/history-summary.txt"
printf '2 check sh scripts/verify.sh | the gate every change runs\n' >"$dir/digest.txt"
lines 'survey: found check 0 prefix 0 sensitive 0 standards 0\n'
out=$(advise "$dir")
printf '%s\n' "$out" | grep -qx 'advice: check_command sh scripts/verify.sh because the survey found no check command and the map verified exactly one'
lines 'survey: check makefile make check\n'
out=$(advise "$dir")
! printf '%s\n' "$out" | grep -q 'check_command'

# Migration directories the patterns in force already cover need no
# advice; uncovered ones are added for a project file and spelled out in
# full for a personal or local one, which replaces the list; a directory
# only named like migrations that the patterns catch is a
# recommendation, never a value.
printf '3 migrations db/changes/** | schema changes go here\n' >"$dir/digest.txt"
lines 'survey: migrations src/App/Data/Migrations ef-core\nsurvey: migrations db/Schema ssdt\nsurvey: migration-named docs/migration\n' 'settings: migration_paths *[Mm]igrations/* *[Mm]igration/* *db/migrate/* *alembic/versions/* from default\n'
out=$(advise "$dir" team)
printf '%s\n' "$out" | grep -qxF 'advice: migration_paths db/changes/* db/Schema/* because db/changes (the map), db/Schema (ssdt) hold migrations the patterns in force miss; a project file adds them to the list'
printf '%s\n' "$out" | grep -qxF 'advice: migration_paths recommend because docs/migration match the migration patterns but hold no migrations, so changes there would wait for a person at merge; narrow the patterns in /plugin configure, since a project file can only add to them'
if printf '%s\n' "$out" | grep -q 'Data/Migrations'; then
	echo "a directory the default patterns cover needs no advice" >&2
	exit 1
fi
out=$(advise "$dir" local)
printf '%s\n' "$out" | grep -qxF 'advice: migration_paths *[Mm]igrations/* *[Mm]igration/* *db/migrate/* *alembic/versions/* db/changes/* db/Schema/* because db/changes (the map), db/Schema (ssdt) hold migrations the patterns in force miss; a local file replaces the list, so it repeats the patterns in force'
out=$(advise "$dir" personal)
printf '%s\n' "$out" | grep -qxF 'advice: migration_paths *[Mm]igrations/* *[Mm]igration/* *db/migrate/* *alembic/versions/* db/changes/* db/Schema/* because db/changes (the map), db/Schema (ssdt) hold migrations the patterns in force miss; a personal file replaces the list, so it repeats the patterns in force'
rm "$dir/digest.txt"
lines 'survey: migrations app/migrations django\n' 'settings: migration_paths *[Mm]igrations/* from default\n'
out=$(advise "$dir" team)
if printf '%s\n' "$out" | grep -q 'migration_paths'; then
	echo "covered migrations and no misnamed directory give no migration advice" >&2
	exit 1
fi

# Refusals.
if advise "$dir" everyone </dev/null 2>/dev/null; then
	echo "expected refusal of an unknown audience" >&2
	exit 1
fi
if advise "$SCRATCH/nowhere" </dev/null 2>/dev/null; then
	echo "expected refusal without an inventory" >&2
	exit 1
fi
