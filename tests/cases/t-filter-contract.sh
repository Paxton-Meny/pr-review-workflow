#!/bin/sh
# The filter is handed the unposted finding ids, reads each record by
# path, and reports a pass that read nothing as skipped.
set -eu

skill="$REPO_ROOT/skills/review-pr/SKILL.md"
filter="$REPO_ROOT/agents/filter.md"

step=$(sed -n '/^7\. /,/^8\. /p' "$skill")
printf '%s\n' "$step" | grep -q 'count-findings.sh <dir> --list'
printf '%s\n' "$step" | grep -q 'When its `unposted_ids` line lists any finding'
printf '%s\n' "$step" | grep -qF '`Filter the banked findings. State directory: <dir>. Finding ids: <unposted_ids>. Demote only what fresh reading cannot support; never drop.`'

grep -qF '`<state-dir>/findings/<id>`' "$filter"
grep -qF '`filter: demoted M of N`' "$filter"
grep -qF '`filter: skipped (<what stopped you>)`' "$filter"
