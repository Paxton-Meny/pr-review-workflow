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
[ "$(route edit $ARGS round=1 -- F001 F002)" = "route edit all rung cheap model sonnet reason mechanical ids F001 F002" ]
[ "$(route edit $ARGS round=1 -- F001 F003)" = "route edit all rung base model inherit reason mixed ids F001 F003" ]
[ "$(route edit $ARGS round=2 -- F001 F002)" = "route edit all rung base model inherit reason mixed ids F001 F002" ]
[ "$(route edit routing=fixed round=1 -- F001)" = "route edit all rung base model inherit reason fixed ids F001" ]

# Each attempt is noted on the record.
grep -q '^Route: round 1 rung cheap model sonnet reason mechanical$' "$dir/findings/F001"
[ "$(grep -c '^Route: ' "$dir/findings/F001")" -eq 4 ]

# A finding attempted and still open climbs one rung; the top of the ladder holds.
printf 'id: F005\nstatus: open\nseverity: major\n---\nbody\nRoute: round 1 rung cheap model sonnet reason contract-first\n' >"$dir/findings/F005"
printf 'id: F006\nstatus: open\nseverity: major\n---\nbody\nRoute: round 1 rung base model inherit reason role-model\n' >"$dir/findings/F006"
[ "$(route edit $ARGS round=2 -- F005 F006)" = "route edit all rung base model inherit reason mixed ids F005 F006" ]
grep -q '^Route: round 2 rung base model inherit reason escalated$' "$dir/findings/F005"
grep -q '^Route: round 2 rung base model inherit reason strong-wanted-unset$' "$dir/findings/F006"
[ "$(route edit routing=auto strong=opus round=3 -- F006)" = "route edit all rung strong model opus reason escalated ids F006" ]
[ "$(route edit routing=auto strong=opus round=4 -- F006)" = "route edit all rung strong model opus reason ladder-top ids F006" ]

# A repair after a failed check gate climbs above the batch that broke it.
printf 'id: F007\nstatus: open\nseverity: minor\n---\nbody\nRoute: round 1 rung cheap model sonnet reason mechanical\n' >"$dir/findings/F007"
[ "$(route repair $ARGS round=1 -- F007)" = "route repair all rung base model inherit reason gate-failed ids F007" ]
grep -q '^Route: round 1 rung base model inherit reason gate-failed$' "$dir/findings/F007"

# Cheap-first: a contract-backed finding starts cheap when its Check line would execute.
mkdir -p "$dir/worktree"
fresh() {
	printf 'id: F008\nstatus: open\nseverity: major\ncategory: correctness\npath: src/a.py\n---\nbody\nCheck: make check -k a\nResolution: x.\n' >"$dir/findings/F008"
	printf 'id: F009\nstatus: open\nseverity: major\ncategory: correctness\npath: src/b.py\n---\nbody\nCheck: go test ./b\nResolution: x.\n' >"$dir/findings/F009"
	printf 'id: F010\nstatus: open\nseverity: major\ncategory: correctness\npath: src/c.py\n---\nbody\nResolution: x.\n' >"$dir/findings/F010"
}
fresh
[ "$(route edit $ARGS 'check=make check' round=1 -- F008 F009 F010)" = "route edit all rung base model inherit reason mixed ids F008 F009 F010" ]
grep -q 'reason contract-first-alone$' "$dir/findings/F008"
fresh
[ "$(route edit $ARGS 'check=make check' 'prefixes=go test' round=1 -- F008 F009 F010)" = "route edit batch-1 rung cheap model sonnet reason contract-first ids F008 F009
route edit batch-2 rung base model inherit reason role-model ids F010" ]
fresh
[ "$(route edit $ARGS round=1 -- F008 F009)" = "route edit all rung base model inherit reason role-model ids F008 F009" ]
fresh
[ "$(route edit $ARGS posture=quality 'check=make check' 'prefixes=go test' round=1 -- F008 F009)" = "route edit all rung base model inherit reason role-model ids F008 F009" ]
fresh
[ "$(route edit $ARGS posture=economy 'check=make check' round=1 -- F008 F010)" = "route edit all rung cheap model sonnet reason mixed ids F008 F010" ]
grep -q 'reason gate-first$' "$dir/findings/F010"

# Floors: a blocker, a security finding, or a sensitive file never starts cheap.
printf 'id: F011\nstatus: open\nseverity: blocker\ncategory: correctness\npath: src/d.py\n---\nbody\nCheck: make check\n' >"$dir/findings/F011"
printf 'id: F012\nstatus: open\nseverity: minor\ncategory: security\npath: src/e.py\n---\nbody\n```suggestion\nz\n```\n' >"$dir/findings/F012"
printf 'id: F013\nstatus: open\nseverity: nit\ncategory: antipatterns\npath: src/auth.py\n---\nbody\n```suggestion\nz\n```\n' >"$dir/findings/F013"
printf 'sensitive\tsrc/auth.py\n' >"$ctx/probe-files.txt"
[ "$(route edit $ARGS posture=economy 'check=make check' round=1 -- F011 F012 F013)" = "route edit all rung base model inherit reason stakes-floor ids F011 F012 F013" ]
if route edit $ARGS posture=cheapest round=1 -- F001 2>"$SCRATCH/err"; then
	echo "expected refusal of an unknown posture" >&2
	exit 1
fi
rm -f "$ctx/probe-files.txt"

# A mixed round splits into a mechanical batch first and the rest, when both hold two findings.
printf 'id: F001\nstatus: open\nseverity: nit\n---\nbody\n```suggestion\nx\n```\n' >"$dir/findings/F001"
printf 'id: F002\nstatus: open\nseverity: minor\n---\nbody\n```suggestion\ny\n```\n' >"$dir/findings/F002"
printf 'id: F003\nstatus: open\nseverity: major\n---\nbody\n```suggestion\nz\n```\n' >"$dir/findings/F003"
printf 'id: F004\nstatus: open\nseverity: major\n---\nbody\n' >"$dir/findings/F004"
[ "$(route edit $ARGS round=1 -- F003 F001 F004 F002)" = "route edit batch-1 rung cheap model sonnet reason mechanical ids F001 F002
route edit batch-2 rung base model inherit reason role-model ids F003 F004" ]
[ "$(route edit $ARGS round=2 -- F003 F001 F004 F002)" = "route edit all rung base model inherit reason mixed ids F003 F001 F004 F002" ]

# A sharded review is routed group by group, on each group's own files.
printf '001\tdocs/a.md\tdocs\t40\n002\tdocs/b.md\tdocs\t30\n003\tsrc/auth.py\tcode\t120\n004\tsrc/util.py\tcode\t60\n' >"$ctx/files-kind.txt"
printf 'group 1 lines 70 files 001 002\ngroup 2 lines 180 files 003 004\n' >"$ctx/shards.txt"
printf 'sensitive\tsrc/auth.py\nadded\tdocs/b.md\n' >"$ctx/probe-files.txt"
classify code 250 180
[ "$(route review routing=auto reviewer=inherit strong=opus)" = "route review group-1 rung cheap model sonnet reason docs-only-small
route review group-2 rung strong model opus reason risky-probe" ]
[ "$(route gap routing=auto reviewer=inherit strong=opus)" = "route gap all rung strong model opus reason follows-reviewer" ]
printf 'deps\tdocs/a.md\n' >"$ctx/probe-files.txt"
[ "$(route review $ARGS)" = "route review group-1 rung base model inherit reason role-model
route review group-2 rung base model inherit reason role-model" ]
rm -f "$ctx/shards.txt"

# Arbitration takes the strong model, else the reviewer's.
[ "$(route arbitrate routing=auto reviewer=inherit strong=opus)" = "route arbitrate all rung strong model opus reason arbitration" ]
[ "$(route arbitrate routing=auto reviewer=inherit)" = "route arbitrate all rung base model inherit reason no-strong-model" ]

# Every decision was recorded, in order.
[ "$(grep -c '^route ' "$ctx/routes.txt")" -eq 37 ]
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
