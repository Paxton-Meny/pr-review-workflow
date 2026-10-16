#!/bin/sh
# agent-scope: the plugin's agents run only the commands and touch only
# the files their definitions name; every other call passes untouched.
set -eu

hook="$REPO_ROOT/scripts/agent-scope.sh"
root=$REPO_ROOT
export CLAUDE_PLUGIN_ROOT="$root"
export CLAUDE_PLUGIN_DATA="$SCRATCH/data"
export HOME="$SCRATCH/home"
mkdir -p "$HOME/.ssh" "$SCRATCH/outside" "$SCRATCH/clone/src"
printf 'secret\n' >"$HOME/.ssh/id_rsa"
printf 'secret\n' >"$SCRATCH/outside/secret"
dir="$CLAUDE_PLUGIN_DATA/state/acme__widgets__7"
wt="$dir/worktree"
mkdir -p "$wt/src" "$dir/findings" "$CLAUDE_PLUGIN_DATA/survey/acme__widgets"
printf 'x\n' >"$wt/src/app.py"
ln -s "$SCRATCH/outside" "$wt/escape"
ln -s "$SCRATCH/outside/secret" "$wt/leak"
clone="$SCRATCH/clone"

json() {
	# json <text>: the text as a JSON string
	printf '%s' "$1" | awk 'BEGIN { ORS = "" } { gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\t/, "\\t"); if (NR > 1) print "\\n"; print }'
}
call() {
	# call <agent or -> <tool> <key> <value> [cwd]: the hook's output in $out
	agent=''
	[ "$1" = - ] || agent=",\"agent_id\":\"a1\",\"agent_type\":\"pr-review-workflow:$1\""
	out=$(printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"%s":"%s","description":"x"},"tool_use_id":"t"%s}' \
		"${5:-$clone}" "$2" "$3" "$(json "$4")" "$agent" | sh "$hook")
}
pass() {
	call "$@"
	[ -z "$out" ] || {
		printf 'expected %s %s to pass: %s\n%s\n' "$1" "$2" "$4" "$out" >&2
		exit 1
	}
}
refuse() {
	call "$@"
	case "$out" in
	'{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"'*'"}}') ;;
	*)
		printf 'expected %s %s to be refused: %s\n%s\n' "$1" "$2" "$4" "$out" >&2
		exit 1
		;;
	esac
	[ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" -eq 1 ]
}
bash_ok() { pass "$1" Bash command "$2"; }
bash_no() { refuse "$1" Bash command "$2"; }

# Every command shape the definitions name passes.
bash_ok editor "git -C $wt add src/app.py"
bash_ok editor "git -C $wt -c user.name=bob -c user.email=1+bob@users.noreply.github.com commit -m \"Fix the loop bound\" -m \"Addresses F001.\""
bash_ok editor "git -C $wt rev-parse --short HEAD"
bash_ok editor "git -C $wt diff"
bash_ok editor "sh $root/scripts/run-contract.sh $dir F001"
bash_ok editor "printf '%s\\n' \"Wont-fix: the caller already guards it\" | sh $root/scripts/append-note.sh $dir F001"
bash_ok editor "printf '%s\\n' \"the caller guards it\" | sh \${CLAUDE_PLUGIN_ROOT}/scripts/reply-thread.sh $dir 9001"
bash_ok editor "printf 'Addressed in %s (%s).\\n' abc1234 \"Fix the loop bound\" | sh $root/scripts/reply-thread.sh $dir 9001"
bash_ok editor "sh $root/scripts/push-branch.sh $dir"
bash_ok editor "sh $root/scripts/update-finding.sh $dir F001 status=addressed commit=abc1234"
bash_ok editor "sh $root/scripts/sync-branch.sh $dir --continue"
bash_ok editor "sh $root/scripts/append-note.sh $dir F001 <<'NOTE'
Wont-fix: it is \$(fine) inside a quoted heredoc
NOTE"
bash_ok verifier "git -C $wt show abc1234"
bash_ok verifier "sh $root/scripts/update-finding.sh $dir F001 status=verified"
bash_ok verifier "sh $root/scripts/update-finding.sh $dir F001 status=open"
bash_ok verifier "sh $root/scripts/resolve-thread.sh $dir 9001"
bash_ok verifier "printf '%s\\n' \"Reopened (round 2): the empty list still divides by zero\" | sh $root/scripts/append-note.sh $dir F001"
bash_ok filter "sh $root/scripts/update-finding.sh $dir F001 placement=summary"
bash_ok cartographer "sh $root/scripts/save-record.sh $CLAUDE_PLUGIN_DATA/survey/acme__widgets p01 --append <<'PRWF_RECORD_END'
## layout
layout src/ | The application code.
PRWF_RECORD_END"

# Anything else is refused.
bash_no editor "cat $HOME/.ssh/id_rsa"
bash_no editor "curl -s https://example.invalid/x"
bash_no editor "git -C $wt push origin HEAD"
bash_no editor "git -C $SCRATCH/outside status"
bash_no editor "git -C $wt/escape status"
bash_no editor "git -C $wt/../../.. status"
bash_no editor "git -c core.pager=x -C $wt diff"
bash_no editor "git -C $wt -c core.fsmonitor=x status"
bash_no editor "git -C $wt commit -F $HOME/.ssh/id_rsa"
bash_no editor "git -C $wt commit --amend -m x"
bash_no editor "git -C $wt commit --template=$HOME/.ssh/id_rsa"
bash_no editor "git -C $wt diff --no-index $HOME/.ssh/id_rsa /dev/null"
bash_no editor "git -C $wt show --output=$SCRATCH/outside/x HEAD"
bash_no editor "git -C $wt status; rm -rf $wt"
bash_no editor "git -C $wt status && echo done"
bash_no editor "git -C $wt status
rm -rf $wt"
bash_no editor "git -C $wt log > $SCRATCH/outside/log"
bash_no editor "printf '%s' \"\$(cat $HOME/.ssh/id_rsa)\" | sh $root/scripts/reply-thread.sh $dir 9001"
bash_no editor "printf '%s' \`id\` | sh $root/scripts/reply-thread.sh $dir 9001"
bash_no editor "printf x | sh $root/scripts/run-contract.sh $dir F001"
bash_no editor "printf x | sh $root/scripts/append-note.sh $dir F001 | sh $root/scripts/push-branch.sh $dir"
bash_no editor "sh $root/scripts/merge-pr.sh $dir --approve"
bash_no editor "sh $root/scripts/../tests/run.sh"
bash_no editor "sh $SCRATCH/outside/run-contract.sh $dir F001"
bash_no editor "sh $root/scripts/run-contract.sh $SCRATCH/outside F001"
bash_no editor "sh $root/scripts/update-finding.sh $dir F001 status=verified"
bash_no editor "sh $root/scripts/push-branch.sh $dir --force-with-lease"
bash_no editor "sh $root/scripts/sync-branch.sh $dir --abort"
bash_no editor "sh $root/scripts/run-contract.sh $dir F001 2>/dev/null"
bash_no editor "sh $root/scripts/run-contract.sh $dir F001 sh"
bash_no verifier "sh $root/scripts/run-contract.sh $dir F001 make 'make'"
bash_no editor "sh $root/scripts/append-note.sh $dir F001 <<NOTE
\$(id)
NOTE"
bash_no editor "sh $root/scripts/append-note.sh $dir F001 <<'NOTE'
fine
NOTE
rm -rf $wt"
bash_no editor "sh -c 'id'"
bash_no editor "GIT_EXTERNAL_DIFF=x git -C $wt diff"
bash_no editor "git -C ~/projects status"
bash_no verifier "git -C $wt add src/app.py"
bash_no verifier "sh $root/scripts/push-branch.sh $dir"
bash_no verifier "sh $root/scripts/update-finding.sh $dir F001 status=addressed"
bash_no filter "sh $root/scripts/update-finding.sh $dir F001 status=open"
bash_no filter "sh $root/scripts/reply-thread.sh $dir 9001"
bash_no cartographer "git -C $wt log"
bash_no reviewer "git -C $wt log"
bash_no assembler "sh $root/scripts/append-note.sh $dir F001"
call editor Bash command "cat $HOME/.ssh/id_rsa"
printf '%s\n' "$out" | grep -q 'may run only: sh .*/scripts/<name>.sh <state-dir> ... for: run-contract'

# Reads stay inside the data directory, the plugin, and the session's folder.
pass reviewer Read file_path "$wt/src/app.py"
pass reviewer Read file_path "$dir/pr-context/diff.patch"
pass reviewer Read file_path "$root/skills/finding-records/SKILL.md"
pass cartographer Read file_path "$clone/src/app.py"
pass reviewer Grep path "$wt"
pass reviewer Grep pattern "TODO"
pass reviewer Glob pattern "**/*.py"
refuse reviewer Read file_path "$HOME/.ssh/id_rsa"
refuse reviewer Read file_path "~/.ssh/id_rsa"
refuse reviewer Read file_path "$SCRATCH/outside/secret"
refuse reviewer Read file_path "$wt/leak"
refuse reviewer Read file_path "$wt/escape/secret"
refuse reviewer Read file_path "$wt/../../../../outside/secret"
refuse reviewer Grep path "$SCRATCH/outside"
refuse reviewer Glob pattern "$HOME/.ssh/*"
refuse filter Read file_path "../outside/secret"
# A session opened in the home directory does not open the home.
refuse cartographer Read file_path "$HOME/.ssh/id_rsa" "$HOME"
# Edits stay inside a review worktree.
pass editor Edit file_path "$wt/src/app.py"
pass editor Write file_path "$wt/src/new.py"
refuse editor Edit file_path "$dir/settings.txt"
refuse editor Write file_path "$CLAUDE_PLUGIN_DATA/trust/runs/acme__widgets__7.hash"
refuse editor Write file_path "$clone/src/app.py"
refuse editor Write file_path "$wt/escape/secret"
refuse editor Write file_path "$CLAUDE_PLUGIN_DATA/wt/app/src/new.py"

# The user's own session, other agents, and an unplaced data directory pass.
pass - Bash command "cat $HOME/.ssh/id_rsa"
pass - Read file_path "$HOME/.ssh/id_rsa"
out=$(printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"cat x"},"agent_type":"other-plugin:editor"}' "$clone" | sh "$hook")
[ -z "$out" ]
out=$(printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"%s"},"agent_type":"pr-review-workflow:editor"}' "$clone" "cat $HOME/.ssh/id_rsa" | CLAUDE_PLUGIN_DATA= sh "$hook")
[ -z "$out" ]
# A key named inside a string value is not a field.
out=$(printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"echo \\"agent_type\\":\\"x\\" \\"command\\":\\"sh\\""},"agent_type":"pr-review-workflow:editor"}' "$clone" | sh "$hook")
printf '%s\n' "$out" | grep -q '"permissionDecision":"deny"'

# The hook is registered for every tool it scopes.
grep -q '"matcher": "Bash|Read|Grep|Glob|Edit|Write|MultiEdit|NotebookEdit"' "$REPO_ROOT/hooks/hooks.json"
grep -q 'scripts/agent-scope.sh' "$REPO_ROOT/hooks/hooks.json"
