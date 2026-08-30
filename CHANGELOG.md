# Changelog

All notable changes to this project are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/Paxton-Meny/pr-review-workflow/commits/main
