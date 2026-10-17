#!/bin/sh
# ci workflow: runs the suite with no outside code, a read-only token
# that never reaches repository code, no privileged triggers, and no
# expression expanded inside a script.
set -eu

# Judged without its comments, which may name what it avoids.
[ -f "$REPO_ROOT/.github/workflows/tests.yml" ]
wf="$SCRATCH/tests.yml"
grep -v '^[[:space:]]*#' "$REPO_ROOT/.github/workflows/tests.yml" >"$wf"
refuse() {
	echo "tests.yml: $1" >&2
	exit 1
}

# No actions, reusable workflows, or containers: nothing from outside.
! grep -qE '^[[:space:]-]*(uses|container|services):' "$wf" || refuse "pulls in outside code"
# Only the unprivileged triggers.
! grep -qE 'pull_request_target|workflow_run|issue_comment|workflow_call' "$wf" || refuse "has a privileged trigger"
# Nothing granted by default; the job reads contents and nothing else.
grep -qx 'permissions: {}' "$wf" || refuse "grants permissions by default"
[ "$(grep -cE '^[[:space:]]+[a-z-]+: (read|write)$' "$wf")" -eq 1 ] || refuse "grants more than one permission"
grep -qE '^[[:space:]]+contents: read$' "$wf" || refuse "does not limit the job to reading contents"
! grep -qE 'permissions:[[:space:]]*(read|write)-all' "$wf" || refuse "grants a shorthand permission"
[ "$(grep -cE '^[[:space:]]*permissions:' "$wf")" -eq 2 ] || refuse "grants permissions beyond the top-level reset and the job's read"
! grep -q 'secrets\.' "$wf" || refuse "reads a secret"
# An expression expands only in a key the runner reads, never in a
# script, where a branch name or title could become a command.
bad=$(grep -n '\${{' "$wf" | grep -vE '^[0-9]+:[[:space:]]*(group|cancel-in-progress|TOKEN):' || true)
[ -z "$bad" ] || refuse "expands an expression outside group, cancel-in-progress, or TOKEN: $bad"
[ "$(grep -c 'TOKEN' "$wf")" -eq 2 ] || refuse "the token appears outside the fetch step"
# The token never lands on argv or in .git/config: the one extraheader
# is the environment's.
[ "$(grep -c 'extraheader' "$wf")" -eq 1 ] || refuse "sets an extra header outside the fetch's environment"
grep -qE '^[[:space:]]+GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http\.extraheader \\$' "$wf" || refuse "no longer passes the token through the environment"
! grep -qE 'git (-c|config)[^|;&]*http\.' "$wf" || refuse "writes the token into git configuration"
# The suite runs offline, after the fetch, with the job time-boxed.
grep -qE '^[[:space:]]+run: sh tests/run.sh$' "$wf" || refuse "does not run the suite"
grep -qE '^[[:space:]]+timeout-minutes: [0-9]+$' "$wf" || refuse "has no timeout"
