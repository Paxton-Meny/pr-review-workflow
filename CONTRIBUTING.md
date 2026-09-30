# Contributing

This project is in early development and not yet accepting external
contributions. The conventions below bind all work in the repository, and they
will govern external contributions when they open.

## Setup

Activate the hooks once per clone:

```sh
git config core.hooksPath .githooks
```

## The gate

One command runs every check:

```sh
sh scripts/gate.sh
```

The pre-commit hook runs it and blocks the commit on failure. A pull request
merges only after the gate passes on its branch.

## Branches and commits

- Never commit directly to `main`. One branch per change: `feat/`, `fix/`,
  `docs/`, `perf/`, `refactor/`, or `research/` plus a kebab-case slug.
- Commit subjects: imperative mood, capitalized, 72 characters or fewer, no
  trailing period, no type prefixes. A body explains why when the subject
  alone cannot.
- One logical change per commit. Read the full staged diff before committing.

## Pull requests

- Every change lands through a pull request, reviewed before merging even by
  its author. Findings are posted as inline comments, addressed as further
  commits on the same branch, and re-checked until none remain open.
- Merge by rebase to keep history linear. The repository accepts no other
  merge method.
- Update CHANGELOG.md in the same branch as the change it records.

## Code

- POSIX `sh`, not bash. Scripts validate their inputs first, quote every
  expansion, write atomically, prove their own results, and exit non-zero
  with a specific message on failure.
- No comments beyond a shebang and a usage line. Names and structure carry
  the explanation.
- No dependencies. The only external tools invoked are `git` and the GitHub
  CLI, and nothing is ever installed.
- Every behavior change lands with a test case under `tests/cases/`.

## Evals (experimental)

`evals/` holds `claude plugin eval` cases: each spawns the plugin in a
sandboxed one-shot session and grades the transcript. They spend real
model tokens and need a logged-in `claude`, so the offline gate never
runs them; run them by hand before a release:

    claude plugin eval . --model sonnet

The suite is experimental until a release has run it green. Keep cases
deterministic (the smoke case asserts the skill stops at a failing
script and relays its error verbatim), one behavior per case, graders
per file under the case's `graders/`.
