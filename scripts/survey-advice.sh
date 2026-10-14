#!/bin/sh
# Turn the inventory, the pull request history, and the verified map into
# advice on which settings to pin and which to leave to per-run routing.
# Usage: sh scripts/survey-advice.sh <survey-dir> [team|personal|local]
#
# Reads inventory.txt and, when present, history-summary.txt,
# digest.txt, survey.txt (the survey's lines: the check candidates, the
# sensitive directories by name, the settings files found), and
# preview.txt (the settings preview: whether a strong model is
# configured, the migration patterns in force) from the survey
# directory. The audience is decided here, once: the one given, else
# the settings file already there (a tracked project file is the
# team's, an untracked one yours, a lone local file local), else team
# when a CODEOWNERS file names owners, pull requests come from forks, or
# at least three people merge or commit, else personal; every other
# piece of advice is written for that audience. Prints one
# "advice: <key> <value> because <reason>" line per decision: a value
# to write, "auto" to leave the key unset so defaults and per-run
# routing decide, or "recommend" for a model setting that belongs in
# the plugin configuration, never in a file. Stakes outrank variance:
# a repository with sensitive code or many fork contributors gets the
# second review pass whatever its size spread. Directories the survey or
# the verified map shows holding migrations that the migration paths in
# force do not cover are advised as extra patterns (the whole list for
# a personal or local file, which replaces it), and directories only
# named like migrations that the patterns catch are a recommendation
# to narrow them in the plugin configuration, since a project file
# cannot. The economy posture is never advised for a team file, which
# cannot lower a setting. The last line counts the advice given.
set -eu

dir=${1:?usage: survey-advice.sh <survey-dir> [team|personal|local]}
audience=${2:-}
[ -f "$dir/inventory.txt" ] || {
	echo "survey-advice: no inventory.txt in $dir, run inventory-repo.sh first" >&2
	exit 1
}
case "$audience" in
'' | team | personal | local) ;;
*)
	echo "survey-advice: audience must be team, personal, or local: $audience" >&2
	exit 1
	;;
esac

MIN_PRS=10
ECONOMY_MIN_PRS=20
WIDE_DISPERSION=3
TIGHT_DISPERSION=2
SMALL_LINES=300
MIN_SENSITIVE_DIRS_FOR_PASS=2
MIN_SENSITIVE_DIRS_FOR_QUALITY=3
FORK_SHARE_FOR_PASS=30
SHARD_SHARE_FOR_PASS=20
LARGE_SHARE_FOR_QUALITY=20
MIN_AUTHORS_FOR_TEAM=3

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cat "$dir/survey.txt" "$dir/preview.txt" 2>/dev/null >"$work/stdin" || true
[ -f "$dir/history-summary.txt" ] && cp "$dir/history-summary.txt" "$work/history" || : >"$work/history"
[ -f "$dir/digest.txt" ] && cp "$dir/digest.txt" "$work/digest" || : >"$work/digest"

awk -v audience="$audience" -v min_prs="$MIN_PRS" -v econ_prs="$ECONOMY_MIN_PRS" -v wide="$WIDE_DISPERSION" -v tight="$TIGHT_DISPERSION" \
	-v small="$SMALL_LINES" -v sens_pass="$MIN_SENSITIVE_DIRS_FOR_PASS" -v sens_quality="$MIN_SENSITIVE_DIRS_FOR_QUALITY" \
	-v fork_pass="$FORK_SHARE_FOR_PASS" -v shard_pass="$SHARD_SHARE_FOR_PASS" -v large_quality="$LARGE_SHARE_FOR_QUALITY" -v team_authors="$MIN_AUTHORS_FOR_TEAM" '
function advise(key, value, why) { printf "advice: %s %s because %s\n", key, value, why; given++ }
function glob_re(g,    re, i, c) {
	re = "^"
	for (i = 1; i <= length(g); i++) {
		c = substr(g, i, 1)
		if (c == "*") re = re ".*"
		else if (c == "?") re = re "."
		else if (c == "[" || c == "]") re = re c
		else if (c ~ /[.^$+(){}|\\\/]/) re = re "\\" c
		else re = re c
	}
	return re "$"
}
function covered(d,    i) { for (i = 1; i <= nglobs; i++) if ((d "/x") ~ glob_re(globs[i])) return 1; return 0 }
FILENAME == ARGV[1] {
	if ($2 == "sensitive-dir") { sdirs++; sdir[$3] = 1 }
	if ($2 == "codeowners" && $3 != "none") codeowners = 1
	next
}
FILENAME == ARGV[2] {
	if ($2 == "source") prs = $5
	if ($2 == "sizes" && $3 == "unavailable") nosizes = 1
	if ($2 == "lines") { p50 = $4; p90 = $6; disp = $10 }
	if ($2 == "share") { over_small = $5 + 0; over_large = $8 + 0; over_shard = $11 + 0 }
	if ($2 == "forks") { forks = $3 + 0; authors = $5 }
	if ($2 == "author" && $NF == "yes") { self = $3; self_prs = $5 }
	next
}
FILENAME == ARGV[3] {
	if ($2 == "migrations") { r = $3; sub(/\/(\*\*)?$/, "", r); if (!(r in migdir)) { migdir[r] = "the map"; migorder[++nmig] = r } }
	if ($2 == "check") { nchecks++; split($0, half, " \\| "); cmd = half[1]; sub(/^[^ ]+ check /, "", cmd); check_cmd = cmd }
	next
}
{
	if ($1 == "survey:" && $2 == "check") survey_checks++
	if ($1 == "survey:" && $2 == "sensitive") sdir_named[$3] = 1
	if ($1 == "settings:" && $2 == "strong_model" && $3 == "(empty)") strong_empty = 1
	if ($1 == "survey:" && $2 == "migrations" && !($3 in migdir)) { migdir[$3] = $4; migorder[++nmig] = $3 }
	if ($1 == "survey:" && $2 == "migration-named") named[++nnamed] = $3
	if ($1 == "survey:" && $2 == "project" && $3 == "file") { shared_state = $4; sub(/,$/, "", shared_state); local_state = $7 }
	if ($1 == "survey:" && $2 == "authors") commit_authors = $3 + 0
	if ($1 == "settings:" && $2 == "migration_paths" && $3 != "(empty)") { inforce = $0; sub(/^settings: migration_paths /, "", inforce); sub(/ from [a-z]+$/, "", inforce); nglobs = split(inforce, globs, " ") }
}
END {
	if (audience != "") why = "you named it"
	else if (shared_state == "tracked") { audience = "team"; why = "the project file is tracked, so it is the team'"'"'s" }
	else if (shared_state == "untracked") { audience = "personal"; why = "the project file is untracked, so it is already yours" }
	else if (local_state == "present") { audience = "local"; why = "only a local file exists" }
	else if (codeowners || forks > 0 || authors + 0 >= team_authors || commit_authors >= team_authors) {
		audience = "team"
		why = (codeowners ? "a CODEOWNERS file names owners" : (forks > 0 ? forks "% of merged pull requests came from forks" : (authors + 0 >= team_authors ? authors " people merged pull requests" : commit_authors " people committed in the last year"))) ", so the file is the team'"'"'s"
	} else { audience = "personal"; why = "no CODEOWNERS file, no forks, and fewer than " team_authors " people at work here, so the file is yours" }
	advise("audience", audience, why)
	paths = ""
	for (d in sdir) paths = paths (paths == "" ? "" : " ") d "/**"
	for (d in sdir_named) { p = d; sub(/\/\*\*$/, "", p); if (!(p in sdir)) paths = paths (paths == "" ? "" : " ") d }
	if (paths != "") advise("sensitive_paths", paths, "the inventory found sensitive surfaces or names there; no fix starts on the cheap model and the reviewer may climb")
	sized = (prs + 0 >= min_prs && !nosizes)
	if (!sized) {
		if (nosizes) advise("sizes", "unknown", "the listing carried no sizes, so no setting is pinned from pull request size")
		else advise("sizes", "unknown", "only " prs + 0 " merged pull requests, fewer than " min_prs ", so no setting is pinned from their size")
	}
	stakes = (sdirs + 0 >= sens_pass || forks >= fork_pass || (sized && over_shard >= shard_pass))
	if (stakes) {
		why = (sdirs + 0 >= sens_pass) ? sdirs " directories hold sensitive code" : (forks >= fork_pass ? forks "% of merged pull requests came from forks" : over_shard "% of merged pull requests exceed 1500 lines")
		advise("double_review", "always", why ", so every change gets the gap pass")
	} else if (sized && disp + 0 > wide) {
		advise("double_review", "auto", "pull request sizes vary " disp "-fold (p50 " p50 ", p90 " p90 "); the risky default lets each run decide")
	}
	quality = (sdirs + 0 >= sens_quality && sized && over_large >= large_quality)
	if (quality) {
		advise("cost_posture", "quality", sdirs " sensitive directories and " over_large "% of pull requests over 800 lines; only proven fixes start cheap")
		advise("review_samples", "2", "the same stakes; a second independent review pass raises recall where an escape is expensive")
	} else if (sized && disp + 0 > wide) {
		advise("cost_posture", "auto", "sizes vary " disp "-fold; the balanced default lets the check command decide per fix")
		advise("review_samples", "auto", "sizes vary " disp "-fold; one sample fits most of them")
	} else if (sized && disp + 0 <= tight && prs + 0 >= econ_prs && p90 + 0 < small && authors + 0 == 1 && self != "" && sdirs + 0 == 0 && audience != "team") {
		advise("cost_posture", "economy", prs " merged pull requests by you alone, p90 " p90 " lines, no sensitive code; cheap fixes once a check command gates the round")
	}
	if (sized && over_large > 0 && strong_empty)
		advise("strong_model", "recommend", over_large "% of merged pull requests exceed 800 changed lines and no strong model is configured; set one in /plugin configure so routing can climb")
	extra = ""; evidence = ""
	for (i = 1; i <= nmig; i++) if (!covered(migorder[i])) { extra = extra (extra == "" ? "" : " ") migorder[i] "/*"; evidence = evidence (evidence == "" ? "" : ", ") migorder[i] " (" migdir[migorder[i]] ")" }
	if (extra != "") advise("migration_paths", (audience != "team" && inforce != "" ? inforce " " extra : extra), evidence " hold migrations the patterns in force miss" (audience != "team" ? "; a " audience " file replaces the list, so it repeats the patterns in force" : "; a project file adds them to the list"))
	falsehits = ""
	for (i = 1; i <= nnamed; i++) if (covered(named[i])) falsehits = falsehits (falsehits == "" ? "" : ", ") named[i]
	if (falsehits != "") advise("migration_paths", "recommend", falsehits " match the migration patterns but hold no migrations, so changes there would wait for a person at merge; narrow the patterns in /plugin configure, since a project file can only add to them")
	if (nchecks == 1 && survey_checks + 0 == 0)
		advise("check_command", check_cmd, "the survey found no check command and the map verified exactly one")
	printf "advice: %d lines\n", given
}' "$dir/inventory.txt" "$work/history" "$work/digest" "$work/stdin"
