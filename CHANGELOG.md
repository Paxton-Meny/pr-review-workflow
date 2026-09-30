# Changelog

All notable changes to this project are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

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
## [0.1.0] - 2026-08-30

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

[Unreleased]: https://github.com/Paxton-Meny/pr-review-workflow/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Paxton-Meny/pr-review-workflow/releases/tag/v0.1.0
