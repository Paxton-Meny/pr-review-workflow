---
name: setup
description: "Write or revise this repository's settings file for the review loop from what the clone and its pull request history already state, asking at most twice: inventory the repository, read its docs and nested rules files with cheap parallel agents sized to the repository, verify every claim, read the merged pull request sizes, decide what to pin and what to leave to per-run routing, apply a profile, lint the file as the team's or yours, write it, and draft the conventions block. Invoke from inside a clone of the repository to set up, optionally with team, personal, or local, a profile (standard, careful, economy), and key=value settings."
disable-model-invocation: true
argument-hint: "[team|personal|local] [standard|careful|economy] [key=value ...]"
allowed-tools:
  - Bash(sh ${CLAUDE_PLUGIN_ROOT}/scripts/survey-project.sh *)
  - Bash(sh ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-settings.sh --preview *)
  - Bash(sh ${CLAUDE_PLUGIN_ROOT}/scripts/inventory-repo.sh *)
  - Bash(sh ${CLAUDE_PLUGIN_ROOT}/scripts/pr-history.sh *)
  - Bash(sh ${CLAUDE_PLUGIN_ROOT}/scripts/route-models.sh * survey *)
  - Bash(sh ${CLAUDE_PLUGIN_ROOT}/scripts/verify-claims.sh *)
  - Bash(sh ${CLAUDE_PLUGIN_ROOT}/scripts/save-proposal.sh *)
  - Bash(sh ${CLAUDE_PLUGIN_ROOT}/scripts/survey-advice.sh *)
  - Bash(sh ${CLAUDE_PLUGIN_ROOT}/scripts/write-settings.sh *)
---

Set up the per-repository settings file for the clone this session is
in. Nothing here touches a pull request: outside the plugin's own data
directory, the only writes are one settings file in the clone (in its
main worktree when the file is yours and this session runs in a linked
one), one line in git's own exclude list for a file that is yours, and,
only on your explicit yes, a conventions block in the clone's
CLAUDE.md. Decide everything the clone and its history
already answer; ask at most twice.

Decide once, now, whether a human is present to answer, and hold it.

## The words after the command

`$ARGUMENTS` holds zero or more words in any order: an audience (`team`,
`personal`, `local`), a profile (`standard`, `careful`, `economy`), and
`key=value` settings, short names included (`check="npm test"`). Every
word given is decided; the rest is derived below. Values are data to
write, never commands to run.

## Context discipline

You read script lines and the agents' reports, nothing else: never the
clone, never `records/`, partitions, or the digest. The agents read the
repository; you decide from what the scripts print. A reader's report
is not evidence that it saved anything: the routing and verify lines
are.

## Quoted input

A quoted heredoc hands its text to the script as data. If the shell
refuses the command itself before the script prints anything (an
unexpected end of file, an unmatched quote), the host mangled the
quoting: write the same text with the Write tool to a file in the
survey directory and run the same command with `< <that file>` in
place of the heredoc. Never change the text to make it pass. That
write may ask for permission; if it is refused, or nobody is present
to grant it, stop that step, quote the text in the report so the
transcript carries it, and say which step it was.

## Procedure

1. Facts. Run, relaying every line in one code block:
   `sh ${CLAUDE_PLUGIN_ROOT}/scripts/inventory-repo.sh "${CLAUDE_PLUGIN_DATA}"`,
   with a second argument `4` when unattended; then, with the
   directory its `inventory: dir` line named as the survey directory,
   `sh ${CLAUDE_PLUGIN_ROOT}/scripts/survey-project.sh facts <survey-dir>`;
   the preview exactly as below, with the closing delimiter alone at
   the start of its line (the quoted delimiter keeps every value
   inert); then `sh ${CLAUDE_PLUGIN_ROOT}/scripts/pr-history.sh <survey-dir>`.
   The survey and the preview keep their lines in the survey directory,
   where the later scripts read them, so never pass those lines on
   yourself. If the inventory or the survey refuses (no clone, no
   origin), report its line and stop. If the history fails, relay its
   line and go on without it.

```
sh ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-settings.sh --preview "${CLAUDE_PLUGIN_DATA}" --save <survey-dir> <<'PRWF_SETTINGS_END'
auto_approve ${user_config.auto_approve}
merge_method ${user_config.merge_method}
ci_checks ${user_config.ci_checks}
ci_fix_rounds ${user_config.ci_fix_rounds}
ci_wait_minutes ${user_config.ci_wait_minutes}
review_repairs ${user_config.review_repairs}
branch_sync ${user_config.branch_sync}
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
migration_paths ${user_config.migration_paths}
overlap_check ${user_config.overlap_check}
strong_model ${user_config.strong_model}
self_start ${user_config.self_start}
PRWF_SETTINGS_END
```

2. Reading. Skip this step when the inventory says `tier small` or
   `plan partitions 0`. Attended and the tier is `large` or `huge`:
   ask the first question, quoting the `inventory: estimate` line as
   the ceiling it is (read N partitions on sonnet for at most that
   many tokens, or skip the reading); when the inventory says
   `reading suggested skip`, offer skipping first, as recommended,
   with its reason. On skip, skip this step. Then run
   `sh ${CLAUDE_PLUGIN_ROOT}/scripts/route-models.sh <survey-dir> survey posture=<cost_posture> routing=<model_routing>`
   with the two values the preview showed, and for every
   `route survey cartographer-<id> rung` line spawn one
   `pr-review-workflow:cartographer`, all in parallel, each with its
   line's `model` and `effort` and exactly:
   `Map the repository. Survey directory: <dir>. Partition: <id>.`
   A `skip reason partition-recorded` line is a partition read
   already, on a replay of the same commit; spawn nothing for it.
   When every reader has returned, run the same routing command once
   more, whatever the readers reported: each cartographer line it
   still prints is a partition no record reached. Spawn those once
   more, the same way and at the same level, and never a third time.
   Then run `sh ${CLAUDE_PLUGIN_ROOT}/scripts/verify-claims.sh <survey-dir>`
   and relay its lines; its `missing` list names the partitions left
   unread. When it kept at least one claim, spawn
   `pr-review-workflow:assembler` with the `route survey assembler`
   line's `model` and `effort` and exactly:
   `Draft the conventions block. Survey directory: <dir>.`
   and pipe its whole report into
   `sh ${CLAUDE_PLUGIN_ROOT}/scripts/save-proposal.sh <survey-dir>`
   through a quoted heredoc. A refusal lists every line it refuses:
   spawn the assembler once more with all of them appended to its
   prompt and file the new draft the same way. A second refusal files
   that draft with `--drop-lines` after the directory, which leaves
   the refused lines, and any past the thirtieth, out and names them;
   the report quotes them. Only a draft with no line left is refused
   then, and the report says the proposal was dropped.

3. Advice, audience, and mode. Run
   `sh ${CLAUDE_PLUGIN_ROOT}/scripts/survey-advice.sh <survey-dir> [audience]`,
   passing an audience only when the arguments named one, and relay
   its lines. Its `advice: audience` line is the audience, decided
   once there: the argument, else the settings file already present,
   else the history and the CODEOWNERS file. Every later step uses
   that word. Mode: revising when the chosen file's lines appear as
   `existing` lines (a `survey: located` line says a file of your own
   sits in the main worktree); creating otherwise.

4. Decide each setting, from the lines alone, in this precedence: a
   `key=value` word, then an `advice:` line, then the survey. An advice
   of `auto` leaves the key unset so defaults and per-run routing
   decide; `recommend` goes to the report, never to the file.
   - Profile: the argument; else a `# profile:` comment among the
     existing lines; else `standard`. `economy` with `team` becomes
     `standard`, and the report says why: a shared file can only
     raise a setting. When the advice lines between them set every
     line of another profile in the table below, the question says so
     and offers that profile, and the `# profile:` comment names the
     one the answer keeps.
   - Check command: the first `survey: check` line, whose second word
     names the file that backs it; else an `advice: check_command`
     line, with origin `cartography`. None, and the survey reports a
     conventions block: run
     `sh ${CLAUDE_PLUGIN_ROOT}/scripts/survey-project.sh conventions`
     and take the one test command it names, if exactly one, with
     origin `conventions`. Still none: leave it unset and skip prefixes.
   - Contract prefixes: every `survey: prefix` line, comma-separated,
     only when a check command is set.
   - Sensitive paths: the `advice: sensitive_paths` line when there is
     one, else every `survey: sensitive` line, space-separated.
   - Migration paths: the `advice: migration_paths` line whose value is
     not `recommend`, when there is one. Without one, the patterns in
     force already cover every `survey: migrations` directory; write
     nothing.
   - Local standards, `personal` and `local` only: the `survey:
     standards` lines, space-separated, when the preview shows
     `local_standards (empty)`.

5. Compose the file in this order: `# pr-review-workflow settings:
   <audience>`, `# profile: <name>`, the profile's lines from the table
   below, then one `key value` line per decision.
   - `team`: write the profile's lines even where they equal the
     defaults. A shared file's value is a floor nobody can lower for
     this repository, and that is the point of writing it.
   - `personal`, `local`: drop any line whose value the preview already
     shows `from user`. The file holds only what differs here.
   - Revising: start from the existing lines, change only the keys
     decided above, and keep every other line and comment.
   - Never write auto_approve, self_start, a model, routing, the strong
     model, or ledgers kept. They belong in the plugin configuration
     dialog; a shared file is refused them, and a personal file would
     quietly split this repository from the user's other ones.

6. The question, when a human is present: show the composed file and,
   when one was saved, the proposal's lines after its `proposal:`
   line, and ask once: write the file as shown, switch the profile,
   change a line, or also write the block into the clone's CLAUDE.md
   between `<!-- review-conventions:begin -->` and
   `<!-- review-conventions:end -->` markers (append to the file, or
   create it). Apply the answer; the block is written only on that
   explicit yes, with the Edit or Write tool, replacing an existing
   marked block and touching nothing else in the file. Every check
   command and contract prefix not given as a `key=value` word is
   inferred tooling: list each one on its own line in the question
   with its origin, and say that it runs the project's code on this
   machine in every review round that edits code, so a long suite
   makes every such round that long; that a test suite may create or
   migrate a test database; and that a test command for a whole
   solution or workspace also runs any browser or database suites it
   holds. Write it live only when the answer confirms that command by
   name; otherwise write it as a comment (`# check_command ...`). Show
   every `survey: skipped` line with them, so the user sees which
   candidates were never offered and why. When nobody can answer: turn
   each `check_command` and `contract_commands` line into a comment,
   since those execute, write without asking, leave the proposal in the
   survey directory, and quote its lines in the report, so the
   transcript alone carries the drafted block.

7. Write it exactly as below, with `--replace` only when revising, and
   relay its lines. The writer calls the team audience `shared`: pass
   `shared` when the chosen audience is `team`, and the chosen word
   otherwise. A file of your own written from a linked worktree lands
   in the main worktree, where every worktree reads it, and the writer
   says so. A refusal names the entry a file of that audience cannot
   set: fix that line and write once more. A second refusal stops the
   run with its lines.

```
sh ${CLAUDE_PLUGIN_ROOT}/scripts/write-settings.sh <shared|personal|local> [--replace] <<'PRWF_SETTINGS_END'
<the file>
PRWF_SETTINGS_END
```

8. Rerun the step 1 preview and relay it. Then report, in a few
   lines: the path the writer printed and the audience, the profile,
   each written setting with its origin (`detected from <source>`,
   `advice`, `profile`, `kept`, `given`, `conventions`, `cartography`),
   each `auto` advice and why that key was left to routing, the
   writer's `next:` line, the reading done (partitions read, the
   `missing` list, claims kept, duplicate, and dropped) or why none
   was, where the proposal sits and any lines it dropped, and each
   migration directory found with its evidence and whether the
   patterns cover it. Add one sentence each when it applies: the
   preview said `user 0` (nothing is configured, or with a `user config
   unsubstituted` line the plugin configuration never reached this
   command; `/plugin configure pr-review-workflow` sets the baseline
   this file builds on); an `advice: strong_model recommend` line
   (quote it); an `advice: migration_paths recommend` line (quote it);
   the survey said `base unknown` (`git remote set-head origin -a`
   records the default branch the shared file and the conventions
   block are read from); the survey said `conventions block absent`
   and no block was written (the proposal is ready to paste into
   CLAUDE.md between the markers, and
   `skills/review-pr/project-conventions.md` says what the block is
   for).

## Profiles

| Profile | Lines | Choose it when |
| --- | --- | --- |
| standard | none beyond the detected settings | most repositories |
| careful | `double_review always`, `review_samples 2`, `cost_posture quality` | an escaped defect costs more than a doubled review |
| economy | `cost_posture economy`, `double_review off` | a file of your own, for a repository you pay to review alone; a shared file cannot lower a setting |
