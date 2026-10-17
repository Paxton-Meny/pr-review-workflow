# Changelog

All notable changes to this project are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Base sync. A `branch_sync` setting (off, update, resolve; default
  update, never from a project's shared file) and `scripts/sync-branch.sh`
  bring the pull request branch up to date, before the checks are
  awaited and when the merge gate finds the base moved, whenever the
  forge reports it conflicting or behind a base that requires it up to
  date, at most three times per pull request. The mechanism follows the
  merge method: a rebase onto the base and a push leased on the head
  the run last saw (`push-branch.sh --force-with-lease`) under rebase
  merging, a merge of the base into the head and a plain push
  otherwise. Conflicts are aborted and handed to a person under update;
  under resolve the editor resolves them and continues through the
  script, with the files whose change the resolution touched reviewed
  before the checks run. A new `conflict` route stage puts the editor
  one level up for it. The run statistics record the updates and the
  conflicts met.

- A follow-up on the pull request's checks after the review converges.
  `ci_checks` (off, wait, fix; default fix) decides it: `await-checks.sh`
  waits for the head's checks when the repository reports any, in
  slices under a wait budget (`ci_wait_minutes`, default 30, kept per
  head on disk), reruns a cancelled Actions run once, and on a failure
  writes a capped digest (names, links, annotations, the failed steps'
  log with colour and timestamps removed) for the editor, with a
  signature that reads the same failure after a repair as a repeat.
  The editor diagnoses, posts its paragraph as a comment, repairs,
  commits, and pushes; a repeat escalates the `ci-repair` route one
  lever and tells the editor its last fix was not enough; repairs are
  capped by `ci_fix_rounds` (default 2) on disk. `review_repairs`
  (default on) gives every repair an incremental review before the
  merge gate. The run statistics record how the checks ended and the
  repairs made.

- A `merge_method` setting (auto, merge, squash, rebase; default auto)
  and `scripts/merge-method.sh`, which decides how a pull request merges:
  the setting, else the one method the repository allows, else the method
  its last thirty merged pull requests into the same base branch used,
  each classified by its merge commit in the clone, judged first among
  pull requests of the same shape (one commit or several). Mixed
  evidence asks an attended user and parks an unattended run with the
  counts; the run never guesses a history shape. A project's shared file
  may set it. The run statistics record the method.

- `scripts/local-diff.sh`: builds a pull request's diff from the clone
  when GitHub refuses to serve it (very large pull requests get an HTTP
  500 from the diff endpoint). It is the diff GitHub shows, merge base
  of the base branch and the head to the head, with `a/` and `b/`
  prefixes, three context lines, renames, and unquoted paths whatever
  the user's git configuration says. The head is fetched through
  `refs/pull/<n>/head` when the clone lacks it, which outlives a
  deleted fork, then through the head branch as the checkout does.
- Continuous integration. `.github/workflows/tests.yml` runs the
  offline suite (`sh tests/run.sh`) on every pull request and every
  push to main, with nothing from outside the repository: no actions,
  packages, or caches. Its token only reads, reaches git through the
  environment rather than argv or `.git/config`, and never reaches the
  suite; fork pull requests run unprivileged. `t-ci-workflow.sh` fails
  the gate if the workflow gains outside code, a privileged trigger, a
  wider permission, or an expression inside a script.

### Changed

- `merge-pr.sh` merges by the decided method instead of always by
  rebase, names the head the run last saw so an unseen push refuses the
  merge, and deletes the head branch only when the repository does not
  delete it itself, no open pull request bases on it, and it is not a
  fork's. A conflicting pull request, or one behind a base that requires
  it up to date, is refused with exit 5 and nothing written, so the run
  can hold or park instead of stopping on an error.
- A refused conventions proposal lists every offending line at once,
  and a second refusal files the draft without those lines
  (`save-proposal.sh --drop-lines`) instead of dropping the proposal.
  The assembler is told that every token holding a slash is a path.
- The survey and preview save their lines in the survey directory
  (`survey-project.sh facts <survey-dir>`, `resolve-settings.sh
  --preview --save`), and `verify-claims.sh` and `survey-advice.sh` read
  them there, so the orchestrator no longer retypes them into a
  heredoc. The skill falls back to a file when a host mangles a quoted
  heredoc.
- `survey-advice.sh` decides the audience once, from the argument, the
  settings file already present, then the history, and always prints
  it; the survey's own audience suggestion is gone.
- A sensitive directory found by content needs both two hits and a
  fifth of its files.
- A .NET tree with several test projects, or a browser suite, offers
  each other test project as its own check candidate and lists the
  browser suites as skipped; every check candidate is named after the
  file that backs it.
- A migrations claim stands only for a directory outside the tests that
  holds a `.sql` file or a file the migration pattern matches.
- Pull request history counts only pull requests into the base branch
  and leaves out syncs between long-lived branches.
- A personal or local settings file written from a linked worktree
  lands in the main worktree, where every worktree reads it, and the
  writer prints the path it wrote.
- The inventory labels its estimate a ceiling and suggests skipping
  the reading when the root rules file already holds a conventions
  block or 150 lines of rules.
- The settings preview says when every plugin configuration value
  arrived as a literal placeholder.

- `fetch-pr.sh` falls back to the clone instead of stopping when the
  API refuses the diff. The file list then comes from the same diff,
  since the API's file list is capped as well, and `meta-full.txt`
  records `diff_source api` or `diff_source clone`. The review skill
  relays the fallback; the size warning still parks oversized pull
  requests unattended.

### Fixed

- Setup's inventory counts files the same under every awk. It passed
  the binary-extension pattern to awk as `\.`, which mawk keeps but GNU
  awk warns about and reads as any character; the warning landed in
  the skipped-files count, and a name like `logopng` counted as binary.
  The pattern now uses `[.]`, which needs no escape.
- An editor batch that commits outside the review worktree now stops
  the run instead of reporting success. The editor's definition names
  the worktree (`<state-dir>/worktree`) and says its working directory
  and `repo_root` are the user's own clone. `push-branch.sh` exits 3
  when the worktree holds nothing new to push, or, on a plain push,
  lacks a commit an addressed finding records, so its proof no longer
  passes on a push that moved nothing. `update-finding.sh` refuses a
  `commit=` the worktree's history does not contain.
  `reply-thread.sh --addressed <id>` composes the "Addressed in"
  reply from the record, and only once its commit is on the head
  `push-branch.sh` proved on the remote; a reply on stdin may not claim
  a fix. The editor now marks each finding before replying to it.
- The run guards the user's checkout around every editor spawn.
  `checkout-guard.sh <dir> before|after` snapshots its head, branch,
  local branches, status, tracked changes, and untracked contents, and
  `after` exits 3 naming every difference, which stops the run.
- Repositories that do not allow rebase merging can now be merged by
  the plugin.
- Setup readers no longer lose their slice when they stop early. Hosts
  that deliver a subagent's report only through a hand-back tool force
  an agent that ends a turn on plain text to report at once, so a
  cartographer that announced its save instead of making it returned a
  stub and saved nothing. The cartographer now saves each section as it
  goes (`save-record.sh --append`), never ends a turn on an announced
  step, and reports `record: <id> unsaved` rather than a stub.
- The setup skill checks the reading by files, not by what readers
  report: survey routing skips partitions already recorded, so the
  same call plans one retry, at the same level, of any partition no
  record reached, and `verify-claims.sh` names the partitions still
  missing.
- `verify-claims.sh` counts duplicate claims, so kept, duplicate, and
  dropped add up to the claims read.
- A personal file's `migration_paths` advice repeats the patterns in
  force, since a personal file, like a local one, replaces the list.
- A moved HEAD clears the records, digest, and proposal of the old
  reading plan.
- Inventory and review routing count `App.Tests/`, `App.Test/`,
  `UnitTests/`, and `FooTests.cs`-style files as tests.

### Security

- The data directory is private to the user. `init-state.sh` and
  `inventory-repo.sh` set it to mode 700 whenever they write state, so
  a umask of 0002 no longer leaves ledgers, surveys, and settings
  readable by other accounts on the machine.

- A Check line's arguments cannot reach outside the worktree.
  `run-contract.sh` allowed quotes, globs, `~`, and absolute paths after
  the approved prefix, so `pytest --basetemp=/home/you/projects` would
  empty that folder. Arguments after the prefix that are absolute, start
  with `~`, or hold a `..` segment, also after an `=`, or that contain
  any of `'"*?[]{}()#!`, are now refused as `unsafe-argument` and the
  finding is judged by reading; `./...` package patterns still run.

- Local standards come only from files git does not track.
  `extract-standards.sh` read any file a configured glob matched, so a
  committed file, which anyone who can commit could write, was applied
  as the user's own standards. Tracked files are now skipped with an
  `extract-standards: skipped <path>: tracked by git` line, as
  `resolve-settings.sh` already skips a tracked personal file.

- A fork's head is fetched from origin's pull request ref first.
  `checkout-pr.sh` fetched the fork by branch name with no `--`, so a
  head branch shaped like an option, such as `--upload-pack=...`, would
  be read as one. It now fetches `refs/pull/<n>/head` from origin, as
  `local-diff.sh` does, and falls back to the fork's branch only when
  that lacks the head; every branch fetch puts `--` before the remote.

- A team's shared file raises review samples only with consent. Each
  sample is another full reviewer pass, so a committed `review_samples
  3` tripled the first review's cost on every teammate's bill. A raise
  above what the user's own sources give now joins the check command
  and contract prefixes in the trust-on-first-use hash, reported as
  `settings: trust pending <hash> review_samples <n>` and applied once
  approved; an unattended run keeps the user's value.
- A push made after the review no longer merges unread. The ledger
  keeps the head the review last covered (`reviewed_head`), which a
  resumed run carries over instead of taking GitHub's head;
  `scripts/reviewed-head.sh` reports a head that moved since, the run
  reviews the files the new commits changed and marks the head, and
  `merge-pr.sh` refuses any other head (exit 6) and pins the merge to
  the reviewed one.

- Auto-approve merges only a pull request whose author can push to the
  repository. `init-state.sh` records the author's permission,
  `scripts/author-trust.sh` trusts the account's own pull requests, write,
  maintain, and admin permission, and a branch in the repository when
  GitHub cannot say; `merge-pr.sh --approve` refuses anyone else (exit
  7) and the run asks, or parks unattended. The review is a model
  reading what the author wrote, so a stranger's text alone never
  merges it.

- Credentials are masked before anything posts. `scripts/redact.sh`
  replaces known token formats, private key blocks, and credentials in
  URLs with `[redacted: <kind>]` in finding bodies, the round summary,
  thread replies, and status comments. Status comments now go through
  `scripts/post-comment.sh`, which posts only to the run's pull request
  and adds the attribution line itself, in place of a `gh pr comment`
  grant that matched any repository and any body file.

- The plugin's agents are held to their definitions. A PreToolUse hook,
  `scripts/agent-scope.sh`, acts on calls Claude Code attributes to one
  of the plugin's agents (2.1.69 and later): reads stay inside the
  data directory, the plugin, and the session's folder, without `..` or
  symlinked files; edits stay inside a review worktree; and shell
  commands are only `git -C` into the data directory with the agent's
  own subcommands and the plugin scripts it names, without expansion,
  redirection, chaining, file-reading git options, or a status change
  outside its role. `append-note.sh` refuses a note that adds a Check,
  Resolution, or Fix line or a suggestion fence.

- The check command, suggestion proving, and contracts run only on code
  from an author who can push to the repository. For anyone else
  `run-check.sh` skips, `prove-suggestions.sh` proves fences by applying
  alone, `run-contract.sh` judges by reading (`untrusted-author`), and
  routing stops counting on the gate, until the user approves that
  author for the pull request (`approve-author.sh`, which asks the user to allow it); unattended
  runs skip the check and say so.

- Finding fields are read from the record's header only. A body
  quoting a line such as `status: ready` from a YAML file stopped the
  run in `count-findings.sh`, and a quoted `path:` line hid an edit to
  that file from the incremental review; every reader now stops at the
  header's `---`, and `update-finding.sh` rewrites header lines only.

- The start gate's decision is always one valid JSON line. A refusal
  quoting a multi-line error, as gh's own stderr is, printed raw
  newlines inside the reason; Claude Code then saw no decision, and the
  call either failed as a hook error or, before `onFailure: "block"`,
  went through without the gate.

## [0.3.0] - 2026-10-13

### Added

- Setup infers where migrations live by reading the clone: content
  markers, file names, and the configuration that names a location,
  across Django, Alembic, Rails, Laravel, Ecto, Knex, TypeORM, goose,
  golang-migrate, Flyway, Liquibase, sqitch, Diesel, and Prisma, and for
  .NET and SQL Server, EF Core, FluentMigrator, DbUp, and SSDT schema
  projects. Cartographers may claim a migrations directory a document
  names. Directories the patterns in force miss are advised as extra
  `migration_paths` patterns, and a directory only named like
  migrations that the patterns catch is a recommendation to narrow
  them. Migrations leave the sensitive-names list, since their own
  setting already routes them as sensitive.
- Setup finds a .NET solution below the root, the usual Blazor layout,
  and offers `dotnet test <solution>` with `dotnet test` as a prefix.
- The schema probe reads EF Core `MigrationBuilder`, FluentMigrator,
  and T-SQL `sp_rename` operations, and tags a regenerated EF model
  snapshot as a snapshot rather than an edit to a shipped migration.
- Migration awareness. A new `migration_paths` setting names where a
  repository keeps database migrations, defaulting to the common
  layouts (`*[Mm]igrations/* *[Mm]igration/* *db/migrate/*
  *alembic/versions/*`); a project's shared file adds to it. The
  probes list each changed migration as added, modified, or deleted,
  treat it as a sensitive path for routing, and point at schema
  operations in its added lines. The reviewer judges migrations for
  harm to databases and code other developers already run, and for
  table rewrites and locks.
- `scripts/match-paths.sh`, the one matcher for path-glob settings,
  shared by the sensitive and migration probes and the merge gate.
- `/pr-review-workflow:setup` writes a repository's settings file from
  what the clone and its history already state, asking at most twice,
  and works on a repository the plugin has never seen. A survey script
  reads the check command from the Makefile, package manifest,
  toolchain files, or CI workflow, the test runner prefixes a Check
  line could start with, directories whose names mark them sensitive,
  the ignored files at the root whose names mark them as rules, how
  many people commit, and whether a conventions block exists. An
  inventory script classifies every tracked file, finds every
  CLAUDE.md and AGENTS.md at any depth, the docs, and the directories
  whose code matches the sensitive probe, sizes the repository into a
  tier, and plans the reading: nothing on a small repository, up to
  four, eight, or sixteen partitions otherwise, docs first, each with
  a file and line budget, with an upfront estimate. A history script
  reads the last hundred merged pull requests in one `gh` call and
  reports sizes by author; an advice script turns inventory and
  history into pin-or-auto decisions with explicit thresholds, so a
  developer whose sizes vary widely keeps per-run routing while
  sensitive code or fork contributors turn the second review pass on.
  Cheap parallel cartographer agents read the partitions and file
  typed claims through a validating script; a verification script
  drops every claim the tree cannot confirm; an assembler agent drafts
  the conventions block from the verified digest, and a proposal
  script refuses any path the digest does not back. The router gained
  a `survey` stage for those spawns. The skill decides the audience
  (team, personal, or local) and a profile (standard, careful, or
  economy) unless told, composes only the lines that differ, shows the
  file beside the drafted block, and writes the block into CLAUDE.md
  only on an explicit yes. Unattended, it reads at most four partitions
  and comments out the lines that would execute. The resolver gained
  `--lint`, which judges a file as the shared or a personal source
  before it exists anywhere and names every entry it would refuse, so
  a committed file never carries a line the review would ignore. A
  writer script lints, places the file atomically, refuses a shared
  file on an ignored path and a personal one on a tracked path, and
  excludes a personal file from git. The classify, probe, and survey
  scripts expose their file classes, probe patterns, and directory
  lists so the inventory shares them instead of carrying copies.
- The first comment each review posts ends with one line naming and
  linking the plugin, so readers can see which tool reviewed the pull
  request. Later comments never repeat it.
- The reviewer checks documentation the diff never touches: it greps
  the repository's docs for each option, command, or behavior the
  change alters, and flags a new user-facing option missing from docs
  that already describe its siblings. A repository without user docs
  is not owed new pages.
- `/pr-review-workflow:status` previews the settings a review started
  in the current clone would use, each with its source, and any
  command from the project's shared file still awaiting approval. It
  reads the base as of the last fetch and writes nothing.
- The settings reference explains where settings come from: the five
  sources and their order, the file format, that the project file
  may be committed for the team or kept out of version control as
  your own, what a committed one may set and why, and a team setup
  that never asks you to commit Claude Code's own settings. Every entry shows what the
  shared file may do with it, and a test holds those markers to the
  resolver's own lists.
- A `sensitive_paths` setting: globs for files where a defect costs
  most. A change touching one counts as a sensitive probe hit, so the
  reviewer may climb to the strong model, no fix there starts cheap,
  and the second review pass runs under the risky setting. A
  project's shared file adds its patterns to yours rather than
  replacing them.
- Per-project settings. A repository can commit
  `.claude/pr-review-workflow.conf`, read from the pull request's base
  branch and never from disk, and you can keep an untracked
  `.claude/pr-review-workflow.local.conf` in your clone; precedence
  runs defaults, your configuration, the shared file, your local file,
  then per-run overrides. The shared file may never set auto-approve,
  the models, routing, ledgers kept, or local standards; may only
  raise the second review pass, the precision filter, the cost
  posture, and review samples; and its check command and contract
  prefixes apply only after you approve that exact pair, asked once
  per change on an attended run and ignored on an unattended one.
  A project file git does not track, because the repository excludes
  it or it was never added, is yours: read from your clone, free to
  set anything, and still outranked by your local file. One tracked in
  your clone but missing from the base branch is refused. A tracked or
  symlinked local file is refused, an offline run reads the last
  fetched base, and every refusal is reported. No script reads Claude
  Code's own settings files. The statistics line records the highest
  source used.
- The scripts make every settings-driven decision and print it: the
  router says whether the gap pass, the filter, and arbitration run,
  and how many review samples each group gets; the check baseline is
  recorded on disk per command, so the gate survives a resume, and a
  changed check command is baselined again before it gates anything.
- Scripts read the run's resolved settings themselves, checking the
  record against the hash kept outside the state directory, so a
  changed settings.txt is refused rather than trusted. The agents no
  longer carry settings at all, and the skill resolves once per
  invocation, a resume included.
- `resolve-settings.sh` resolves a run's settings from the manifest
  defaults, the user's plugin configuration, and the per-run
  overrides, in that order, into a read-only settings.txt with a
  sources record and a hash kept outside the state directory. An
  invalid value is reported and falls back to the source below it;
  a placeholder from an unconfigured install counts as unset. Short
  aliases (posture, samples, check, prefixes, ...) are accepted.
- Per-run settings typed after the pull request,
  `/pr-review-workflow:review-pr 128 posture=quality`, are parsed and
  recorded in the ledger for that invocation only; a later invocation
  without them clears them. They take effect once the settings
  resolver lands.
- Claude can start a review on its own once the work on a branch is
  finished. A hook the plugin ships checks the pull request before
  the skill loads: a merged or closed one is refused, and a new
  `self_start` setting (ask, auto; default ask) decides whether you
  confirm. With auto, a ready pull request starts without a question;
  a draft, an existing review, failing checks, uncommitted or
  unpushed work, or an earlier run on this machine still asks, and
  the question says why. The hook reads `self_start` through the
  settings resolver, so your own project file or local file can set it
  per repository; a committed project file and per-run words cannot. A
  review Claude starts must pass exactly the pull request and
  `auto_approve=false`, so it never merges without asking and never
  carries a per-run setting Claude wrote. Typing the command works as
  before and is never asked about.
- An escalation ladder for fixes. Every editing attempt is noted on
  the finding's record with its round, rung, model, effort, and
  reason; a finding attempted and still open climbs one rung above its
  last attempt, and a repair after a failed check gate climbs one rung
  above the batch that broke it. A new `cost_posture` setting
  (quality, balanced, economy; default balanced) decides how readily a
  fix starts on the cheap model: proven suggestions only, also fixes
  whose Check line will execute, or any fix once a check command gates
  the round. A blocker, a security finding, or a file the secrets or
  sensitive probe flagged never starts cheap. The contract runner
  gains a policy-only mode the router uses to tell an executable Check
  line from one judged by reading, and the statistics count
  escalations.
- Routing decides per unit of work. A sharded review is routed group
  by group on each group's own files, so a documentation group runs
  on the cheap rung while an authentication group climbs, and the gap
  pass takes the highest rung any group used. A first editing round
  splits into a mechanical batch and the rest when each holds at
  least two findings, run one after the other with the check gate
  after each, so a broken check is pinned on the batch that broke it.
- Model routing is a script, `route-models.sh`, that prints one
  `route` line per decision with its rung, model, effort, and
  reason, and keeps them in the ledger. The skill passes the model
  and effort it names instead of choosing them. Large means over 800 changed lines of
  code, with tests, docs, and configuration no longer counted. When a
  change calls for a stronger model and none is set, the route says
  so and the final report repeats it. Each run's statistics line
  gains the count of decisions per rung, and the status report sums
  them.
- Reasoning effort is routed per unit of work, beside the model, so no
  agent inherits whatever level the session runs at. Each starts at
  its definition's level (the reviewer high, the editor and the
  verifier medium, the filter low) and moves one level per signal. It
  goes up for a wide search: over 800 lines of code unless a stronger
  model takes it, a shard on a seam, a gap pass over seams, each
  earlier attempt at a finding. It goes up for stakes: a secrets,
  automation, or sensitive probe on a review, and a blocker, a
  security finding, or a file the secrets or sensitive probe flagged
  on a fix or its verification. It goes down only where a later step
  checks the work: for the editor, a minor or nit fix carried by a
  proven suggestion; for the verifier, a finding an executable Check
  line or a proven suggestion settles; and for a small docs or config
  review. An editing batch or a verified round runs at its highest
  finding's level. The economy posture caps effort at high, the others
  at xhigh, and fixed routing keeps each definition's level. The
  incremental review after a round gets its own route at the
  reviewer's model and level. Route lines and Route notes record the
  level, and a pinned CLAUDE_CODE_EFFORT_LEVEL as such. The one
  arbitration pass before a run parks spawns the verifier at high
  effort on the strong model, else the reviewer's, so its Arbitration
  section stays the one copy of that procedure. Needs Claude Code
  2.1.292 or later.
- Run statistics count route lines per effort level and pinned lines,
  and every retry of a finding by what it changed from the attempt
  before: the model, only the effort, or nothing. A repair after a
  failed check gate belongs to its round rather than counting as a
  retry, and a retry from a note that predates effort, on the same
  model, is left out. A retry another attempt followed counts as
  failed. A finding's last retry succeeds when the verifier verifies
  it, fails while the finding is open or addressed, and is left out
  when it ended wont-fix or arbitration verified it; update-finding.sh
  now marks that verdict with an Arbitrated note. The status skill's
  report sums all three, so whether a stronger model or more effort
  fixes a finding more often than a plain retry can be settled from
  recorded runs.
- A settings reference page on the site: every setting explained in
  plain terms, with a switch on each entry showing what each value
  changes on a pull request, when to choose it, how the five model
  settings combine, and a glossary for the terms the descriptions
  lean on. The page works without scripts, loads nothing from other
  origins, and a test holds its keys, defaults, and options to the
  plugin manifest.
- Issue forms replace the markdown issue templates: structured bug
  and feature forms, a dedicated commercial license inquiry form,
  and contact links to the site and the security policy. A
  CITATION.cff makes the project citable, and CONTRIBUTING now
  documents the release ritual, proofs first, in order.
- A status skill: /pr-review-workflow:status lists recorded runs
  for the current repository or all of them, with finding outcomes
  and resumability, and summarizes the stats ledger
  (stats-report.sh: outcomes, a rounds histogram, finding totals),
  reading local state only.
- A commercial licensing section on the site and in the README:
  what needs a commercial license and how to start the
  conversation, so the dual-licensing model has an operable path.

### Changed

- Inferred tooling waits for a person. Setup lists every inferred check
  command and contract prefix on its own line in its question, says it
  runs the project's code and may create or migrate a test database,
  and writes live only the commands confirmed by name.
- Migration and database tooling is never offered or run, through one
  matcher, `scripts/migration-tool.sh`: the survey prints such a
  candidate as skipped, verification drops such a check claim, and
  `run-contract.sh` refuses it. The matcher now also knows `dotnet ef`,
  the Package Manager Console verbs, `sqlpackage`, `sqlcmd`,
  RoundhousE, and the `psql`, `mysql`, `sqlite3`, and `mongosh`
  clients.
- The merge checklist asks whether the model snapshot, as well as the
  numbering or parent, is still the latest.
- A pull request that changes migrations never merges without a
  person, auto-approve included. `merge-pr.sh` refuses with exit 4 and
  lists the migrations, and the skill asks the user to confirm what
  one pull request cannot show: no newer migrations on the base
  branch, no other open pull request adding migrations in the same
  directories, code teammates run still working against the new
  schema, and no shipped migration edited. Only their answer adds
  `--migrations-checked`; an unattended run parks with that
  checklist. A forge file list shorter than the changed-file count is
  refused the same way, since it cannot rule migrations out.
- Migrations are read, never run. The editor and verifier never run
  migration tooling or anything that reaches a database, and
  `run-contract.sh` judges a Check line naming migration tooling by
  reading, even under an allowed prefix.
- Every review now starts with the sweep that used to run only after
  a merge, and the sweep covers every repository: a run whose pull
  request merged or closed outside this tool loses its worktree and
  fetched context at the next review anywhere, instead of waiting for
  a merge by this tool in the same repository. Finished ledgers are
  still kept per repository, up to the configured count.
- Holding a converged pull request drops the run's worktree and
  fetched context, keeping only the ledger, since a resumed run
  fetches and checks out again. The run's outcome is recorded in
  the ledger, so a held, parked, or review-only run stays resumable
  without a worktree, and the status skill lists it as such.
- The editor's thread reply names the fixing commit by sha and subject,
  so the reference still finds the commit after a rebase rewrites the
  sha.
- The cost posture now leans every routing decision the change itself
  does not settle, instead of only where a fix starts. Economy counts a
  change as small enough for the cheap reviewer under 500 lines and
  lets a tests-only change drop too, counts code as large over 1,200
  lines, and still caps effort at high. Quality counts small under 150
  and large over 400, and pays for one review sample beyond the
  setting on a group a secrets, automation, or sensitive probe
  flagged, never above three. Balanced keeps 300 and 800. Nothing is
  pinned: a posture moves the lines routing judges the change against,
  and fixed routing honors only its effort cap. A stakes probe now
  climbs the reviewer to the strong model whatever the kind of file,
  so a token in a configuration file or a workflow edit is routed like
  one in code.
- The model and the effort are routed as two levers moved by different
  evidence. The model climbs on depth: a stakes probe, a sensitive
  path, or, new, code whose changed files reference one another (6, 4,
  or 2 couplings under economy, balanced, or quality, counted by the
  shard planner for the run). Effort climbs on breadth: a
  seam, a gap pass over seams, high stakes, and size or coupling when
  no stronger model takes it. A fix that fails now tries again one lever
  up instead of two: more effort on the same model while the editor is
  below its cap, then the next model at that effort, so each retry's
  statistics name the one lever it pulled. A signal is paid for once:
  when a stronger model takes a climb, the signal leaves the effort
  alone, and effort reaches xhigh only under the quality posture,
  since on agentic coding the top level buys little for its cost.
- The shard limit follows the cost posture: a change splits into
  parallel reviewer shards over 2,250 changed lines under economy,
  1,500 under balanced, and 1,000 under quality, so economy keeps one
  reviewer, and skips the gap pass a sharded review always gets, up to
  a larger change, and quality puts a second reader on a smaller one.
  The planner reads the limit from the run's settings and names it in
  its result, a change under the limit leaves no plan file, and the
  skill no longer holds the number.
- A round's summary comment now posts before its inline findings, so
  the pull request's conversation opens on the overview.
- The README leads with a restrained badge row (release, license,
  site), a contents line, and folds the optional conventions-block
  detail behind a summary, so the install path and the figures stay
  above the depth.
- The project site is redesigned from a reviewed set of design
  comps: editorial serif display over the system sans, a sticky
  section nav, a hero led by the animated loop figure, an install
  band, the finding record as an annotated card with its contract
  lines keyed by color, licensing cards, and tables that scroll
  inside their card on narrow screens, in light and dark.
- The site now carries link-preview and social metadata: Open Graph
  and Twitter cards backed by a generated brand-mark image, a
  favicon in the loop's own mark, canonical URL, and theme colors
  for both schemes.

### Fixed

- A run whose spawn tool has no effort parameter no longer drops the
  routed effort silently. The orchestrator records once per
  invocation whether the tool takes one (`route-models.sh <dir>
  spawn-effort applied|unapplied`). Unapplied, every route line and
  Route note names the level the agent runs at, its definition's, as
  `unapplied <level>`. A retry climbs the model instead of pulling an
  effort lever that does nothing, and the final report says efforts
  were not applied. Run statistics gain an `unapplied` count, and
  retries read unapplied attempts at the level that ran, so a run
  like this no longer shows effort climbs that never happened.
- The skill no longer tells the orchestrator to pass `inherit` as a
  model override, which the spawn tool rejects: an inherit route now
  means omitting the model, and arbitration on an inherited reviewer
  model passes the session model's alias so the verifier does not
  fall back to its own default. The self-start hint names the exact
  argument form, so a first attempt is not refused by the gate.
- The start gate runs again on an install that never saved the
  self_start option. The hook named the option as an argument, and
  Claude Code refuses to run a hook whose option is unset, default or
  not, which blocked every review Claude tried to start. The gate now
  reads the option from the environment Claude Code exports to hook
  processes, and falls back to ask.
- Saving findings into a ledger that already holds F008 or F009 no
  longer fails: the ids were read as octal by the shell's arithmetic,
  so every save after the eighth finding stopped the run. Leading
  zeros are now stripped before the next id is computed.
- An arbitration that upholds a reopen no longer fails on an illegal
  open-to-open transition: the finding is already open, so it gets the
  note and the thread reply and keeps its status. Only open findings
  are sent to arbitration, so one verified after three reopens is no
  longer judged again.
- A round whose every finding the precision filter demoted now posts
  its summary comment. Before, nothing posted and the demoted findings
  never reached the pull request.
- A check command or contract prefix containing a single quote no
  longer breaks the shell commands it was pasted into: settings reach
  the scripts through the resolved record, and `${user_config}` now
  appears only in the one quoted heredoc that feeds the resolver.
- The base branch is fetched with an explicit refspec, so a clone made
  with --single-branch still reads the conventions block from a
  pull request's non-default base instead of silently skipping it.
- The invocation text reaches the first script on stdin through a
  quoted heredoc, never pasted into a shell command, so quotes and
  command substitutions typed after the pull request stay inert.
- The run figure is drawn as three labeled lanes, GitHub, scripts,
  and models, with the scripts as the backbone, so who does each
  step is read from position instead of from a color legend.
- The origin rule reads in order now, condition before consequence,
  says plainly that it is the only tie between plugin and
  repository, and the site shows the check as a small two-row
  graphic.
- The hero now follows one finding from review to merge, the same
  F003 example the findings section uses, and the fully labeled
  loop figure moved to its own full-width card in the run section:
  at hero scale its labels were unreadable.
- The loop figure reads left to right, first review in and merged
  out, with its stations outside the ring, the reopen path passing
  the round counter, and the round budget in the center. The
  information figure shows the script lines the orchestrating
  session actually sees above the ledger's real directory and all
  four agents. The favicon and social card are redrawn to match.
- The README has install instructions, matching the site, which now
  also shows the one-step install for Claude Code 2.1.275 or later.
  Its project structure lists every skill, agent, and top-level
  directory.
- The repository is now the marketplace the README always claimed:
  a marketplace manifest lists the plugin at the repository root,
  so the documented install commands work. They could not have
  before, because the manifest did not exist.

## [0.2.1] - 2026-10-04

### Changed

- The security policy states the real support stance now that
  releases exist, the README status no longer counts releases, and
  CONTRIBUTING explains why external code contributions stay closed
  under the commercial licensing model while welcoming issue
  reports.

### Changed

- The project site's footer now states the PolyForm Noncommercial
  license; it still said Apache-2.0 after the relicense.
- Relicensed from Apache-2.0 to the PolyForm Noncommercial License
  1.0.0, with commercial licenses available from the maintainer by
  arrangement. The two Apache-era releases and tags were withdrawn
  while the repository had zero forks, clones, and external views,
  so no Apache-licensed copy was ever distributed.

### Added

- A NOTICE file and a README license section carrying the copyright
  notice, so redistributions have attribution to preserve, per the
  license's notice clause.
- A code of conduct, completing the documentation set ahead of the
  repository going public.

### Fixed

- The skill spawns its agents by their namespaced names
  (pr-review-workflow:reviewer and so on), so another installed
  plugin shipping an agent called reviewer, editor, verifier, or
  filter can never be picked up by mistake.

## 0.2.0 - 2026-10-03

### Fixed

- Fix commits are now authored as the signed-in GitHub account, with
  its noreply address, never the clone's ambient git identity:
  init-state banks self_login and self_email in the ledger and the
  editor commits with them explicitly. The third dogfood run's
  commits showed up on the pull request as the machine's default
  identity.
- init-state now refuses to run from a clone whose origin is not the
  reviewed repository, before any state is written or the pull
  request is fetched; the first interactive dogfood run reached step
  4 before checkout-pr caught the same mistake, leaving a part-built
  ledger behind.
- The skill now recognizes unsubstituted user_config placeholders as
  an unconfigured install, runs on manifest defaults, and says so in
  the final report. Loading with --plugin-dir never shows the
  configuration dialog; the README now says to run /plugin configure
  in the session.
- The settings block annotates every default inline, because an
  unconfigured orchestrator cannot see the manifest: the second
  dogfood run spawned its verifier on the session model instead of
  sonnet for exactly that reason.

### Changed

- The content-leakage criteria gain a license-provenance item, the
  first criterion grown from a live criteria signal: the inaugural
  dogfood run filed GPL-copied code under other because nothing
  named it. Final reports now quote the run-stats line verbatim
  alongside the criteria signals, since paraphrases lose the lines
  the tuning process greps for.

### Added

- An animated figure (docs/assets/loop.svg): the review-revise cycle
  from above, hand-written SVG with CSS animation, dark-mode aware,
  showing a run that reopens once, laps the loop again, and exits on
  its second of four budgeted rounds.
- An experimental eval suite under evals/ for `claude plugin eval`:
  a smoke case proving the skill reaches for its script layer first,
  names where the run stopped, and fabricates no finding ids even
  with Bash withheld by the sandbox. Run by hand before releases; the
  offline gate never spends model tokens.
- Run statistics (`run-stats.sh`): every finished run, merged or not,
  appends one summary line (rounds, finding outcomes, reopens, filter
  demotions, contracts, samples, change kind, groups, seams) to a
  stats file beside the ledgers, so thresholds and gating rules can
  be tuned from evidence instead of guesses.
- Opt-in multi-review aggregation (`review_samples`, default 1): the
  first review can run two or three independent passes per shard, and
  `dedup-findings.sh` merges duplicates into the richest record with
  a support count the filter weighs. Detection recall rises at
  roughly the sample multiple of the review cost.
- A precision filter (`finding_filter`, default on): before findings
  post, a cheap second context re-reads each one's cited code cold
  and demotes findings the fresh evidence cannot support into the
  round summary, with the doubt recorded as a note. Nothing is
  dropped or closed, and demoted findings are still addressed.
- Coupling-aware shard planning (`shard-plan.sh`): large diffs are
  split by clustering files whose changes reference each other rather
  than by raw file order, the plan persists so resumed runs shard
  identically, and every coupling that still crosses a shard boundary
  lands in seams.txt, which the gap pass inspects first.
- Executable Resolution contracts: a finding may carry one `Check:`
  line, the check command narrowed to the relevant test, and the
  verifier runs it instead of judging prose; the editor reruns it
  before committing a fix to a reopened finding, discarding candidates
  the contract rejects. A Check line executes only when it starts with
  the configured check command or a prefix from the new
  contract_commands setting and contains no shell metacharacters;
  otherwise verification falls back to reading. Fix lines now bank
  exact edit-location spans, and the verifier judges diffs and code
  only, never commit messages.
- Dynamic model routing (`model_routing`, default auto): a
  deterministic classifier (`classify-change.sh`) types each change,
  and small docs-only or config-only changes with no risk probes get
  a sonnet reviewer, a first editing round whose open findings are
  all minor and fence-backed gets a sonnet editor, and a finding
  reopened past the limit gets one strong arbitration pass before
  the run parks. With a strong model configured, large code changes
  and probe-flagged sensitive code climb above the session model,
  and arbitration uses it. The gap pass never routes down; fixed
  restores static models.
- A test-shrink probe: test files whose diff deletes more lines than
  it adds are flagged as possible assertion weakening, and the slug
  blocks reviewer down-routing.
- A sensitive probe: concurrency, crypto, auth, and injection
  surfaces in added lines become reviewer leads, block down-routing,
  and route the review up when a strong model is set.
- count-findings --list now also reports `open_mechanical_ids` (open
  findings that are minor or nit and fence-backed) and `capped_ids`
  (findings past the reopen limit), the facts routing decides on.
- Enum pickers on the second-review-pass and model-routing settings,
  and a README cost-notes section covering subagent cache lifetimes
  and the environment variables that interact with model routing.
- A post-merge sweep: stale runs whose pull requests closed outside the
  tool are cleaned, and finished ledgers are retained per repository up
  to a configurable count.
- A project site under docs/: one hand-written static page reusing the
  README figures, ready for GitHub Pages branch deployment at
  go-public time.
- README figures: the layered pipeline and the information-flow map as
  hand-written, dark-mode-aware SVG under docs/assets/.
- A gap pass: a second reviewer that reads the first pass's findings
  and reports only what they miss, run after every sharded review
  because only a whole-diff pass sees defects that span shards, and
  otherwise always, never, or when the probes say the change is risky.
- The check gate: with a check command configured, every editing round
  must leave the project's own check passing before verification runs,
  with one bounded repair attempt on failure.
- Reviewer hardening from the comparison: an explicit refutation step,
  probe leads and excluded-file handling, resource-lifecycle and wiring
  items under correctness, executable-automation and exhaustion items
  under security, and turn caps with memory isolation on all agents.
- Deterministic diff probes (`probe-diff.sh`): secrets (locations only),
  risky automation, debug leftovers, work markers, imports, dependency
  files, added and deleted files, oversized additions, handed to the
  reviewer as leads at zero model cost.
- Generated and lock files are excluded from the reviewable diff and
  listed in `excluded.txt`; probes still see them.
- The finding record reference ships as a preloadable skill, injected
  into the reviewer at spawn instead of costing a read every run.
- Standards-aware review plumbing: a local_standards setting names the
  untracked rule files in your clone, and extract-standards.sh gathers
  their text into the review context, deduplicated and containment-checked.
- The review judges by layered authority: the project's stated rules
  first, sharpening whichever category each rule's subject belongs to;
  the codebase's observable conventions where rules are silent; general
  practice where both are. Local rule files are enforced in substance,
  never named in anything posted.
- Findings carry a required Fix line: the recommended repair with its
  reasoning and repair context, so edits need no re-reading of the
  project (a proven suggestion fence stands in for it).
- An other category plus per-finding criteria notes, collected by
  criteria-signals.sh, so the criteria grow deliberately from what real
  reviews surface.
- Optional conventions block: a marked map in the reviewed repository's
  CLAUDE.md, extracted from the base branch into the review state, so
  agents stop re-deriving layout, test locations, and idioms every run.
- The agents consume all of it: the reviewer banks its reading in Fix
  lines, sweeps for other-category defects after the categories, and
  files criteria notes; the editor follows Fix pointers instead of
  re-deriving structure; the run report surfaces criteria signals.
- Every finding body carries a required Resolution line, the checkable
  criterion that editing satisfies and verification judges.
- Note appending (`append-note.sh`), so reopen reasons and wont-fix
  justifications live in the record the next round reads.
- Agent definitions rebuilt around first-round convergence: a coverage
  audit and calibration bar for the reviewer, plan-first editing with a
  pre-commit self-check, verbatim Resolution judging for the verifier,
  and literal delegation templates in the skill.
- Pre-push hook refusing direct pushes to main.
- Fork pull request support: the worktree fetches from the fork, pushes
  land on the fork branch when maintainer edits are allowed, and forks
  that refuse edits get a review-only pass with postable findings.
- Round regression skim: files a remediation round changed outside any
  finding's scope trigger an incremental review of just those files.

### Fixed

- Loop state that lived in model memory now lives on disk: the round
  budget persists per pull request in the ledger, a resume routes
  through the rerun-safe posting step, and local standards are found
  from linked worktrees by falling back to the main worktree.
- The skill frontmatter description is quoted, so strict YAML parsers
  accept it, and stray fence markers in agent prose are plain words now.
- Thread resolution pages past the first hundred review threads.

## 0.1.0 - 2026-08-30

### Added

- Quality gate (`scripts/gate.sh`), test harness, and pre-commit hook.
- Contributing guide, security policy, and issue and pull request templates.
- Plugin manifest with user configuration: auto-approve, check command, and
  per-role model overrides.
- Tool probe (`check-tools.sh`), state initialization (`init-state.sh`), and
  an offline GitHub CLI stub for the test suite.
- Context fetch (`fetch-pr.sh`) and the diff transform (`split-diff.sh`):
  annotated per-file diffs, a file index, and a commentable-line index.
- Findings ledger: record format, batch save with validation
  (`save-findings.sh`), field updates with transition rules
  (`update-finding.sh`), and convergence counting (`count-findings.sh`).
- Posting layer: inline comments with placement validation and a round
  summary (`post-review.sh`), thread replies (`reply-thread.sh`), and
  thread resolution (`resolve-thread.sh`).
- Branch plumbing: a detached review worktree (`checkout-pr.sh`), proven
  pushes (`push-branch.sh`), and state teardown (`cleanup-state.sh`).
- Proven merges (`merge-pr.sh`) and suggestion verification
  (`prove-suggestions.sh`): a fence posts only after it applies cleanly
  and the configured check passes with it in place.
- Reviewer agent: read-only, criteria in seven categories, emits finding
  records only.
- Editor and verifier agents: per-finding commits with thread replies, and
  verify-or-reopen passes that return counts only.
- The review-pr skill: the orchestration loop, context discipline, the
  merge gate with the auto-approve setting, and resume from the ledger.

[Unreleased]: https://github.com/Paxton-Meny/pr-review-workflow/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/Paxton-Meny/pr-review-workflow/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/Paxton-Meny/pr-review-workflow/releases/tag/v0.2.1
