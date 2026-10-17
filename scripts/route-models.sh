#!/bin/sh
# Decide which model each role runs on, one line per unit of work.
# Usage: sh scripts/route-models.sh <state-dir> <stage> [key=value ...] [-- <ids>]
#        sh scripts/route-models.sh <state-dir> spawn-effort applied|unapplied
#
# Settings come from the run's resolved settings.txt when there is one;
# key=value arguments override them. Stages: review, gap, filter, edit,
# repair, verify, incremental, arbitrate, and survey, which takes a
# survey directory holding partitions.txt instead of a run's state. Keys,
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
#   route <stage> <unit> rung <rung> model <model> effort <level>[ pinned|unapplied <value>] reason <reason>[ ids ...]
# The model and the effort are two levers moved by different evidence,
# and a signal is paid for once: when a stronger model takes a climb,
# the signal that caused it leaves the effort alone.
# The model is the capability ceiling, so it climbs on depth: a
# secrets, automation, or sensitive probe, or code whose changed files
# reference one another at least the posture's count of times. Effort
# is thoroughness, how much the agent thinks and how many files it
# opens, so it starts at the level the role's agent definition declares
# and moves one level for each breadth signal: up for a wide search
# (large or coupled code when no strong model takes it, a shard group
# on a seam, a gap pass over seams), up for stakes (a secrets,
# automation, or sensitive probe, a blocker or security finding), down
# where a later step checks the work (a minor or nit fix carried by a
# proven suggestion for the editor on a model above the cheap one, an
# executable Check line or proven suggestion for the verifier) or the
# review is small docs or config with no risk. A batch or a verified
# round runs at its highest finding's level. Max is never routed.
# Fixed routing keeps every
# role's own level, under the posture's cap. A set
# CLAUDE_CODE_EFFORT_LEVEL outranks every override, so the line and
# each Route note record it as pinned, and a retry under it climbs the
# model directly.
# The spawn-effort stage records, once per invocation, whether the
# orchestrator's spawn tool takes an effort override. When it does not,
# each agent runs at its definition's level whatever the line routes,
# so the line and each Route note record that level as unapplied, and
# a retry climbs the model directly, as under a pinned level.
# The cost posture is the lean of every decision the change itself does
# not settle, never a pinned value: where code counts as large (economy
# over 1200 changed lines, balanced 800, quality 400), where a change
# counts as small enough to drop (under 500, 300, 150) and which kinds
# may (docs-only and config-only; tests-only too under economy), how far
# effort may climb (xhigh under quality, high otherwise), how readily a fix
# starts cheap (below), and whether a group a stakes probe flagged earns
# one review sample beyond the setting (quality only, never above 3).
# A sharded review gets one line per group, judged on that group's own
# files: it climbs for large code, for coupled code, or for a secrets,
# automation, or sensitive probe whatever the kind, when a strong model
# is set, and drops for a small group of a droppable kind with no risk
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
# attempted and is still open tries again one lever up: the base model
# after a cheap attempt, otherwise more effort on the same model while
# the last attempt ran below the posture's cap (high, xhigh under
# quality), then one rung above it at that effort;
# a repair after a failed check gate does the same for the batch that
# broke it. Each attempt is noted on the finding's record. The
# verifier and the filter never change model; arbitration is the
# verifier on the strong model, else the reviewer's, at high effort.
# With routing fixed, every role stays on its own setting. The verify
# stage takes the addressed ids after "--" too, and skips when none
# follow it. The ci-repair stage, after the pull request's checks
# failed, starts the editor at its own rung one level up in effort
# (finding a cause is a search) and never cheap, and with repeat=1, the
# same failure after a repair, moves one lever up from its last line,
# as a retry does. The conflict stage, for the editor resolving an
# update that stopped on conflicts, is the editor's rung one level up:
# a wrong resolution drops code.
set -eu

dir=${1:?usage: route-models.sh <state-dir> <stage> [key=value ...] [-- <ids>]}
stage=${2:?usage: route-models.sh <state-dir> <stage> [key=value ...] [-- <ids>]}
shift 2
if [ "$stage" = spawn-effort ]; then
	[ -d "$dir" ] || {
		echo "route-models: no ledger at $dir, run init-state.sh first" >&2
		exit 1
	}
	case "${1:-}" in
	applied) echo "route-models: spawn effort applied" ;;
	unapplied) echo "route-models: spawn effort unapplied, each agent runs at its definition's level" ;;
	*)
		echo "route-models: spawn-effort takes applied or unapplied: ${1:-}" >&2
		exit 1
		;;
	esac
	printf '%s\n' "$1" >"$dir/spawn-effort.txt"
	exit 0
fi
if [ "$stage" = survey ]; then
	ctx=$dir
	[ -f "$dir/partitions.txt" ] || {
		echo "route-models: no partitions.txt in $dir, run inventory-repo.sh first" >&2
		exit 1
	}
else
	ctx="$dir/pr-context"
	[ -d "$ctx" ] || {
		echo "route-models: no pr-context in $dir, run fetch-pr.sh first" >&2
		exit 1
	}
fi

CHEAP=sonnet
CLIMB_SLUGS='secrets automation sensitive'
RISK_SLUGS='secrets automation deps debug test-shrink sensitive'
EFFORT_LEVELS='low medium high xhigh'
ARBITRATION_EFFORT=high
MAX_SAMPLES=3
AGENTS="$(dirname "$0")/../agents"

routing=auto reviewer=inherit editor=inherit verifier=sonnet strong='' round=1
posture=balanced check='' prefixes='' repeat=0
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
	# A check that will not run on this author's code gates nothing.
	if ! sh "$(dirname "$0")/author-trust.sh" "$dir" --exec >/dev/null 2>&1; then
		check='' prefixes=''
	fi
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
		repeat) repeat=${value:-0} ;;
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
# The posture's lean: the large-code line, the coupling count that
# makes a change deep, the small-change line and the kinds that may
# drop, the effort cap (xhigh only under quality: the top level buys
# little for its cost), and the extra sample a stakes group earns.
case "$posture" in
economy) large_code_lines=1200 coupled_min=6 small_lines=500 drop_kinds='docs-only config-only tests-only' effort_cap=high extra_sample=0 ;;
balanced) large_code_lines=800 coupled_min=4 small_lines=300 drop_kinds='docs-only config-only' effort_cap=high extra_sample=0 ;;
quality) large_code_lines=400 coupled_min=2 small_lines=150 drop_kinds='docs-only config-only' effort_cap=xhigh extra_sample=1 ;;
*)
	echo "route-models: posture must be quality, balanced, or economy: $posture" >&2
	exit 1
	;;
esac

pinned=${CLAUDE_CODE_EFFORT_LEVEL:+ pinned $CLAUDE_CODE_EFFORT_LEVEL}

emit() {
	# emit <unit> <rung> <model> <effort> <reason> [ids]
	line="route $stage $1 rung $2 model $3 effort $4$held reason $5${6:+ ids $6}"
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
	cap=$(level_rank "$effort_cap")
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
	# moved <base level> <signed steps>: no steps when routing is fixed,
	# and capped either way
	if [ "$routing" = fixed ]; then
		level_at "$(level_rank "$1")"
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
cartographer_effort=$(role_effort cartographer)
assembler_effort=$(role_effort assembler)

# A pinned level outranks the spawn tool; otherwise a spawn tool with
# no effort override leaves the stage's agent at its own level.
held=$pinned
if [ -z "$held" ] && [ "$(cat "$dir/spawn-effort.txt" 2>/dev/null)" = unapplied ]; then
	case "$stage" in
	review | gap | incremental) held=" unapplied $reviewer_effort" ;;
	edit | repair | ci-repair | conflict) held=" unapplied $editor_effort" ;;
	verify | arbitrate) held=" unapplied $verifier_effort" ;;
	filter) held=" unapplied $filter_effort" ;;
	esac
fi

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
couplings=0
[ -f "$ctx/couplings.txt" ] && couplings=$(sed -n 1p "$ctx/couplings.txt")

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

large_code() {
	# large_code <kind> <code_lines>: code over the posture's large-code line
	[ "$1" = code ] && [ "${2:-0}" -gt "$large_code_lines" ]
}

coupled() {
	# coupled <kind> [group]: code whose changed files reference one
	# another at least the posture's count of times, so the judgment
	# spans files; a shard group counts the couplings on its own files
	c=$couplings
	[ -n "${2:-}" ] && [ -f "$ctx/couplings.txt" ] && c=$(sed -n "s/^group $2 //p" "$ctx/couplings.txt")
	[ "$1" = code ] && [ "${c:-0}" -ge "$coupled_min" ]
}

small_drop() {
	# small_drop <kind> <lines> <slugs>: a kind the posture lets drop,
	# under its small-change line, with no risk signal
	has_slug "$1" "$drop_kinds" && [ "${2:-0}" -lt "$small_lines" ] && ! has_slug "$RISK_SLUGS" "$3"
}

# The reviewer's rung for one unit of the change, and why. Stakes climb
# whatever the kind: a token in a config file or a workflow edit is as
# risky as one in code.
review_rung() {
	# review_rung <kind> <lines> <code_lines> <slugs> [group]; prints "<rung> <reason>"
	if [ "$routing" = fixed ]; then
		echo "base fixed"
		return
	fi
	why=''
	if large_code "$1" "$3"; then why=large-code; elif coupled "$1" "${5:-}"; then why=coupled; elif has_slug "$CLIMB_SLUGS" "$4"; then why=risky-probe; fi
	if [ -n "$why" ]; then
		if [ -n "$strong" ]; then echo "strong $why"; else echo "base strong-wanted-unset"; fi
		return
	fi
	if small_drop "$1" "$2" "$4"; then
		echo "cheap $1-small"
		return
	fi
	echo "base role-model"
}

# The reviewer's effort for one unit of the change. Size, coupling,
# and a stakes probe climb the model when a strong one is set and
# differs from the reviewer's, and the effort otherwise, so one signal
# is paid for once; a seam always raises the effort.
review_effort() {
	# review_effort <kind> <lines> <code_lines> <slugs> [group] [rung]
	steps=0
	small_drop "$1" "$2" "$4" && steps=-1
	if [ "${6:-}" != strong ] || [ "$strong" = "$reviewer" ]; then
		if large_code "$1" "$3" || coupled "$1" "${5:-}"; then steps=$((steps + 1)); fi
		has_slug "$CLIMB_SLUGS" "$4" && steps=$((steps + 1))
	fi
	if on_seam "${5:-}"; then
		steps=$((steps + 1))
	fi
	moved "$reviewer_effort" "$steps"
}

# The review samples for one unit: the setting, plus the posture's
# extra sample where a stakes probe fired, never above the manifest's
# maximum and never under fixed routing.
samples_for() {
	# samples_for <slugs>
	s=$samples
	if [ "$routing" = auto ] && has_slug "$CLIMB_SLUGS" "$1"; then
		s=$((s + extra_sample))
		[ "$s" -gt "$MAX_SAMPLES" ] && s=$MAX_SAMPLES
	fi
	echo "$s"
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
	printf 'Route: round %s rung %s model %s effort %s%s reason %s\n' "$round" "$2" "$3" "$4" "$held" "$5" |
		sh "$(dirname "$0")/append-note.sh" "$dir" "$1" >/dev/null
}

header() {
	# header <record>: the record's header lines, never its body
	sed -n '/^---$/q; p' "$1"
}

high_stakes() {
	# high_stakes <record>: a blocker, a security finding, or a secrets or sensitive file
	header "$1" | grep -q '^severity: blocker$' && return 0
	header "$1" | grep -q '^category: security$' && return 0
	path=$(sed -n '/^---$/q; s/^path: //p' "$1")
	[ -f "$ctx/probe-files.txt" ] && grep -Fqx -e "secrets	$path" -e "sensitive	$path" "$ctx/probe-files.txt"
}

mechanical() {
	# mechanical <record>: a minor or nit finding with a proven suggestion
	header "$1" | grep -Eq '^severity: (minor|nit)$' && grep -q '^```suggestion$' "$1"
}

contract_runs() {
	# contract_runs <id>: its Check line would execute under the run's policy
	grep -q '^Check: ' "$dir/findings/$1" &&
		sh "$(dirname "$0")/run-contract.sh" --policy "$dir" "$1" "$check" "$prefixes" >/dev/null 2>&1
}

last_effort() {
	# last_effort <record>: the effort the latest attempt was routed at,
	# the editor's own level for a note written before efforts were
	grep '^Route: ' "$1" | tail -n 1 | sed -n 's/.* effort \([a-z]*\).*/\1/p' | grep . || echo "$editor_effort"
}

# The next attempt after a failed one moves one lever. A cheap attempt
# climbs to the base model: the cheap rung is a round-one bet, and once
# it has lost, more care on that model spends a round the ladder needs.
# Otherwise, while the last attempt ran below the posture's cap it was
# the effort: the same model with more care recovers most failures for
# a fraction of a stronger model's price. At the cap more effort has
# little headroom left and the model climbs, at the effort already
# reached. A pinned CLAUDE_CODE_EFFORT_LEVEL or an unapplied effort
# makes the effort lever inert, so the model climbs at once. Prints
# "<rung> <effort> <reason>".
next_attempt() {
	# next_attempt <last rung> <last effort>
	if [ "$1" = cheap ]; then
		echo "base $(moved "$2" 0) escalated"
		return
	fi
	if [ -z "$held" ] && [ "$(level_rank "$2")" -lt "$(level_rank "$effort_cap")" ]; then
		echo "$1 $(moved "$2" 1) more-effort"
		return
	fi
	e=$(moved "$2" 0)
	next=$(up "$1")
	if [ "$next" != "$1" ]; then
		echo "$next $e escalated"
	elif [ "$1" = base ]; then
		echo "base $e strong-wanted-unset"
	else
		echo "$1 $e ladder-top"
	fi
}

# A finding's rung and effort for this round, and why. A first attempt
# starts at the editor's level, one up for stakes and one down when a
# proven suggestion carries the fix, unless the cheap model already
# takes that discount: a signal is paid once, across both levers.
# Prints "<rung> <reason> <effort>".
finding_plan() {
	# finding_plan <id>
	record="$dir/findings/$1"
	[ -f "$record" ] || {
		echo "route-models: unknown finding: $1" >&2
		exit 1
	}
	if [ "$routing" = fixed ]; then
		echo "base fixed $(moved "$editor_effort" 0)"
		return
	fi
	last=$(last_rung "$record")
	if [ -n "$last" ]; then
		set -- $(next_attempt "$last" "$(last_effort "$record")")
		echo "$1 $3 $2"
		return
	fi
	steps=0
	high_stakes "$record" && steps=1
	mechanical "$record" && steps=$((steps - 1))
	effort=$(moved "$editor_effort" "$steps")
	if [ "$round" -ne 1 ]; then
		echo "base role-model $effort"
	elif high_stakes "$record"; then
		echo "base stakes-floor $effort"
	elif mechanical "$record"; then
		echo "cheap mechanical $(moved "$editor_effort" 0)"
	elif [ "$posture" != quality ] && contract_runs "$1"; then
		echo "cheap contract-first $effort"
	elif [ "$posture" = economy ] && [ -n "$check" ]; then
		echo "cheap gate-first $effort"
	else
		echo "base role-model $effort"
	fi
}

# Print the batches for a set of ids: one line per rung used, cheapest
# first, each as "<rung> <reason> <ids>", noting every attempt.
batches() {
	# batches <ids>; leaves each finding's own rung, reason, and effort in $plan
	plan="$ctx/.route-plan"
	: >"$plan"
	for id in $1; do
		set -- $(finding_plan "$id")
		printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$id" "$3" >>"$plan"
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
			set -- $(review_rung "$gk" "$gl" "$gc" "$gs" "$gi")
			emit "group-$gi" "$1" "$(model_for "$1" "$reviewer")" \
				"$(review_effort "$gk" "$gl" "$gc" "$gs" "$gi" "$1")" "$2 samples $(samples_for "$gs")"
		done <"$ctx/shards.txt"
	else
		set -- $(review_rung "$kind" "$lines" "$code_lines" "$slugs")
		emit all "$1" "$(model_for "$1" "$reviewer")" \
			"$(review_effort "$kind" "$lines" "$code_lines" "$slugs" "" "$1")" "$2 samples $(samples_for "$slugs")"
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
	[ "$routing" = fixed ] && effort=$(moved "$base" 0)
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
	# After a failed check gate: the batch that broke it tries again one
	# lever up, more effort below the posture's cap and a rung above it.
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
		efforts="$efforts $(last_effort "$record")"
	done
	if [ "$routing" = fixed ]; then
		rung=base effort=$(moved "$editor_effort" 0) reason=fixed
	else
		set -- $(next_attempt "$top" "$(highest "$efforts")")
		rung=$1 effort=$2 reason=gate-failed
	fi
	model=$(model_for "$rung" "$editor")
	for id in $ids; do note_attempt "$id" "$rung" "$model" "$effort" "$reason"; done
	emit all "$rung" "$model" "$effort" "$reason" "$ids"
	;;
ci-repair)
	# After failing checks: never cheap, one level more effort than the
	# editor's own for a fresh failure, and one lever up from the last
	# repair when the same failure followed it.
	if [ "$routing" = fixed ]; then
		emit all base "$editor" "$(moved "$editor_effort" 0)" fixed
		exit 0
	fi
	last=$(grep '^route ci-repair ' "$ctx/routes.txt" 2>/dev/null | grep -v ' skip ' | tail -n 1 || true)
	if [ "$repeat" = 1 ] && [ -n "$last" ]; then
		set -- $(next_attempt "$(printf '%s\n' "$last" | sed 's/.* rung \([a-z]*\) .*/\1/')" "$(printf '%s\n' "$last" | sed 's/.* effort \([a-z]*\).*/\1/')")
		emit all "$1" "$(model_for "$1" "$editor")" "$2" ci-repeat
	else
		emit all base "$editor" "$(moved "$editor_effort" 1)" ci-failed
	fi
	;;
conflict)
	# Resolving an update that stopped on conflicts: never cheap, one
	# level more effort than the editor's own, since a wrong resolution
	# drops code.
	if [ "$routing" = fixed ]; then
		emit all base "$editor" "$(moved "$editor_effort" 0)" fixed
	else
		emit all base "$editor" "$(moved "$editor_effort" 1)" conflict
	fi
	;;
survey)
	# Setup's reading of a repository: one cheap cartographer per planned
	# partition that has no record yet, a level up where the partition
	# holds sensitive code, and one assembler on the session model to
	# draft the map. A partition already recorded prints a skip line, so
	# the same call plans the first reading and the retry of whatever a
	# reader left unrecorded, at the same level.
	if ! grep -q '^partition ' "$dir/partitions.txt"; then
		skip no-partitions
		exit 0
	fi
	while read -r _p pid _l _n _f _m _d _k _s sens _rest; do
		if [ -f "$dir/records/$pid.txt" ]; then
			line="route $stage cartographer-$pid skip reason partition-recorded"
			printf '%s\n' "$line" >>"$ctx/routes.txt"
			echo "$line"
			continue
		fi
		steps=0 reason=partition-read
		[ "$sens" = yes ] && steps=1 reason=partition-read-sensitive
		emit "cartographer-$pid" cheap "$CHEAP" "$(moved "$cartographer_effort" "$steps")" "$reason"
	done <"$dir/partitions.txt"
	emit assembler base inherit "$(moved "$assembler_effort" 0)" synthesis
	;;
incremental)
	# The review of files a round changed that no finding names: the
	# reviewer's own model and level, since nothing has been judged yet.
	emit all base "$reviewer" "$(moved "$reviewer_effort" 0)" role-model
	;;
arbitrate)
	if [ "$routing" = fixed ]; then
		skip fixed-routing
		exit 0
	fi
	effort=$(moved "$ARBITRATION_EFFORT" 0)
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
