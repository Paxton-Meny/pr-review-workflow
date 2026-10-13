#!/bin/sh
# Every agent declares a reasoning effort from the levels Claude Code
# accepts, the narrow roles stay cheap, and arbitration is the verifier
# at a routed effort rather than an agent carrying its own copy.
set -eu

field() {
	sed -n '2,/^---$/p' "$REPO_ROOT/agents/$1.md" | sed -n "s/^$2: //p"
}

for agent in reviewer editor verifier filter; do
	effort=$(field "$agent" effort)
	case "$effort" in
	low | medium | high | xhigh | max) ;;
	*)
		echo "agents/$agent.md declares effort '$effort', which is not a level Claude Code accepts" >&2
		exit 1
		;;
	esac
done

[ "$(field reviewer effort)" = high ]
[ "$(field editor effort)" = medium ]
[ "$(field verifier effort)" = medium ]
[ "$(field filter effort)" = low ]

[ ! -e "$REPO_ROOT/agents/arbiter.md" ]
grep -q '^## Arbitration$' "$REPO_ROOT/agents/verifier.md"
if grep -q 'pr-review-workflow:arbiter' "$REPO_ROOT/skills/review-pr/SKILL.md"; then
	echo "the skill still spawns the retired arbiter agent" >&2
	exit 1
fi

# Every delegation passes the route's effort beside its model: each
# delegation prompt in the skill has `effort` named within its step.
awk '
	{ line[NR] = $0 }
	/^ *`(Review the pull request|Filter the banked|Address the open|The project check fails|Verify the addressed|Arbitrate the repeatedly)/ { at[++n] = NR }
	END {
		for (i = 1; i <= n; i++) {
			found = 0
			for (j = at[i] - 8; j <= at[i] + 8; j++) if (index(line[j], "`effort`")) found = 1
			if (!found) { print "no effort named near skill line " at[i] > "/dev/stderr"; bad = 1 }
		}
		if (n < 7) { print "expected seven delegation prompts, found " n > "/dev/stderr"; bad = 1 }
		exit bad
	}' "$REPO_ROOT/skills/review-pr/SKILL.md"

# A spawn tool without an effort parameter is recorded on every
# invocation, before any route line, and reported at the end.
grep -q 'route-models.sh <dir> spawn-effort applied' "$REPO_ROOT/skills/review-pr/SKILL.md"
sed -n '/^2\. /,/^3\. /p' "$REPO_ROOT/skills/review-pr/SKILL.md" | grep -q 'whether the spawn tool takes an effort'
grep -q 'routed efforts were not applied' "$REPO_ROOT/skills/review-pr/SKILL.md"

# The incremental review in step 8e has no prompt of its own, so check
# that it is routed and passes both overrides.
grep -A4 'route-models.sh <dir> incremental' "$REPO_ROOT/skills/review-pr/SKILL.md" | grep -q 'with its `model` and'
grep -A5 'route-models.sh <dir> incremental' "$REPO_ROOT/skills/review-pr/SKILL.md" | grep -q '`effort`'
grep -B9 'Arbitrate the repeatedly reopened findings' "$REPO_ROOT/skills/review-pr/SKILL.md" |
	grep -q 'spawning `pr-review-workflow:verifier`'

# An arbitration that upholds a reopen changes no status: the finding is
# already open, and open to open is an illegal transition.
sed -n '/^## Arbitration$/,/^## /p' "$REPO_ROOT/agents/verifier.md" | grep -q 'change no status'

# The verifier serves both roles, so its Arbitration section makes no
# claim about which model is running.
if sed -n '/^## Arbitration$/,/^## /p' "$REPO_ROOT/agents/verifier.md" | grep -qi 'stronger model'; then
	echo "the verifier's Arbitration section claims a stronger model" >&2
	exit 1
fi
