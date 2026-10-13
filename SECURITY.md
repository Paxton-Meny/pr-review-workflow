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

A repository's committed settings file may name a check command too, but
it runs only after you approve that exact command, once per change. The
setup skill lists every check command it infers on its own line and
writes it live only when you confirm that command by name; unattended,
it writes them as comments.

## Migrations and databases

The plugin never runs migration tooling, a dry run or check mode
included, and never connects to a database. Setup never offers such a
command as a check, and a finding's Check line that names one is judged
by reading instead of run. Your own check command is yours to keep
database-free: a test suite may create or migrate a test database.

A pull request that changes migration files never merges without a
person, auto-approve included, because one pull request cannot show
what the base branch or other open pull requests did to the same
schema.
