---
name: status
description: "Show the review ledger: the runs recorded for this repository or all of them, each run's finding outcomes and whether it can resume, and the accumulated statistics across finished runs."
disable-model-invocation: true
argument-hint: "[all]"
allowed-tools:
  - Bash(sh ${CLAUDE_PLUGIN_ROOT}/scripts/list-runs.sh *)
  - Bash(sh ${CLAUDE_PLUGIN_ROOT}/scripts/stats-report.sh *)
---

Report the state of the review ledger. This skill reads local state
only: no network, no GitHub calls, nothing written.

1. `sh ${CLAUDE_PLUGIN_ROOT}/scripts/list-runs.sh "${CLAUDE_PLUGIN_DATA}" $ARGUMENTS`
   With no argument it lists runs for the repository the session is
   in; `all` lists every repository's runs.
2. `sh ${CLAUDE_PLUGIN_ROOT}/scripts/stats-report.sh "${CLAUDE_PLUGIN_DATA}"`

Relay both outputs verbatim in one code block, then at most two
sentences of reading: name any run marked `resumable yes` and say it
resumes by invoking `/pr-review-workflow:review-pr` with that pull
request, and note anything the statistics make obvious, such as every
run converging in one round or a rising demotion count. Do not open
ledger files, re-derive counts, or editorialize beyond those two
sentences; the lines are the report.
