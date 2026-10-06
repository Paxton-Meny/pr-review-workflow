#!/bin/sh
# Decide which model each role runs on, one line per unit of work.
# Usage: sh scripts/route-models.sh <state-dir> <stage> [key=value ...] [-- <ids>]
#
# Stages: review, gap, filter, edit, verify, arbitrate. Keys, each with
# its manifest default: routing (auto), reviewer (inherit), editor
# (inherit), verifier (sonnet), strong (empty), round (1). A value that
# is still a literal ${user_config...} placeholder, as on an install with
# no saved configuration, counts as unset. For the edit stage the open
# finding ids follow a lone "--".
#
# Every decision is a rung on one ladder: cheap (sonnet), base (the
# role's own setting), strong (the strong model). Each printed line is
# label-value, is appended to pr-context/routes.txt, and names the model
# the orchestrator passes as the override, "inherit" included:
#   route <stage> <unit> rung <rung> model <model> reason <reason>[ ids ...]
# A sharded review gets one line per group, judged on that group's own
# files: it climbs for large or sensitive code when a strong model is
# set and drops for a small docs-only or config-only group with no risk
# signal. The gap pass follows the highest review rung but never drops.
# An editing round in round one splits into a mechanical batch (minor or
# nit findings with a proven suggestion, on the cheap rung) and the rest,
# when both have at least two findings; otherwise it is one batch, cheap
# only when every finding is mechanical. The verifier and the filter
# never move; arbitration takes the strong model, else the reviewer's.
# With routing fixed, every role stays on its own setting.
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

routing=auto reviewer=inherit editor=inherit verifier=sonnet strong='' round=1
ids=''
while [ $# -gt 0 ]; do
	case "$1" in
	--)
		shift
		ids=$*
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

emit() {
	# emit <unit> <rung> <model> <reason> [ids]
	line="route $stage $1 rung $2 model $3 reason $4${5:+ ids $5}"
	printf '%s\n' "$line" >>"$ctx/routes.txt"
	echo "$line"
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

model_for() {
	# model_for <rung> <base-model>
	case "$1" in
	cheap) echo "$CHEAP" ;;
	strong) echo "$strong" ;;
	*) echo "$2" ;;
	esac
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
			emit "group-$gi" "$1" "$(model_for "$1" "$reviewer")" "$2"
		done <"$ctx/shards.txt"
	else
		set -- $(review_rung "$kind" "$lines" "$code_lines" "$slugs")
		emit all "$1" "$(model_for "$1" "$reviewer")" "$2"
	fi
	;;
gap)
	# The highest rung any review unit used, never below the reviewer's own setting.
	rung=base reason=follows-reviewer
	if [ -f "$ctx/routes.txt" ] && grep -q '^route review .* rung strong ' "$ctx/routes.txt"; then
		rung=strong
	fi
	emit all "$rung" "$(model_for "$rung" "$reviewer")" "$reason"
	;;
filter | verify)
	emit all base "$verifier" role-model
	;;
edit)
	[ -n "$ids" ] || {
		echo "route-models: the edit stage needs the open finding ids after --" >&2
		exit 1
	}
	mech='' rest='' nmech=0 nrest=0
	for id in $ids; do
		record="$dir/findings/$id"
		[ -f "$record" ] || {
			echo "route-models: unknown finding: $id" >&2
			exit 1
		}
		mechanical=0
		case "$(sed -n 's/^severity: //p' "$record")" in
		minor | nit) grep -q '^```suggestion$' "$record" && mechanical=1 ;;
		esac
		if [ "$mechanical" -eq 1 ]; then
			mech="$mech $id"
			nmech=$((nmech + 1))
		else
			rest="$rest $id"
			nrest=$((nrest + 1))
		fi
	done
	mech=${mech# }
	rest=${rest# }
	if [ "$routing" = fixed ]; then
		emit all base "$editor" fixed "$ids"
	elif [ "$round" -ne 1 ]; then
		# Never route down after round one.
		emit all base "$editor" role-model "$ids"
	elif [ "$nrest" -eq 0 ]; then
		emit all cheap "$CHEAP" mechanical-round-one "$ids"
	elif [ "$nmech" -ge 2 ]; then
		# Two batches, the mechanical one first: run them in order, never together.
		emit batch-1 cheap "$CHEAP" mechanical-round-one "$mech"
		emit batch-2 base "$editor" role-model "$rest"
	else
		emit all base "$editor" role-model "$ids"
	fi
	;;
arbitrate)
	if [ -n "$strong" ]; then
		emit all strong "$strong" arbitration
	else
		emit all base "$reviewer" no-strong-model
	fi
	;;
*)
	echo "route-models: unknown stage: $stage" >&2
	exit 1
	;;
esac
