#!/bin/sh
# Every agent declares a reasoning effort from the levels Claude Code
# accepts, the narrow roles stay cheap, and the arbiter defers to the
# verifier's procedure instead of carrying a diverging copy of it.
set -eu

field() {
	sed -n '2,/^---$/p' "$REPO_ROOT/agents/$1.md" | sed -n "s/^$2: //p"
}

for agent in reviewer editor verifier filter arbiter; do
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
[ "$(field arbiter effort)" = high ]
[ "$(field editor effort)" = medium ]
[ "$(field verifier effort)" = low ]
[ "$(field filter effort)" = low ]

# The arbiter and the verifier are one procedure: same tools, same turn
# budget, and the arbiter reads the verifier's definition rather than
# restating it.
[ "$(field arbiter tools)" = "$(field verifier tools)" ]
[ "$(field arbiter maxTurns)" = "$(field verifier maxTurns)" ]
grep -q 'agents/verifier.md' "$REPO_ROOT/agents/arbiter.md"
grep -q '`pr-review-workflow:arbiter`' "$REPO_ROOT/skills/review-pr/SKILL.md"
if grep -q 'Arbitrate.*pr-review-workflow:verifier\|pr-review-workflow:verifier.*[Aa]rbitrat' "$REPO_ROOT/skills/review-pr/SKILL.md"; then
	echo "the skill still sends arbitration to the verifier agent" >&2
	exit 1
fi
