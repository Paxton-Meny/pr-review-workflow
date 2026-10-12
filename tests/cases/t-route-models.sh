#!/bin/sh
# route-models: every rung of the ladder and every effort move, per stage,
# with the record kept.
set -eu
unset CLAUDE_CODE_EFFORT_LEVEL

dir="$SCRATCH/state"
ctx="$dir/pr-context"
mkdir -p "$ctx" "$dir/findings"
route() { sh "$REPO_ROOT/scripts/route-models.sh" "$dir" "$@"; }
classify() { printf 'classify-change: kind %s files 1 lines %s code_lines %s\n' "$1" "$2" "$3" >"$ctx/class.txt"; }
probes() { printf '%s\n' "$1" >"$ctx/probe-slugs.txt"; }
ARGS='routing=auto reviewer=inherit editor=inherit verifier=sonnet strong='

# A small docs-only change drops; the gap pass still floors at the reviewer,
# and climbs a level when seams cross the shards.
classify docs-only 120 0
probes ''
[ "$(route review $ARGS)" = "route review all rung cheap model sonnet effort medium reason docs-only-small samples 1" ]
[ "$(route gap $ARGS double=always)" = "route gap all rung base model inherit effort high reason follows-reviewer" ]
printf 'a.py and b.py split across groups 1 and 2 (shared name: parse)\n' >"$ctx/seams.txt"
[ "$(route gap $ARGS double=always)" = "route gap all rung base model inherit effort high reason follows-reviewer" ]
[ "$(route gap routing=fixed double=always)" = "route gap all rung base model inherit effort high reason follows-reviewer" ]
rm "$ctx/seams.txt"

# The same change with a risk signal stays on the reviewer model.
probes 'deps'
[ "$(route review $ARGS)" = "route review all rung base model inherit effort high reason role-model samples 1" ]

# Large code climbs when a strong model is set, and says so when none is.
classify code 1200 950
probes 'added'
[ "$(route review $ARGS)" = "route review all rung base model inherit effort high reason strong-wanted-unset samples 1" ]
[ "$(route review routing=auto reviewer=inherit strong=opus)" = "route review all rung strong model opus effort high reason large-code samples 1" ]
[ "$(route review routing=auto reviewer=opus strong=opus)" = "route review all rung strong model opus effort high reason large-code samples 1" ]
[ "$(route gap routing=auto reviewer=inherit strong=opus double=always)" = "route gap all rung strong model opus effort high reason follows-reviewer" ]

# Size counts code lines only: 1,200 lines of mostly tests is not large code.
classify code 1200 300
probes ''
[ "$(route review routing=auto reviewer=opus strong=opus)" = "route review all rung base model opus effort high reason role-model samples 1" ]

# A sensitive probe climbs even on a small change; economy caps effort at high.
classify code 90 90
probes 'sensitive'
[ "$(route review routing=auto strong=opus)" = "route review all rung strong model opus effort high reason risky-probe samples 1" ]
[ "$(route review routing=auto strong=opus posture=economy)" = "route review all rung strong model opus effort high reason risky-probe samples 1" ]

# A pinned environment level outranks every override, so the line and
# every Route note record it, and a retry under it climbs the model
# rather than pulling an effort lever that does nothing.
[ "$(CLAUDE_CODE_EFFORT_LEVEL=max route review routing=auto strong=opus)" = "route review all rung strong model opus effort high pinned max reason risky-probe samples 1" ]
printf 'id: F015\nstatus: open\nseverity: major\n---\nbody\n' >"$dir/findings/F015"
[ "$(CLAUDE_CODE_EFFORT_LEVEL=low route edit $ARGS round=1 -- F015)" = "route edit all rung base model inherit effort medium pinned low reason role-model ids F015" ]
[ "$(CLAUDE_CODE_EFFORT_LEVEL=low route repair $ARGS round=1 -- F015)" = "route repair all rung base model inherit effort medium pinned low reason gate-failed ids F015" ]
[ "$(grep -c '^Route: round 1 rung base model inherit effort [a-z]* pinned low reason ' "$dir/findings/F015")" -eq 2 ]
printf 'id: F016\nstatus: open\nseverity: major\n---\nbody\nRoute: round 1 rung base model inherit effort medium pinned low reason role-model\n' >"$dir/findings/F016"
[ "$(CLAUDE_CODE_EFFORT_LEVEL=low route edit routing=auto strong=opus round=2 -- F016)" = "route edit all rung strong model opus effort medium pinned low reason escalated ids F016" ]

# Fixed routing never moves, and placeholders from an unconfigured install count as unset.
[ "$(route review routing=fixed reviewer=inherit strong=opus)" = "route review all rung base model inherit effort high reason fixed samples 1" ]
[ "$(route review 'routing=${user_config.model_routing}' 'strong=${user_config.strong_model}')" = "route review all rung base model inherit effort high reason strong-wanted-unset samples 1" ]

# The filter always takes the verifier model at its own level.
[ "$(route filter $ARGS)" = "route filter all rung base model sonnet effort low reason role-model" ]

# Editing drops only in round one and only when every finding is mechanical.
printf 'id: F001\nstatus: open\nseverity: nit\n---\nbody\n```suggestion\nx\n```\n' >"$dir/findings/F001"
printf 'id: F002\nstatus: open\nseverity: minor\n---\nbody\n```suggestion\ny\n```\n' >"$dir/findings/F002"
printf 'id: F003\nstatus: open\nseverity: major\n---\nbody\n```suggestion\nz\n```\n' >"$dir/findings/F003"
[ "$(route edit $ARGS round=1 -- F001 F002)" = "route edit all rung cheap model sonnet effort low reason mechanical ids F001 F002" ]
[ "$(route edit $ARGS round=1 -- F001 F003)" = "route edit all rung base model inherit effort medium reason mixed ids F001 F003" ]
[ "$(route edit $ARGS round=2 -- F001 F002)" = "route edit all rung base model inherit effort high reason mixed ids F001 F002" ]
[ "$(route edit routing=fixed round=1 -- F001)" = "route edit all rung base model inherit effort medium reason fixed ids F001" ]

# Each attempt is noted on the record.
grep -q '^Route: round 1 rung cheap model sonnet effort low reason mechanical$' "$dir/findings/F001"
[ "$(grep -c '^Route: ' "$dir/findings/F001")" -eq 4 ]

# A finding attempted and still open moves one lever: the base model
# after a cheap attempt, otherwise more effort on the same model while
# the editor has headroom, then one rung up at that effort, until the
# top of the ladder holds.
printf 'id: F005\nstatus: open\nseverity: major\n---\nbody\nRoute: round 1 rung cheap model sonnet reason contract-first\n' >"$dir/findings/F005"
printf 'id: F006\nstatus: open\nseverity: major\n---\nbody\nRoute: round 1 rung base model inherit reason role-model\n' >"$dir/findings/F006"
[ "$(route edit $ARGS round=2 -- F005 F006)" = "route edit all rung base model inherit effort high reason mixed ids F005 F006" ]
grep -q '^Route: round 2 rung base model inherit effort high reason escalated$' "$dir/findings/F005"
grep -q '^Route: round 2 rung base model inherit effort high reason more-effort$' "$dir/findings/F006"
[ "$(route edit routing=auto strong=opus round=3 -- F006)" = "route edit all rung strong model opus effort high reason escalated ids F006" ]
[ "$(route edit routing=auto strong=opus round=4 -- F006)" = "route edit all rung strong model opus effort high reason ladder-top ids F006" ]

# A repair after a failed check gate moves the batch that broke it one
# lever up as well: here the base model, since the cheap attempt lost its bet.
printf 'id: F007\nstatus: open\nseverity: minor\n---\nbody\nRoute: round 1 rung cheap model sonnet reason mechanical\n' >"$dir/findings/F007"
[ "$(route repair $ARGS round=1 -- F007)" = "route repair all rung base model inherit effort medium reason gate-failed ids F007" ]
grep -q '^Route: round 1 rung base model inherit effort medium reason gate-failed$' "$dir/findings/F007"

# Cheap-first: a contract-backed finding starts cheap when its Check line would execute.
mkdir -p "$dir/worktree"
fresh() {
	printf 'id: F008\nstatus: open\nseverity: major\ncategory: correctness\npath: src/a.py\n---\nbody\nCheck: make check -k a\nResolution: x.\n' >"$dir/findings/F008"
	printf 'id: F009\nstatus: open\nseverity: major\ncategory: correctness\npath: src/b.py\n---\nbody\nCheck: go test ./b\nResolution: x.\n' >"$dir/findings/F009"
	printf 'id: F010\nstatus: open\nseverity: major\ncategory: correctness\npath: src/c.py\n---\nbody\nResolution: x.\n' >"$dir/findings/F010"
}
fresh
[ "$(route edit $ARGS 'check=make check' round=1 -- F008 F009 F010)" = "route edit all rung base model inherit effort medium reason mixed ids F008 F009 F010" ]
grep -q 'reason contract-first-alone$' "$dir/findings/F008"
fresh
[ "$(route edit $ARGS 'check=make check' 'prefixes=go test' round=1 -- F008 F009 F010)" = "route edit batch-1 rung cheap model sonnet effort medium reason contract-first ids F008 F009
route edit batch-2 rung base model inherit effort medium reason role-model ids F010" ]
fresh
[ "$(route edit $ARGS round=1 -- F008 F009)" = "route edit all rung base model inherit effort medium reason role-model ids F008 F009" ]
fresh
[ "$(route edit $ARGS posture=quality 'check=make check' 'prefixes=go test' round=1 -- F008 F009)" = "route edit all rung base model inherit effort medium reason role-model ids F008 F009" ]
fresh
[ "$(route edit $ARGS posture=economy 'check=make check' round=1 -- F008 F010)" = "route edit all rung cheap model sonnet effort medium reason mixed ids F008 F010" ]
grep -q 'reason gate-first$' "$dir/findings/F010"

# Floors: a blocker, a security finding, or a sensitive file never starts
# cheap, and each raises the effort a level; a proven suggestion lowers it.
printf 'id: F011\nstatus: open\nseverity: blocker\ncategory: correctness\npath: src/d.py\n---\nbody\nCheck: make check\n' >"$dir/findings/F011"
printf 'id: F012\nstatus: open\nseverity: minor\ncategory: security\npath: src/e.py\n---\nbody\n```suggestion\nz\n```\n' >"$dir/findings/F012"
printf 'id: F013\nstatus: open\nseverity: nit\ncategory: antipatterns\npath: src/auth.py\n---\nbody\n```suggestion\nz\n```\n' >"$dir/findings/F013"
printf 'sensitive\tsrc/auth.py\n' >"$ctx/probe-files.txt"
[ "$(route edit $ARGS posture=economy 'check=make check' round=1 -- F011 F012 F013)" = "route edit all rung base model inherit effort high reason stakes-floor ids F011 F012 F013" ]
printf 'id: F012\nstatus: open\nseverity: minor\ncategory: security\npath: src/e.py\n---\nbody\n```suggestion\nz\n```\n' >"$dir/findings/F012"
[ "$(route edit $ARGS round=1 -- F012)" = "route edit all rung base model inherit effort medium reason stakes-floor ids F012" ]
if route edit $ARGS posture=cheapest round=1 -- F001 2>"$SCRATCH/err"; then
	echo "expected refusal of an unknown posture" >&2
	exit 1
fi
# A flagged path is matched literally, whatever characters it holds.
for p in 'app/(auth)/login/route.ts' 'src/routes/+page.server.ts' 'pages/api/[id].ts'; do
	printf 'sensitive\t%s\n' "$p" >"$ctx/probe-files.txt"
	printf 'id: F014\nstatus: open\nseverity: major\ncategory: correctness\npath: %s\n---\nbody\n' "$p" >"$dir/findings/F014"
	[ "$(route edit $ARGS posture=economy 'check=make check' round=1 -- F014)" = "route edit all rung base model inherit effort high reason stakes-floor ids F014" ]
done
rm -f "$ctx/probe-files.txt"

# A mixed round splits into a mechanical batch first and the rest, when both hold two findings.
printf 'id: F001\nstatus: open\nseverity: nit\n---\nbody\n```suggestion\nx\n```\n' >"$dir/findings/F001"
printf 'id: F002\nstatus: open\nseverity: minor\n---\nbody\n```suggestion\ny\n```\n' >"$dir/findings/F002"
printf 'id: F003\nstatus: open\nseverity: major\n---\nbody\n```suggestion\nz\n```\n' >"$dir/findings/F003"
printf 'id: F004\nstatus: open\nseverity: major\n---\nbody\n' >"$dir/findings/F004"
[ "$(route edit $ARGS round=1 -- F003 F001 F004 F002)" = "route edit batch-1 rung cheap model sonnet effort low reason mechanical ids F001 F002
route edit batch-2 rung base model inherit effort medium reason role-model ids F003 F004" ]
[ "$(route edit $ARGS round=2 -- F003 F001 F004 F002)" = "route edit all rung base model inherit effort high reason mixed ids F003 F001 F004 F002" ]

# A sharded review is routed group by group, on each group's own files.
printf '001\tdocs/a.md\tdocs\t40\n002\tdocs/b.md\tdocs\t30\n003\tsrc/auth.py\tcode\t120\n004\tsrc/util.py\tcode\t60\n' >"$ctx/files-kind.txt"
printf 'group 1 lines 70 files 001 002\ngroup 2 lines 180 files 003 004\n' >"$ctx/shards.txt"
printf 'sensitive\tsrc/auth.py\nadded\tdocs/b.md\n' >"$ctx/probe-files.txt"
classify code 250 180
[ "$(route review routing=auto reviewer=inherit strong=opus)" = "route review group-1 rung cheap model sonnet effort medium reason docs-only-small samples 1
route review group-2 rung strong model opus effort high reason risky-probe samples 1" ]
[ "$(route gap routing=auto reviewer=inherit strong=opus)" = "route gap all rung strong model opus effort high reason follows-reviewer" ]
printf 'docs/a.md and src/util.py split across groups 1 and 2 (shared name: util)\n' >"$ctx/seams.txt"
[ "$(route review routing=auto reviewer=inherit strong=opus)" = "route review group-1 rung cheap model sonnet effort high reason docs-only-small samples 1
route review group-2 rung strong model opus effort high reason risky-probe samples 1" ]
rm "$ctx/seams.txt"
printf 'deps\tdocs/a.md\n' >"$ctx/probe-files.txt"
[ "$(route review $ARGS)" = "route review group-1 rung base model inherit effort high reason role-model samples 1
route review group-2 rung base model inherit effort high reason role-model samples 1" ]
rm -f "$ctx/shards.txt"

# The gap pass runs after any sharded review; otherwise double_review decides.
rm -f "$ctx/shards.txt"
probes ''
[ "$(route gap $ARGS double=off)" = "route gap all skip reason double-review-off" ]
[ "$(route gap $ARGS double=risky)" = "route gap all skip reason no-risk-signal" ]
probes 'sensitive'
[ "$(route gap $ARGS double=risky)" = "route gap all rung base model inherit effort high reason follows-reviewer" ]
probes 'automation'
[ "$(route gap $ARGS double=risky)" = "route gap all rung base model inherit effort high reason follows-reviewer" ]
probes ''
printf 'group 1 lines 9 files 001\n' >"$ctx/shards.txt"
[ "$(route gap $ARGS double=off)" = "route gap all rung base model inherit effort high reason follows-reviewer" ]
rm -f "$ctx/shards.txt"

# The filter is skipped when it is off; review lines carry the sample count.
[ "$(route filter $ARGS filter=false)" = "route filter all skip reason filter-off" ]
classify code 50 50
[ "$(route review $ARGS samples=3)" = "route review all rung base model inherit effort high reason role-model samples 3" ]

# The verifier drops a level only when every finding it judges is settled by
# execution or a proven suggestion, and climbs one for a finding's stakes.
printf 'id: F020\nstatus: addressed\nseverity: minor\npath: src/a.py\n---\nbody\n```suggestion\nx\n```\n' >"$dir/findings/F020"
printf 'id: F021\nstatus: addressed\nseverity: major\npath: src/a.py\n---\nbody\nCheck: make check -k a\nResolution: x.\n' >"$dir/findings/F021"
printf 'id: F022\nstatus: addressed\nseverity: major\npath: src/a.py\n---\nbody\nResolution: x.\n' >"$dir/findings/F022"
[ "$(route verify routing=auto verifier=inherit 'check=make check' -- F020 F021)" = "route verify all rung base model inherit effort low reason role-model" ]
[ "$(route verify $ARGS 'check=make check' -- F020 F022)" = "route verify all rung base model sonnet effort medium reason role-model" ]
[ "$(route verify $ARGS -- F021)" = "route verify all rung base model sonnet effort medium reason role-model" ]
[ "$(route verify $ARGS 'prefixes=make check' -- F021)" = "route verify all rung base model sonnet effort low reason role-model" ]
[ "$(route verify routing=fixed -- F020)" = "route verify all rung base model sonnet effort medium reason role-model" ]
[ "$(route verify $ARGS --)" = "route verify all skip reason nothing-addressed" ]
printf 'id: F023\nstatus: addressed\nseverity: major\ncategory: security\npath: src/a.py\n---\nbody\nResolution: x.\n' >"$dir/findings/F023"
printf 'id: F024\nstatus: addressed\nseverity: blocker\npath: src/a.py\n---\nbody\nCheck: make check -k a\nResolution: x.\n' >"$dir/findings/F024"
[ "$(route verify $ARGS -- F020 F023)" = "route verify all rung base model sonnet effort high reason role-model" ]
[ "$(route verify $ARGS 'check=make check' -- F020 F024)" = "route verify all rung base model sonnet effort medium reason role-model" ]
[ "$(route verify $ARGS posture=economy -- F023)" = "route verify all rung base model sonnet effort high reason role-model" ]

# The incremental review after a round keeps the reviewer's model and level.
[ "$(route incremental routing=auto reviewer=opus strong=sonnet)" = "route incremental all rung base model opus effort high reason role-model" ]

# Arbitration takes the strong model, else the reviewer's.
[ "$(route arbitrate routing=auto reviewer=inherit strong=opus)" = "route arbitrate all rung strong model opus effort high reason arbitration" ]
[ "$(route arbitrate routing=auto reviewer=inherit)" = "route arbitrate all rung base model inherit effort high reason no-strong-model" ]
[ "$(route arbitrate routing=fixed strong=opus)" = "route arbitrate all skip reason fixed-routing" ]

# The posture leans every decision the change itself does not settle:
# economy drops more and climbs later, quality drops less and climbs
# sooner, and balanced keeps the lines above.
classify docs-only 400 0
probes ''
[ "$(route review $ARGS posture=economy)" = "route review all rung cheap model sonnet effort medium reason docs-only-small samples 1" ]
[ "$(route review $ARGS)" = "route review all rung base model inherit effort high reason role-model samples 1" ]
classify docs-only 200 0
[ "$(route review $ARGS posture=quality)" = "route review all rung base model inherit effort high reason role-model samples 1" ]
[ "$(route review $ARGS)" = "route review all rung cheap model sonnet effort medium reason docs-only-small samples 1" ]
classify tests-only 100 0
[ "$(route review $ARGS posture=economy)" = "route review all rung cheap model sonnet effort medium reason tests-only-small samples 1" ]
[ "$(route review $ARGS)" = "route review all rung base model inherit effort high reason role-model samples 1" ]
probes 'test-shrink'
[ "$(route review $ARGS posture=economy)" = "route review all rung base model inherit effort high reason role-model samples 1" ]
classify code 600 500
probes ''
[ "$(route review routing=auto strong=opus posture=quality)" = "route review all rung strong model opus effort high reason large-code samples 1" ]
[ "$(route review routing=auto strong=opus)" = "route review all rung base model inherit effort high reason role-model samples 1" ]
classify code 1100 1000
[ "$(route review routing=auto strong=opus)" = "route review all rung strong model opus effort high reason large-code samples 1" ]
[ "$(route review routing=auto strong=opus posture=economy)" = "route review all rung base model inherit effort high reason role-model samples 1" ]

# A stakes probe climbs whatever the kind: a token in a config file or
# a workflow edit is as risky as one in code.
classify config-only 40 0
probes 'automation'
[ "$(route review routing=auto strong=opus)" = "route review all rung strong model opus effort high reason risky-probe samples 1" ]
[ "$(route review $ARGS)" = "route review all rung base model inherit effort high reason strong-wanted-unset samples 1" ]
classify docs-only 20 0
probes 'secrets'
[ "$(route review routing=auto strong=opus posture=economy)" = "route review all rung strong model opus effort high reason risky-probe samples 1" ]

# Quality pays for one review sample beyond the setting where a stakes
# probe fired, never above three and never under fixed routing; the
# other postures keep the setting.
classify code 90 90
probes 'sensitive'
[ "$(route review routing=auto strong=opus posture=quality)" = "route review all rung strong model opus effort high reason risky-probe samples 2" ]
[ "$(route review routing=auto strong=opus posture=quality samples=3)" = "route review all rung strong model opus effort high reason risky-probe samples 3" ]
[ "$(route review routing=auto strong=opus)" = "route review all rung strong model opus effort high reason risky-probe samples 1" ]
[ "$(route review routing=fixed strong=opus posture=quality)" = "route review all rung base model inherit effort high reason fixed samples 1" ]
probes ''
[ "$(route review routing=auto strong=opus posture=quality)" = "route review all rung base model inherit effort high reason role-model samples 1" ]
printf '001\tdocs/a.md\tdocs\t40\n002\tdocs/b.md\tdocs\t30\n003\tsrc/auth.py\tcode\t120\n004\tsrc/util.py\tcode\t60\n' >"$ctx/files-kind.txt"
printf 'group 1 lines 70 files 001 002\ngroup 2 lines 180 files 003 004\n' >"$ctx/shards.txt"
printf 'sensitive\tsrc/auth.py\n' >"$ctx/probe-files.txt"
classify code 250 180
[ "$(route review routing=auto reviewer=inherit strong=opus posture=quality)" = "route review group-1 rung cheap model sonnet effort medium reason docs-only-small samples 1
route review group-2 rung strong model opus effort high reason risky-probe samples 2" ]
rm -f "$ctx/shards.txt" "$ctx/probe-files.txt"

# Depth climbs the model: code whose changed files reference one another
# at least the posture's count of times (balanced 4, quality 2, economy
# 6) takes the strong model, and the effort instead when none is set. A
# shard group is judged on its own count, not the whole change's.
classify code 90 90
probes ''
printf '4\n' >"$ctx/couplings.txt"
[ "$(route review routing=auto strong=opus)" = "route review all rung strong model opus effort high reason coupled samples 1" ]
[ "$(route review $ARGS)" = "route review all rung base model inherit effort high reason strong-wanted-unset samples 1" ]
[ "$(route review routing=auto strong=opus posture=economy)" = "route review all rung base model inherit effort high reason role-model samples 1" ]
printf '2\n' >"$ctx/couplings.txt"
[ "$(route review routing=auto strong=opus)" = "route review all rung base model inherit effort high reason role-model samples 1" ]
[ "$(route review routing=auto strong=opus posture=quality)" = "route review all rung strong model opus effort high reason coupled samples 1" ]
classify docs-only 20 0
printf '9\n' >"$ctx/couplings.txt"
[ "$(route review routing=auto strong=opus)" = "route review all rung cheap model sonnet effort medium reason docs-only-small samples 1" ]
printf '001\tdocs/a.md\tdocs\t40\n002\tdocs/b.md\tdocs\t30\n003\tsrc/auth.py\tcode\t120\n004\tsrc/util.py\tcode\t60\n' >"$ctx/files-kind.txt"
printf 'group 1 lines 70 files 001 002\ngroup 2 lines 180 files 003 004\n' >"$ctx/shards.txt"
: >"$ctx/probe-files.txt"
classify code 250 180
printf '9\ngroup 1 0\ngroup 2 0\n' >"$ctx/couplings.txt"
[ "$(route review routing=auto reviewer=inherit strong=opus)" = "route review group-1 rung cheap model sonnet effort medium reason docs-only-small samples 1
route review group-2 rung base model inherit effort high reason role-model samples 1" ]
printf '9\ngroup 1 0\ngroup 2 4\n' >"$ctx/couplings.txt"
[ "$(route review routing=auto reviewer=inherit strong=opus)" = "route review group-1 rung cheap model sonnet effort medium reason docs-only-small samples 1
route review group-2 rung strong model opus effort high reason coupled samples 1" ]
rm -f "$ctx/shards.txt" "$ctx/probe-files.txt" "$ctx/couplings.txt"

# The editor's effort is capped at high except under quality, so a retry
# at high climbs the model under balanced and the effort under quality.
printf 'id: F030\nstatus: open\nseverity: blocker\ncategory: correctness\npath: src/d.py\n---\nbody\n' >"$dir/findings/F030"
[ "$(route edit routing=auto strong=opus round=1 -- F030)" = "route edit all rung base model inherit effort high reason stakes-floor ids F030" ]
[ "$(route edit routing=auto strong=opus round=2 -- F030)" = "route edit all rung strong model opus effort high reason escalated ids F030" ]
printf 'id: F031\nstatus: open\nseverity: blocker\ncategory: correctness\npath: src/d.py\n---\nbody\n' >"$dir/findings/F031"
[ "$(route edit routing=auto strong=opus posture=quality round=1 -- F031)" = "route edit all rung base model inherit effort high reason stakes-floor ids F031" ]
[ "$(route edit routing=auto strong=opus posture=quality round=2 -- F031)" = "route edit all rung base model inherit effort xhigh reason more-effort ids F031" ]
[ "$(route edit routing=auto strong=opus posture=quality round=3 -- F031)" = "route edit all rung strong model opus effort xhigh reason escalated ids F031" ]
[ "$(route repair routing=auto strong=opus posture=economy round=1 -- F030)" = "route repair all rung strong model opus effort high reason gate-failed ids F030" ]
[ "$(route repair routing=fixed round=1 -- F030)" = "route repair all rung base model inherit effort medium reason fixed ids F030" ]

# Effort reaches xhigh only under quality, and a signal is paid for
# once: a stakes probe a stronger model takes leaves the effort alone,
# and raises it when no stronger model is set or the strong model is
# the reviewer's own.
classify code 90 90
probes 'sensitive'
[ "$(route review $ARGS posture=quality)" = "route review all rung base model inherit effort xhigh reason strong-wanted-unset samples 2" ]
[ "$(route review routing=auto reviewer=opus strong=opus posture=quality)" = "route review all rung strong model opus effort xhigh reason risky-probe samples 2" ]
[ "$(route review routing=auto reviewer=opus strong=opus)" = "route review all rung strong model opus effort high reason risky-probe samples 1" ]
classify code 1200 950
probes ''
printf 'a.py and b.py split across groups 1 and 2 (shared name: parse)\n' >"$ctx/seams.txt"
[ "$(route review routing=auto strong=opus posture=quality)" = "route review all rung strong model opus effort high reason large-code samples 1" ]
rm -f "$ctx/seams.txt"

# Every decision was recorded, in order.
[ "$(grep -c '^route ' "$ctx/routes.txt")" -eq 110 ]
[ "$(sed -n '1p' "$ctx/routes.txt")" = "route review all rung cheap model sonnet effort medium reason docs-only-small samples 1" ]

# Every emitted level passes the posture's cap, the gap floor and the
# filter included.
sed 's/^effort: low$/effort: xhigh/' "$REPO_ROOT/agents/filter.md" >"$SCRATCH/xhigh-filter.md"
mkdir -p "$SCRATCH/capped"
cp -R "$REPO_ROOT/scripts" "$REPO_ROOT/agents" "$SCRATCH/capped/"
cp "$SCRATCH/xhigh-filter.md" "$SCRATCH/capped/agents/filter.md"
sed 's/^effort: high$/effort: xhigh/' "$REPO_ROOT/agents/reviewer.md" >"$SCRATCH/capped/agents/reviewer.md"
[ "$(sh "$SCRATCH/capped/scripts/route-models.sh" "$dir" filter $ARGS posture=economy)" = "route filter all rung base model sonnet effort high reason role-model" ]
rm -f "$ctx/shards.txt"
probes 'sensitive'
[ "$(sh "$SCRATCH/capped/scripts/route-models.sh" "$dir" gap $ARGS posture=economy double=risky)" = "route gap all rung base model inherit effort high reason follows-reviewer" ]
[ "$(sh "$SCRATCH/capped/scripts/route-models.sh" "$dir" filter routing=fixed posture=economy)" = "route filter all rung base model sonnet effort high reason role-model" ]
[ "$(sh "$SCRATCH/capped/scripts/route-models.sh" "$dir" review routing=fixed posture=economy)" = "route review all rung base model inherit effort high reason fixed samples 1" ]

# A definition at a level routing does not use stops every stage before it
# prints a line, rather than routing the bottom level.
mkdir -p "$SCRATCH/copy"
cp -R "$REPO_ROOT/scripts" "$REPO_ROOT/agents" "$SCRATCH/copy/"
sed 's/^effort: high$/effort: max/' "$REPO_ROOT/agents/reviewer.md" >"$SCRATCH/copy/agents/reviewer.md"
for stage in review "edit $ARGS round=1 -- F001"; do
	if out=$(sh "$SCRATCH/copy/scripts/route-models.sh" "$dir" $stage 2>"$SCRATCH/err"); then
		echo "expected refusal of a max definition at: $stage" >&2
		exit 1
	fi
	[ -z "$out" ]
	grep -q "agents/reviewer.md declares effort 'max'" "$SCRATCH/err"
done

# Refusals: an unknown stage, a bad routing value, an edit without ids, an unknown finding.
for bad in "wat" "review routing=sometimes" "edit $ARGS" "edit $ARGS -- F999" "verify $ARGS" "verify $ARGS -- F999"; do
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
