---
name: status
description: "Show the review ledger: the runs recorded for this repository or all of them, each run's finding outcomes and whether it can resume, the accumulated statistics across finished runs, and the settings a review in this clone would use, with where each comes from."
disable-model-invocation: true
argument-hint: "[all]"
allowed-tools:
  - Bash(sh ${CLAUDE_PLUGIN_ROOT}/scripts/list-runs.sh *)
  - Bash(sh ${CLAUDE_PLUGIN_ROOT}/scripts/stats-report.sh *)
  - Bash(sh ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-settings.sh --preview *)
---

Report the state of the review ledger. This skill reads local state
only: no network, no GitHub calls, nothing written.

1. `sh ${CLAUDE_PLUGIN_ROOT}/scripts/list-runs.sh "${CLAUDE_PLUGIN_DATA}" $ARGUMENTS`
   With no argument it lists runs for the repository the session is
   in; `all` lists every repository's runs.
2. `sh ${CLAUDE_PLUGIN_ROOT}/scripts/stats-report.sh "${CLAUDE_PLUGIN_DATA}"`
3. The settings a review started in this clone would use, exactly as
   below, with the closing delimiter alone at the start of its line:

```
sh ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-settings.sh --preview "${CLAUDE_PLUGIN_DATA}" <<'PRWF_SETTINGS_END'
auto_approve ${user_config.auto_approve}
check_command ${user_config.check_command}
keep_ledgers ${user_config.keep_ledgers}
double_review ${user_config.double_review}
local_standards ${user_config.local_standards}
reviewer_model ${user_config.reviewer_model}
editor_model ${user_config.editor_model}
verifier_model ${user_config.verifier_model}
model_routing ${user_config.model_routing}
review_samples ${user_config.review_samples}
finding_filter ${user_config.finding_filter}
contract_commands ${user_config.contract_commands}
cost_posture ${user_config.cost_posture}
sensitive_paths ${user_config.sensitive_paths}
strong_model ${user_config.strong_model}
PRWF_SETTINGS_END
```

   It reads the project's shared file as of the last fetch, fetches
   nothing, and records nothing. Skip it when the session is not in a
   clone; `all` does not change it.

Relay all outputs verbatim in one code block, then at most two
sentences of reading: name any run marked `resumable yes` and say it
resumes by invoking `/pr-review-workflow:review-pr` with that pull
request, and note anything the statistics make obvious, such as every
run converging in one round or a rising demotion count, or a
`trust pending` line, which means the project's shared file names a
command that the next review will ask about. Do not open
ledger files, re-derive counts, or editorialize beyond those two
sentences; the lines are the report.
