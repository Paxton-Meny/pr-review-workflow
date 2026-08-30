# pr-review-workflow

A Claude Code plugin that runs the full loop of reviewing a pull request:
review the diff against categorized criteria, post findings, edit the code to
address them, then re-review until the change is ready to approve.

## Status

Early development. Nothing here works yet. The repository currently holds
scaffolding only, and this section will say otherwise when that changes.

## Requirements

- `git`
- The GitHub CLI, authenticated. The plugin shells out to it and never handles
  a token itself.

Nothing else. The plugin has no runtime dependencies, no build step, and
nothing to install beyond itself.

## What it does to your repository

Read this before installing. The plugin reads pull requests, posts review
comments to them, and pushes commits to their branches. It acts with whatever
access your GitHub CLI credentials carry.

## Install

Not yet published. Installation instructions land with the first release.

## Development

Run the gate before every commit:

```sh
sh scripts/gate.sh
```

Activate the pre-commit hook once per clone:

```sh
git config core.hooksPath .githooks
```

See CONTRIBUTING.md for branch naming, commit style, and the review loop every
change goes through.
