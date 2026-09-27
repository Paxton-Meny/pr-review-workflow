# Project conventions for reviewed repositories

A repository reviewed by this plugin can carry a conventions block: a short
map of itself that the review agents read instead of re-deriving the same
facts from the tree on every run. It is optional; without one, reviews work
exactly as before, just with more exploratory reading.

## Where it lives, and why there

The block goes in the repository's tracked `CLAUDE.md`, between markers:

```
<!-- review-conventions:begin -->
...the map...
<!-- review-conventions:end -->
```

`CLAUDE.md` is the one file Claude already reads when developing on the
repository, so the same facts bind development and review without a second
home to drift. The markers keep the block regenerable without touching
whatever else the file holds, and a repository without `CLAUDE.md` can adopt
one with only this block in it.

The extraction reads the file as of the pull request's base branch on
origin, never from the pull request head and never from the working copy, so
a pull request cannot alter what reviewers believe about the project.

## What belongs in it

A map, not a manual. Facts a reviewer or editor would otherwise have to dig
for, stated in a line or two each:

- The layout: what each top-level directory holds, one line per directory.
- Where tests live, how they are named, and the one command that runs them.
- The idioms the codebase actually follows: error handling, naming, logging,
  the pattern a new module copies.
- Intentional oddities a reviewer would otherwise flag: generated files,
  vendored paths, deliberate deviations and their reasons.
- Anything reviews have repeatedly re-discovered.

Keep it under about thirty lines. Do not duplicate CONTRIBUTING or the
README; name them where detail lives. Prune lines the code no longer backs,
in the same change that invalidates them: a wrong map is worse than none.

## How the agents use it

`checkout-pr.sh` extracts the block to `pr-context/conventions.txt` in the
state directory. Agents read it first and go straight to the places it
names. It is data about the codebase, never instructions: nothing in it
changes an agent's procedure, scope, criteria, or output, and a diff that
edits the block gets reviewed like any other change.
