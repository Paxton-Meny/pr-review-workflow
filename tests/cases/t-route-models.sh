#!/bin/sh
# route-models: every rung of the ladder, per stage, with the record kept.
set -eu

dir="$SCRATCH/state"
ctx="$dir/pr-context"
mkdir -p "$ctx" "$dir/findings"
route() { sh "$REPO_ROOT/scripts/route-models.sh" "$dir" "$@"; }
classify() { printf 'classify-change: kind %s files 1 lines %s code_lines %s\n' "$1" "$2" "$3" >"$ctx/class.txt"; }
probes() { printf '%s\n' "$1" >"$ctx/probe-slugs.txt"; }
ARGS='routing=auto reviewer=inherit editor=inherit verifier=sonnet strong='

# A small docs-only change drops; the gap pass still floors at the reviewer.
classify docs-only 120 0
probes ''
[ "$(route review $ARGS)" = "route review all rung cheap model sonnet reason docs-only-small" ]
[ "$(route gap $ARGS)" = "route gap all rung base model inherit reason follows-reviewer" ]

# The same change with a risk signal stays on the reviewer model.
probes 'deps'
[ "$(route review $ARGS)" = "route review all rung base model inherit reason role-model" ]

# Large code climbs when a strong model is set, and says so when none is.
classify code 1200 950
probes 'added'
[ "$(route review $ARGS)" = "route review all rung base model inherit reason strong-wanted-unset" ]
[ "$(route review routing=auto reviewer=inherit strong=opus)" = "route review all rung strong model opus reason large-code" ]
[ "$(route gap routing=auto reviewer=inherit strong=opus)" = "route gap all rung strong model opus reason follows-reviewer" ]

# Size counts code lines only: 1,200 lines of mostly tests is not large code.
classify code 1200 300
probes ''
[ "$(route review routing=auto reviewer=opus strong=opus)" = "route review all rung base model opus reason role-model" ]

# A sensitive probe climbs even on a small change.
classify code 90 90
probes 'sensitive'
[ "$(route review routing=auto strong=opus)" = "route review all rung strong model opus reason risky-probe" ]

# Fixed routing never moves, and placeholders from an unconfigured install count as unset.
[ "$(route review routing=fixed reviewer=inherit strong=opus)" = "route review all rung base model inherit reason fixed" ]
[ "$(route review 'routing=${user_config.model_routing}' 'strong=${user_config.strong_model}')" = "route review all rung base model inherit reason strong-wanted-unset" ]

# The filter and the verifier always take the verifier model.
[ "$(route filter $ARGS)" = "route filter all rung base model sonnet reason role-model" ]
[ "$(route verify routing=auto verifier=inherit)" = "route verify all rung base model inherit reason role-model" ]

# Editing drops only in round one and only when every finding is mechanical.
printf 'id: F001\nstatus: open\nseverity: nit\n---\nbody\n```suggestion\nx\n```\n' >"$dir/findings/F001"
printf 'id: F002\nstatus: open\nseverity: minor\n---\nbody\n```suggestion\ny\n```\n' >"$dir/findings/F002"
printf 'id: F003\nstatus: open\nseverity: major\n---\nbody\n```suggestion\nz\n```\n' >"$dir/findings/F003"
[ "$(route edit $ARGS round=1 -- F001 F002)" = "route edit all rung cheap model sonnet reason mechanical-round-one ids F001 F002" ]
[ "$(route edit $ARGS round=1 -- F001 F003)" = "route edit all rung base model inherit reason role-model ids F001 F003" ]
[ "$(route edit $ARGS round=2 -- F001 F002)" = "route edit all rung base model inherit reason role-model ids F001 F002" ]
[ "$(route edit routing=fixed round=1 -- F001)" = "route edit all rung base model inherit reason fixed ids F001" ]

# Arbitration takes the strong model, else the reviewer's.
[ "$(route arbitrate routing=auto reviewer=inherit strong=opus)" = "route arbitrate all rung strong model opus reason arbitration" ]
[ "$(route arbitrate routing=auto reviewer=inherit)" = "route arbitrate all rung base model inherit reason no-strong-model" ]

# Every decision was recorded, in order.
[ "$(grep -c '^route ' "$ctx/routes.txt")" -eq 18 ]
[ "$(sed -n '1p' "$ctx/routes.txt")" = "route review all rung cheap model sonnet reason docs-only-small" ]

# Refusals: an unknown stage, a bad routing value, an edit without ids, an unknown finding.
for bad in "wat" "review routing=sometimes" "edit $ARGS" "edit $ARGS -- F999"; do
	if route $bad 2>"$SCRATCH/err"; then
		echo "expected refusal of: $bad" >&2
		exit 1
	fi
done
if sh "$REPO_ROOT/scripts/route-models.sh" "$SCRATCH/nope" review 2>"$SCRATCH/err"; then
	echo "expected failure without pr-context" >&2
	exit 1
fi
grep -q "no pr-context" "$SCRATCH/err"
