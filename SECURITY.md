# Security policy

## Supported versions

The latest release and the tip of `main` are supported. There are no
maintained older release lines: a security fix ships as a new release,
never as a patch to a previous one.

## What this tool does with your credentials

The plugin never reads, stores, or transmits a GitHub token. It shells out to
the GitHub CLI and lets it hold its own credentials. It acts with whatever
access your `gh` login carries: it reads pull requests, posts comments, pushes
commits to pull request branches, and merges when told to.

## Reporting a vulnerability

Report vulnerabilities privately through GitHub security advisories:
[Report a vulnerability](https://github.com/Paxton-Meny/pr-review-workflow/security/advisories/new).
Do not open a public issue for a security problem.

Expect an acknowledgment within a week. Please include the steps to reproduce
and the impact you believe the problem has.

## The check command

When you configure a check command, the plugin runs it against a scratch copy
of the pull request head to verify suggested changes, and again in the
review worktree after fixes are committed. Both execute the pull
request's code with your local privileges, exactly as running its tests
yourself would. Leave the option empty for repositories whose contributors
you do not trust that far.
