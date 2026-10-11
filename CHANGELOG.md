# Changelog

All notable changes to this project are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

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

### Added

- The first comment each review posts ends with one line naming and
  linking the plugin, so readers can see which tool reviewed the pull
  request. Later comments never repeat it.
- The reviewer checks documentation the diff never touches: it greps
  the repository's docs for each option, command, or behavior the
  change alters, and flags a new user-facing option missing from docs
  that already describe its siblings. A repository without user docs
  is not owed new pages.
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
- An escalation ladder for fixes. Every editing attempt is noted on
  the finding's record with its round, rung, model, and reason; a
  finding attempted and still open climbs one rung above its last
  attempt, and a repair after a failed check gate climbs one rung
  above the batch that broke it. A new `cost_posture` setting
  (quality, balanced, economy; default balanced) decides how readily
  a fix starts on the cheap model: proven suggestions only, also
  fixes whose Check line will execute, or any fix once a check
  command gates the round. A blocker, a security finding, or a file
  the secrets or sensitive probe flagged never starts cheap. The
  contract runner gains a policy-only mode the router uses to tell
  an executable Check line from one judged by reading, and the
  statistics count escalations.
- Routing decides per unit of work. A sharded review is routed group
  by group on each group's own files, so a documentation group runs
  on the cheap rung while an authentication group climbs, and the gap
  pass takes the highest rung any group used. A first editing round
  splits into a mechanical batch and the rest when each holds at
  least two findings, run one after the other with the check gate
  after each, so a broken check is pinned on the batch that broke it.
- Model routing is a script, `route-models.sh`, that prints one
  `route` line per decision with its rung, model, and reason, and
  keeps them in the ledger. The skill passes the model it names
  instead of choosing one. Large means over 800 changed lines of
  code, with tests, docs, and configuration no longer counted. When a
  change calls for a stronger model and none is set, the route says
  so and the final report repeats it. Each run's statistics line
  gains the count of decisions per rung, and the status report sums
  them.
- Each agent declares its reasoning effort: the reviewer high, the
  editor medium, the verifier and the filter low, so the narrow
  checks no longer inherit whatever level the session runs at. An
  arbiter agent carries the verifier's procedure at high effort for
  the one arbitration pass before a run parks.
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

### Changed

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

- The repository is now the marketplace the README always claimed:
  a marketplace manifest lists the plugin at the repository root,
  so the documented install commands work. They could not have
  before, because the manifest did not exist.

### Added

- A commercial licensing section on the site and in the README:
  what needs a commercial license and how to start the
  conversation, so the dual-licensing model has an operable path.

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

[Unreleased]: https://github.com/Paxton-Meny/pr-review-workflow/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/Paxton-Meny/pr-review-workflow/releases/tag/v0.2.1
