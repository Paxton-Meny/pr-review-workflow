#!/bin/sh
# Settings reach the code through the resolver only: ${user_config} stays
# in the skill's one heredoc, agents carry none, and scripts called
# without settings arguments use the resolved record.
set -eu

skill="$REPO_ROOT/skills/review-pr/SKILL.md"
outside=$(awk '
/^sh \$\{CLAUDE_PLUGIN_ROOT\}\/scripts\/resolve-settings\.sh / { inside = 1; next }
/^PRWF_SETTINGS_END$/ { inside = 0; next }
!inside && /\$\{user_config\./ { print FILENAME ":" NR ": " $0 }
' "$skill")
[ -z "$outside" ] || {
	echo "user_config used outside the resolver heredoc:" >&2
	printf '%s\n' "$outside" >&2
	exit 1
}
if grep -n '\${user_config\.' "$REPO_ROOT"/agents/*.md; then
	echo "agents must not carry user_config" >&2
	exit 1
fi

# Every manifest key appears in the heredoc exactly once.
for key in $(sed -n 's/^    "\([a-z_]*\)": {$/\1/p' "$REPO_ROOT/.claude-plugin/plugin.json"); do
	[ "$(grep -c "^$key \${user_config\.$key}\$" "$skill")" -eq 1 ] || {
		echo "the resolver heredoc must pass $key exactly once" >&2
		exit 1
	}
done

# Scripts called without settings arguments read the resolved record.
data="$SCRATCH/data"
dir="$data/state/o__r__1"
mkdir -p "$dir/pr-context" "$dir/worktree" "$dir/findings"
printf 'owner o\nrepo r\npr 1\n' >"$dir/meta.txt"
printf 'check_command echo checked > ran.txt\nkeep_ledgers 3\ncontract_commands make t\n' |
	sh "$REPO_ROOT/scripts/resolve-settings.sh" "$dir" >/dev/null
[ "$(sh "$REPO_ROOT/scripts/run-check.sh" "$dir")" = "run-check: pass" ]
[ "$(cat "$dir/worktree/ran.txt")" = checked ]
printf 'id: F001\nstatus: addressed\n---\nbody\nCheck: make t -k a\nResolution: x.\n' >"$dir/findings/F001"
[ "$(sh "$REPO_ROOT/scripts/run-contract.sh" --policy "$dir" F001)" = "run-contract: F001 verdict executable" ]
