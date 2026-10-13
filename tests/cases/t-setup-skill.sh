#!/bin/sh
# The setup skill: Claude never starts it alone, it is allowed exactly
# the scripts its body runs and those exist, its preview feeds every
# manifest setting, and its profile table names only real values.
set -eu

skill="$REPO_ROOT/skills/setup/SKILL.md"
manifest="$REPO_ROOT/.claude-plugin/plugin.json"
[ -f "$skill" ]
grep -qx 'disable-model-invocation: true' "$skill"
grep -q '^name: setup$' "$skill"

# Every script the body names is allowed, and every allowed one exists and is named.
grep -o 'scripts/[a-z-]*\.sh' "$skill" | sort -u >"$SCRATCH/named"
sed -n 's/^  - Bash(sh ${CLAUDE_PLUGIN_ROOT}\/\(scripts\/[a-z-]*\.sh\).*/\1/p' "$skill" | sort -u >"$SCRATCH/allowed"
cmp -s "$SCRATCH/named" "$SCRATCH/allowed" || {
	echo "the skill's allowed scripts and the scripts its body names differ" >&2
	diff "$SCRATCH/named" "$SCRATCH/allowed" >&2 || true
	exit 1
}
while read -r path; do
	[ -f "$REPO_ROOT/$path" ] || {
		echo "the skill names $path, which does not exist" >&2
		exit 1
	}
done <"$SCRATCH/allowed"
# The resolver is allowed only in preview, which writes nothing.
grep -q 'Bash(sh ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-settings.sh --preview \*)' "$skill"
! grep -q 'resolve-settings.sh \*' "$skill"

# The preview block feeds every manifest setting, each from user_config.
sed -n 's/^    "\([a-z_]*\)": {$/\1/p' "$manifest" | sort >"$SCRATCH/keys"
sed -n 's/^\([a-z_]*\) \${user_config\.\1}$/\1/p' "$skill" | sort -u >"$SCRATCH/fed"
cmp -s "$SCRATCH/keys" "$SCRATCH/fed" || {
	echo "the skill's preview block and the manifest's settings differ" >&2
	diff "$SCRATCH/keys" "$SCRATCH/fed" >&2 || true
	exit 1
}

# Every profile line is a value the resolver accepts, and the shared-file
# profiles only raise. The economy profile lowers, so the body says it is
# for a file of the user's own.
awk '/^\| careful \|/ || /^\| economy \|/' "$skill" | grep -o '`[a-z_]* [a-z0-9]*`' | tr -d '`' >"$SCRATCH/profile-lines"
[ -s "$SCRATCH/profile-lines" ]
cd "$SCRATCH"
sh "$REPO_ROOT/scripts/resolve-settings.sh" --lint personal profile-lines | grep -q ' 0 refused$'
awk '/^\| careful \|/' "$skill" | grep -o '`[a-z_]* [a-z0-9]*`' | tr -d '`' >"$SCRATCH/careful"
sh "$REPO_ROOT/scripts/resolve-settings.sh" --lint shared careful | grep -q ' 0 refused$'
awk '/^\| economy \|/' "$skill" | grep -o '`[a-z_]* [a-z0-9]*`' | tr -d '`' >"$SCRATCH/economy"
if sh "$REPO_ROOT/scripts/resolve-settings.sh" --lint shared economy >/dev/null; then
	echo "the economy profile must be one a shared file cannot carry" >&2
	exit 1
fi
grep -q '^| economy |.*shared file cannot lower' "$skill"

# The two setup agents: read-only cartographers that write only through the
# record script, an assembler that reads only, both without the reviewed
# repository's CLAUDE.md, and the skill spawns them with these exact prompts.
field() { sed -n '2,/^---$/p' "$REPO_ROOT/agents/$1.md" | sed -n "s/^$2: //p"; }
[ "$(field cartographer omitClaudeMd)" = true ]
[ "$(field assembler omitClaudeMd)" = true ]
[ "$(field cartographer tools)" = "Read, Grep, Glob, Bash" ]
[ "$(field assembler tools)" = Read ]
[ "$(field cartographer model)" = sonnet ]
[ -z "$(field assembler model)" ]
[ "$(field cartographer maxTurns)" = 40 ]
[ "$(field assembler maxTurns)" = 20 ]
grep -q 'scripts/save-record.sh' "$REPO_ROOT/agents/cartographer.md"
! grep -q 'save-record' "$skill"
grep -qF 'Map the repository. Survey directory: <dir>. Partition: <id>.' "$skill"
grep -qF 'Draft the conventions block. Survey directory: <dir>.' "$skill"
grep -q 'pr-review-workflow:cartographer' "$skill"
grep -q 'pr-review-workflow:assembler' "$skill"

# The writer takes `shared` for the team audience, and the skill says so.
grep -q 'write-settings.sh <shared|personal|local>' "$skill"
tr '\n' ' ' <"$skill" | tr -s ' ' | grep -q 'pass `shared` when the chosen audience is `team`'
