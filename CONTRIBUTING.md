# Contributing

This project does not accept external code contributions at present:
its commercial licensing model requires a contributor agreement that
does not exist yet, and accepting code without one would cloud the
rights the model depends on. Bug reports and feature requests through
the issue templates are welcome. The conventions below bind all work
in the repository, and they will govern external contributions if a
contributor agreement opens them. Conduct in every project
space is governed by [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

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

    claude plugin eval . --model sonnet --ablation none

Sandbox facts that shape cases, learned from the first live run:
Bash is withheld unless granted with `--allow-tools Bash`, and that
grant demands an OS confinement backend (`apt install bubblewrap
socat` on Debian), so portable cases must grade behavior with the
scripts refused: the attempted Bash call still lands in the trace,
and honesty is the thing to assert (names where it stopped, invents
nothing). `${user_config.*}` is not substituted in the sandbox, so
never grade on configured values. The smoke case asserts exactly
this: the skill reaches for check-tools first, names the stop, and
fabricates no finding ids. With bubblewrap installed, deeper cases
that actually execute the scripts become possible.

Keep cases deterministic, one behavior per case, graders per file
under the case's `graders/`.
