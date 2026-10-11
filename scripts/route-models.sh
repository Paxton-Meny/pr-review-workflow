#!/bin/sh
# Decide which model each role runs on, one line per unit of work.
# Usage: sh scripts/route-models.sh <state-dir> <stage> [key=value ...] [-- <ids>]
#
# Settings come from the run's resolved settings.txt when there is one;
# key=value arguments override them. Stages: review, gap, filter, edit,
# repair, verify, arbitrate. Keys,
# each with its manifest default: routing (auto), reviewer (inherit),
# editor (inherit), verifier (sonnet), strong (empty), posture
# (balanced), check (empty), prefixes (empty), round (1). A value that
# is still a literal ${user_config...} placeholder, as on an install with
# no saved configuration, counts as unset. For the edit and repair
# stages the finding ids follow a lone "--".
#
# Every decision is a rung on one ladder: cheap (sonnet), base (the
# role's own setting), strong (the strong model), plus a reasoning
# effort. Each printed line is label-value, is appended to
# pr-context/routes.txt, and names the model and effort the
# orchestrator passes as overrides, "inherit" included:
#   route <stage> <unit> rung <rung> model <model> effort <level>[ pinned <value>] reason <reason>[ ids ...]
# Effort starts at the level the role's agent definition declares and
# moves one level for each signal: up for a wide search (large code, a
# shard group on a seam, a gap pass over seams, each earlier attempt at
# a finding), up for stakes (a secrets, automation, or sensitive probe,
# a blocker or security finding), down where a later step checks the
# work (a minor or nit fix carried by a proven suggestion for the
# editor, an executable Check line or proven suggestion for the
# verifier) or the review is small docs or config with no risk. A batch
# or a verified round runs at its highest finding's level. The economy posture caps effort at high, the others
# at xhigh; max is never routed. Fixed routing keeps every role's own
# level. A set CLAUDE_CODE_EFFORT_LEVEL outranks every override, so the
# line records it as pinned.
# A sharded review gets one line per group, judged on that group's own
# files: it climbs for large or sensitive code when a strong model is
# set and drops for a small docs-only or config-only group with no risk
# signal. The gap pass follows the highest review rung but never drops.
# An editing round gives each open finding a starting rung and batches
# the round by rung, cheapest first. In round one a finding starts cheap
# when it is mechanical (minor or nit with a proven suggestion), or,
# under the balanced posture, when its Check line would execute (by the
# check command or a contract prefix), so a wrong fix is caught by
# running it; under the economy posture any finding starts cheap once a
# check command gates the round; under the quality posture only
# mechanical ones do. A
# blocker, a security finding, or a finding on a file where the secrets
# or sensitive probe fired never starts cheap. A finding that was
# attempted and is still open climbs one rung above its last attempt,
# and a repair after a failed check gate climbs one rung above the batch
# that broke it. Each attempt is noted on the finding's record. The
# verifier and the filter never change model; arbitration takes the
# strong model, else the reviewer's. With routing fixed, every role
# stays on its own setting. The verify stage takes the addressed ids
# after "--" too, and skips when none follow it.
set -eu

dir=${1:?usage: route-models.sh <state-dir> <stage> [key=value ...] [-- <ids>]}
stage=${2:?usage: route-models.sh <state-dir> <stage> [key=value ...] [-- <ids>]}
shift 2
ctx="$dir/pr-context"
[ -d "$ctx" ] || {
	echo "route-models: no pr-context in $dir, run fetch-pr.sh first" >&2
	exit 1
}

CHEAP=sonnet
LARGE_CODE_LINES=800
SMALL_LINES=300
CLIMB_SLUGS='secrets automation sensitive'
RISK_SLUGS='secrets automation deps debug test-shrink sensitive'
EFFORT_LEVELS='low medium high xhigh'
ECONOMY_EFFORT_CAP=high
EFFORT_CAP=xhigh
AGENTS="$(dirname "$0")/../agents"

routing=auto reviewer=inherit editor=inherit verifier=sonnet strong='' round=1
posture=balanced check='' prefixes=''
double=risky filter=true samples=1
ids='' listed=0
# The run's resolved settings come first; key=value arguments override
# them, which is how the tests drive every branch.
if [ -f "$dir/settings.txt" ]; then
	get() { sh "$(dirname "$0")/setting.sh" "$dir" "$1"; }
	routing=$(get model_routing)
	reviewer=$(get reviewer_model)
	editor=$(get editor_model)
	verifier=$(get verifier_model)
	strong=$(get strong_model)
	posture=$(get cost_posture)
	check=$(get check_command)
	prefixes=$(get contract_commands)
	double=$(get double_review)
	filter=$(get finding_filter)
	samples=$(get review_samples)
fi
while [ $# -gt 0 ]; do
	case "$1" in
	--)
		shift
		ids=$* listed=1
		break
		;;
	*=*)
		key=${1%%=*}
		value=${1#*=}
		case "$value" in '${user_config'*) value='' ;; esac
		case "$key" in
		routing) routing=${value:-auto} ;;
		reviewer) reviewer=${value:-inherit} ;;
		editor) editor=${value:-inherit} ;;
		verifier) verifier=${value:-sonnet} ;;
		strong) strong=$value ;;
		posture) posture=${value:-balanced} ;;
		check) check=$value ;;
		prefixes) prefixes=$value ;;
		double) double=${value:-risky} ;;
		filter) filter=${value:-true} ;;
		samples) samples=${value:-1} ;;
		round) round=${value:-1} ;;
		*)
			echo "route-models: unknown key: $key" >&2
			exit 1
			;;
		esac
		;;
	*)
		echo "route-models: expected key=value, got: $1" >&2
		exit 1
		;;
	esac
	shift
done
case "$routing" in
auto | fixed) ;;
*)
	echo "route-models: routing must be auto or fixed: $routing" >&2
	exit 1
	;;
esac
case "$posture" in
quality | balanced | economy) ;;
*)
	echo "route-models: posture must be quality, balanced, or economy: $posture" >&2
	exit 1
	;;
esac

pinned=${CLAUDE_CODE_EFFORT_LEVEL:+ pinned $CLAUDE_CODE_EFFORT_LEVEL}

emit() {
	# emit <unit> <rung> <model> <effort> <reason> [ids]
	line="route $stage $1 rung $2 model $3 effort $4$pinned reason $5${6:+ ids $6}"
	printf '%s\n' "$line" >>"$ctx/routes.txt"
	echo "$line"
}

skip() {
	# skip <reason>
	line="route $stage all skip reason $1"
	printf '%s\n' "$line" >>"$ctx/routes.txt"
	echo "$line"
}

level_rank() {
	# level_rank <level>: its position in EFFORT_LEVELS, from 0
	i=0
	for l in $EFFORT_LEVELS; do
		[ "$l" = "$1" ] && {
			echo "$i"
			return
		}
		i=$((i + 1))
	done
	echo "route-models: not an effort level: $1" >&2
	exit 1
}

level_at() {
	# level_at <rank>, clamped to low and to the posture's cap
	if [ "$posture" = economy ]; then cap=$(level_rank "$ECONOMY_EFFORT_CAP"); else cap=$(level_rank "$EFFORT_CAP"); fi
	r=$1
	[ "$r" -lt 0 ] && r=0
	[ "$r" -gt "$cap" ] && r=$cap
	set -- $EFFORT_LEVELS
	shift "$r"
	echo "$1"
}

role_effort() {
	# role_effort <agent>: the level its definition declares
	e=$(sed -n '2,/^---$/s/^effort: //p' "$AGENTS/$1.md")
	case " $EFFORT_LEVELS " in
	*" $e "*) echo "$e" ;;
	*)
		echo "route-models: agents/$1.md declares effort '$e', which routing does not use" >&2
		exit 1
		;;
	esac
}

moved() {
	# moved <base level> <signed steps>: the base unless routing is fixed
	if [ "$routing" = fixed ]; then
		echo "$1"
	else
		level_at $(($(level_rank "$1") + $2))
	fi
}

# Every role's own level, read once so a definition the router cannot
# route stops the run here instead of printing a wrong line.
reviewer_effort=$(role_effort reviewer)
editor_effort=$(role_effort editor)
verifier_effort=$(role_effort verifier)
filter_effort=$(role_effort filter)
arbiter_effort=$(role_effort arbiter)

highest() {
	# highest <levels>: the highest of them
	top=low
	for l in $1; do
		[ "$(level_rank "$l")" -gt "$(level_rank "$top")" ] && top=$l
	done
	echo "$top"
}

has_slug() {
	# has_slug <needles> <haystack>: any word of the first list in the second
	for n in $1; do
		for h in $2; do
			[ "$n" = "$h" ] && return 0
		done
	done
	return 1
}

kind=none lines=0 code_lines=0
[ -f "$ctx/class.txt" ] && {
	kind=$(sed -n 's/.* kind \([a-z-]*\).*/\1/p' "$ctx/class.txt")
	lines=$(sed -n 's/.* lines \([0-9]*\).*/\1/p' "$ctx/class.txt")
	code_lines=$(sed -n 's/.* code_lines \([0-9]*\).*/\1/p' "$ctx/class.txt")
}
slugs=''
[ -f "$ctx/probe-slugs.txt" ] && slugs=$(cat "$ctx/probe-slugs.txt")

# The facts for one shard group: its kind, lines, code lines, and the
# probe slugs that fired on its files. Prints "kind lines code_lines slugs".
group_facts() {
	# group_facts <file numbers>
	awk -F '\t' -v nums="$1" -v kinds="$ctx/files-kind.txt" -v probes="$ctx/probe-files.txt" '
	BEGIN {
		n = split(nums, want, " ")
		for (i = 1; i <= n; i++) in_group[want[i]] = 1
		while ((getline line < kinds) > 0) {
			split(line, f, "\t")
			if (!(f[1] in in_group)) continue
			files++; path[f[2]] = 1
			if (f[3] == "docs") docs++
			if (f[3] == "tests") tests++
			if (f[3] == "config") config++
			if (f[3] == "code") { code++; cl += f[4] }
			lines += f[4]
		}
		while ((getline line < probes) > 0) {
			split(line, p, "\t")
			if ((p[2] in path) && !(p[1] in seen)) { seen[p[1]] = 1; s = s " " p[1] }
		}
		kind = "mixed"
		if (code > 0) kind = "code"
		if (files == docs) kind = "docs-only"
		if (files == tests) kind = "tests-only"
		if (files == config) kind = "config-only"
		if (files == 0) kind = "empty"
		printf "%s %d %d%s\n", kind, lines, cl, s
	}'
}

# The reviewer's rung for one unit of the change, and why.
review_rung() {
	# review_rung <kind> <lines> <code_lines> <slugs>; prints "<rung> <reason>"
	if [ "$routing" = fixed ]; then
		echo "base fixed"
		return
	fi
	if [ "$1" = code ] && { [ "${3:-0}" -gt "$LARGE_CODE_LINES" ] || has_slug "$CLIMB_SLUGS" "$4"; }; then
		if [ "${3:-0}" -gt "$LARGE_CODE_LINES" ]; then why=large-code; else why=risky-probe; fi
		if [ -n "$strong" ]; then echo "strong $why"; else echo "base strong-wanted-unset"; fi
		return
	fi
	case "$1" in
	docs-only | config-only)
		if [ "${2:-0}" -lt "$SMALL_LINES" ] && ! has_slug "$RISK_SLUGS" "$4"; then
			echo "cheap $1-small"
			return
		fi
		;;
	esac
	echo "base role-model"
}

# The reviewer's effort for one unit of the change.
review_effort() {
	# review_effort <kind> <lines> <code_lines> <slugs> [group]
	steps=0
	case "$1" in
	docs-only | config-only)
		[ "${2:-0}" -lt "$SMALL_LINES" ] && ! has_slug "$RISK_SLUGS" "$4" && steps=-1
		;;
	esac
	if { [ "$1" = code ] && [ "${3:-0}" -gt "$LARGE_CODE_LINES" ]; } || on_seam "${5:-}"; then
		steps=$((steps + 1))
	fi
	has_slug "$CLIMB_SLUGS" "$4" && steps=$((steps + 1))
	moved "$reviewer_effort" "$steps"
}

on_seam() {
	# on_seam <group>: a coupling crosses out of this shard group
	[ -n "$1" ] && [ -f "$ctx/seams.txt" ] &&
		sed -n 's/.* split across groups \([0-9]*\) and \([0-9]*\) .*/ \1 \2 /p' "$ctx/seams.txt" | grep -q " $1 "
}

model_for() {
	# model_for <rung> <base-model>
	case "$1" in
	cheap) echo "$CHEAP" ;;
	strong) echo "$strong" ;;
	*) echo "$2" ;;
	esac
}

up() {
	# up <rung>: the next rung, capped where the ladder ends
	case "$1" in
	cheap) echo base ;;
	*) if [ -n "$strong" ]; then echo strong; else echo base; fi ;;
	esac
}

last_rung() {
	# last_rung <record>: the rung of the finding's latest attempt, if any
	sed -n 's/^Route: round [0-9]* rung \([a-z]*\) .*/\1/p' "$1" | tail -n 1
}

note_attempt() {
	# note_attempt <id> <rung> <model> <effort> <reason>
	printf 'Route: round %s rung %s model %s effort %s%s reason %s\n' "$round" "$2" "$3" "$4" "$pinned" "$5" |
		sh "$(dirname "$0")/append-note.sh" "$dir" "$1" >/dev/null
}

high_stakes() {
	# high_stakes <record>: a blocker, a security finding, or a secrets or sensitive file
	grep -q '^severity: blocker$' "$1" && return 0
	grep -q '^category: security$' "$1" && return 0
	path=$(sed -n 's/^path: //p' "$1")
	[ -f "$ctx/probe-files.txt" ] && grep -Fqx -e "secrets	$path" -e "sensitive	$path" "$ctx/probe-files.txt"
}

mechanical() {
	# mechanical <record>: a minor or nit finding with a proven suggestion
	grep -Eq '^severity: (minor|nit)$' "$1" && grep -q '^```suggestion$' "$1"
}

contract_runs() {
	# contract_runs <id>: its Check line would execute under the run's policy
	grep -q '^Check: ' "$dir/findings/$1" &&
		sh "$(dirname "$0")/run-contract.sh" --policy "$dir" "$1" "$check" "$prefixes" >/dev/null 2>&1
}

# The editor's effort for one finding: up for stakes and for each
# earlier attempt, down when a proven suggestion carries the fix.
finding_effort() {
	# finding_effort <id>
	record="$dir/findings/$1"
	steps=$(grep -c '^Route: ' "$record" || true)
	high_stakes "$record" && steps=$((steps + 1))
	mechanical "$record" && steps=$((steps - 1))
	moved "$editor_effort" "$steps"
}

# A finding's starting rung for this round, and why. Prints "<rung> <reason>".
finding_rung() {
	# finding_rung <id>
	record="$dir/findings/$1"
	[ -f "$record" ] || {
		echo "route-models: unknown finding: $1" >&2
		exit 1
	}
	if [ "$routing" = fixed ]; then
		echo "base fixed"
		return
	fi
	last=$(last_rung "$record")
	if [ -n "$last" ]; then
		# Attempted before and still open: one rung above the last attempt.
		next=$(up "$last")
		if [ "$next" != "$last" ]; then
			echo "$next escalated"
		elif [ "$last" = base ]; then
			echo "base strong-wanted-unset"
		else
			echo "$next ladder-top"
		fi
		return
	fi
	if [ "$round" -ne 1 ]; then
		echo "base role-model"
		return
	fi
	if high_stakes "$record"; then
		echo "base stakes-floor"
		return
	fi
	if mechanical "$record"; then
		echo "cheap mechanical"
		return
	fi
	if [ "$posture" != quality ] && contract_runs "$1"; then
		echo "cheap contract-first"
		return
	fi
	if [ "$posture" = economy ] && [ -n "$check" ]; then
		echo "cheap gate-first"
		return
	fi
	echo "base role-model"
}

# Print the batches for a set of ids: one line per rung used, cheapest
# first, each as "<rung> <reason> <ids>", noting every attempt.
batches() {
	# batches <ids>; leaves each finding's own rung, reason, and effort in $plan
	plan="$ctx/.route-plan"
	: >"$plan"
	for id in $1; do
		set -- $(finding_rung "$id")
		printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$id" "$(finding_effort "$id")" >>"$plan"
	done
	# A lone cheap finding in a round that also has others rides with them.
	if [ "$(grep -c '^cheap	' "$plan")" -eq 1 ] && grep -qv '^cheap	' "$plan"; then
		sed 's/^cheap	\([a-z-]*\)	/base	\1-alone	/' "$plan" >"$plan.2"
		mv "$plan.2" "$plan"
	fi
	for rung in cheap base strong; do
		grep "^$rung	" "$plan" >/dev/null || continue
		list=$(awk -F '\t' -v r="$rung" '$1 == r { printf "%s%s", (n++ ? " " : ""), $3 }' "$plan")
		reasons=$(awk -F '\t' -v r="$rung" '$1 == r { print $2 }' "$plan" | sort -u)
		case "$(printf '%s\n' "$reasons" | wc -l | tr -d ' ')" in
		1) reason=$reasons ;;
		*) reason=mixed ;;
		esac
		effort=$(highest "$(awk -F '\t' -v r="$rung" '$1 == r { print $4 }' "$plan")")
		printf '%s %s %s %s\n' "$rung" "$reason" "$effort" "$list"
	done
}

case "$stage" in
review)
	if [ -s "$ctx/shards.txt" ] && [ -f "$ctx/files-kind.txt" ]; then
		# One decision per group, on that group's own files.
		[ -f "$ctx/probe-files.txt" ] || : >"$ctx/probe-files.txt"
		while read -r _g gi _l _gl _f nums; do
			facts=$(group_facts "$nums")
			gk=${facts%% *}
			rest=${facts#* }
			gl=${rest%% *}
			rest=${rest#* }
			gc=${rest%% *}
			gs=${rest#"$gc"}
			set -- $(review_rung "$gk" "$gl" "$gc" "$gs")
			emit "group-$gi" "$1" "$(model_for "$1" "$reviewer")" \
				"$(review_effort "$gk" "$gl" "$gc" "$gs" "$gi")" "$2 samples $samples"
		done <"$ctx/shards.txt"
	else
		set -- $(review_rung "$kind" "$lines" "$code_lines" "$slugs")
		emit all "$1" "$(model_for "$1" "$reviewer")" \
			"$(review_effort "$kind" "$lines" "$code_lines" "$slugs")" "$2 samples $samples"
	fi
	;;
gap)
	# Whether to run: always after a sharded review, since each shard saw
	# only its own files; otherwise as double_review says, where risky
	# means a secrets, automation, or sensitive probe fired.
	if [ -s "$ctx/shards.txt" ]; then
		:
	else
		case "$double" in
		always) ;;
		off) skip_gap=double-review-off ;;
		*) has_slug "secrets automation sensitive" "$slugs" || skip_gap=no-risk-signal ;;
		esac
	fi
	if [ -n "${skip_gap:-}" ]; then
		skip "$skip_gap"
		exit 0
	fi
	# The highest rung and effort any review unit used, never below the
	# reviewer's own, and one level up when seams cross the shards.
	rung=base reason=follows-reviewer
	if [ -n "$strong" ] && [ -f "$ctx/routes.txt" ] && grep -q '^route review .* rung strong ' "$ctx/routes.txt"; then
		rung=strong
	fi
	base=$reviewer_effort
	effort=$(highest "$base $(sed -n 's/^route review .* effort \([a-z]*\) .*/\1/p' "$ctx/routes.txt" 2>/dev/null)")
	[ -s "$ctx/seams.txt" ] && effort=$(highest "$effort $(moved "$base" 1)")
	effort=$(moved "$effort" 0)
	[ "$routing" = fixed ] && effort=$base
	emit all "$rung" "$(model_for "$rung" "$reviewer")" "$effort" "$reason"
	;;
filter)
	if [ "$filter" = false ]; then
		skip filter-off
		exit 0
	fi
	emit all base "$verifier" "$(moved "$filter_effort" 0)" role-model
	;;
verify)
	# Each finding one level down when execution or a proven suggestion
	# settles it and one up for stakes; the round takes the highest.
	[ "$listed" -eq 1 ] || {
		echo "route-models: the verify stage needs the addressed finding ids after --" >&2
		exit 1
	}
	if [ -z "$ids" ]; then
		skip nothing-addressed
		exit 0
	fi
	efforts=''
	for id in $ids; do
		record="$dir/findings/$id"
		[ -f "$record" ] || {
			echo "route-models: unknown finding: $id" >&2
			exit 1
		}
		steps=0
		{ grep -q '^```suggestion$' "$record" || contract_runs "$id"; } && steps=-1
		high_stakes "$record" && steps=$((steps + 1))
		efforts="$efforts $(moved "$verifier_effort" "$steps")"
	done
	emit all base "$verifier" "$(highest "$efforts")" role-model
	;;
edit)
	[ -n "$ids" ] || {
		echo "route-models: the edit stage needs the open finding ids after --" >&2
		exit 1
	}
	# Plan first, note afterwards: a note changes what the next read sees.
	lines=$(batches "$ids")
	n=$(printf '%s\n' "$lines" | grep -c .)
	i=0
	printf '%s\n' "$lines" | while read -r rung reason effort list; do
		i=$((i + 1))
		model=$(model_for "$rung" "$editor")
		if [ "$n" -eq 1 ]; then unit=all; else unit="batch-$i"; fi
		for id in $list; do
			note_attempt "$id" "$rung" "$model" "$effort" "$(awk -F '\t' -v i="$id" '$3 == i { print $2 }' "$ctx/.route-plan")"
		done
		emit "$unit" "$rung" "$model" "$effort" "$reason" "$list"
	done
	rm -f "$ctx/.route-plan"
	;;
repair)
	# After a failed check gate: one rung above the batch that broke it,
	# at the effort its findings now call for, the failed attempt counted.
	[ -n "$ids" ] || {
		echo "route-models: the repair stage needs the batch's finding ids after --" >&2
		exit 1
	}
	top=cheap efforts=''
	for id in $ids; do
		record="$dir/findings/$id"
		[ -f "$record" ] || {
			echo "route-models: unknown finding: $id" >&2
			exit 1
		}
		case "$(last_rung "$record")" in
		strong) top=strong ;;
		base) [ "$top" = strong ] || top=base ;;
		esac
		efforts="$efforts $(finding_effort "$id")"
	done
	if [ "$routing" = fixed ]; then
		rung=base reason=fixed
	else
		rung=$(up "$top") reason=gate-failed
	fi
	model=$(model_for "$rung" "$editor")
	effort=$(highest "$efforts")
	for id in $ids; do note_attempt "$id" "$rung" "$model" "$effort" "$reason"; done
	emit all "$rung" "$model" "$effort" "$reason" "$ids"
	;;
arbitrate)
	if [ "$routing" = fixed ]; then
		skip fixed-routing
		exit 0
	fi
	effort=$(moved "$arbiter_effort" 0)
	if [ -n "$strong" ]; then
		emit all strong "$strong" "$effort" arbitration
	else
		emit all base "$reviewer" "$effort" no-strong-model
	fi
	;;
*)
	echo "route-models: unknown stage: $stage" >&2
	exit 1
	;;
esac
