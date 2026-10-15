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

## What the plugin posts

Everything posted to a pull request, finding bodies, the round
summary, thread replies, and status comments, is written by an agent
that read the change and may have been steered by it. Every body passes
through `scripts/redact.sh` first, which masks known token formats
(GitHub, GitLab, Anthropic, OpenAI, AWS, Slack, Google, Stripe, npm),
JSON web tokens, private key blocks, and credentials inside URLs.
Status comments go through `scripts/post-comment.sh`, which posts only
to the run's own pull request. The masking knows formats, not secrets:
a credential in a format it does not list posts as written.

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

## Check output

When the pull request's checks fail after the review converges, the plugin
reads what GitHub reports about them: the check runs' summaries and
annotations, and the failed steps' log of an Actions run. All of it is
written by whatever the pull request runs, so it is handled as data: it
goes into a capped digest in the state directory that only the editor
reads, it is never printed into the orchestrating session, and the comment
the plugin posts carries the failed checks' names and links and the
editor's own paragraph, never log text. The editor repairs code only; it
never edits a workflow or a check's definition, disables a check, or
weakens a test to get a green result.

## Pushes to your branch

Fixes, repairs, and updates are pushed to the pull request branch as the
account `gh` is signed in as. An update that rewrites the branch, a rebase
onto the base under rebase merging, is pushed with a lease on the head the
run last saw, so a push anyone else made in the meantime refuses it rather
than being overwritten. A project's shared file can never turn the base
sync on; only your own configuration or local file can.
