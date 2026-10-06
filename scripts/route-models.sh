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
# The reviewer climbs for large or sensitive code when a strong model is
# set and drops for a small docs-only or config-only change with no risk
# signal; the gap pass follows the reviewer up but never down; the editor
# drops in round one when every open finding is minor or nit with a
# proven suggestion; the verifier and the filter never move; arbitration
# takes the strong model, else the reviewer's. With routing fixed, every
# role stays on its own setting.
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
	set -- $(review_rung "$kind" "$lines" "$code_lines" "$slugs")
	emit all "$1" "$(model_for "$1" "$reviewer")" "$2"
	;;
gap)
	# Never below the reviewer's own setting, however the review was routed.
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
	rung=base reason=role-model
	if [ "$routing" = fixed ]; then
		reason=fixed
	elif [ "$round" -eq 1 ]; then
		mechanical=1
		for id in $ids; do
			record="$dir/findings/$id"
			[ -f "$record" ] || {
				echo "route-models: unknown finding: $id" >&2
				exit 1
			}
			case "$(sed -n 's/^severity: //p' "$record")" in
			minor | nit) grep -q '^```suggestion$' "$record" || mechanical=0 ;;
			*) mechanical=0 ;;
			esac
		done
		[ "$mechanical" -eq 1 ] && rung=cheap reason=mechanical-round-one
	fi
	emit all "$rung" "$(model_for "$rung" "$editor")" "$reason" "$ids"
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
