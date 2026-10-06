# pr-review-workflow

[![Release](https://img.shields.io/github/v/release/Paxton-Meny/pr-review-workflow?color=534AB7&label=release)](https://github.com/Paxton-Meny/pr-review-workflow/releases)
[![License](https://img.shields.io/badge/license-PolyForm--NC--1.0.0-0F6E56)](LICENSE)
[![Site](https://img.shields.io/badge/site-paxton--meny.github.io-D97757)](https://paxton-meny.github.io/pr-review-workflow/)

A Claude Code plugin that runs the full loop of reviewing a GitHub pull
request: review the diff against categorized criteria, post inline findings,
edit the branch to address them, re-verify with a cheaper model, and repeat
until nothing remains open. Then it merges, or asks you first.

**Contents:** [Status](#status) &#183;
[Requirements](#requirements) &#183;
[What it does](#what-it-does-to-your-repository) &#183;
[Usage](#usage) &#183;
[Settings](#settings) &#183;
[Development](#development) &#183;
[License](#license-and-attribution)

<p align="center"><img src="docs/assets/pipeline.svg" width="860" alt="The shape of a run in three lanes: scripts run down the center as the backbone, GitHub on the left, models on the right. One command stages the pull request with no model; the reviewer reads once, in up to four parallel shards, then a gap pass; findings are banked, filtered, proven, and posted as inline threads; a loop of at most four rounds runs the editor, the check gate, the verifier over executed contracts, and a skim; a merge gate asks first, and a run that does not converge parks with a status comment."></p>

<p align="center"><img src="docs/assets/loop.svg" width="860" alt="Animated: the review-revise cycle from above. One thorough first review feeds a ring of editor, gate and verifier, and a decision point; a reopened finding sends the token around again, a clean verdict exits to a proven merge, and a four-round budget bounds the cycle before it parks. The animation shows a run converging on its second lap."></p>

## Status

Released and public. The full loop is proven end to end in a live
interactive run: categorized review, a precision filter, per-finding
fix commits authored as the signed-in account, a round-diff skim that
caught and reviewed files no finding covered, cheap-model
verification, an attended merge gate, and a proven rebase merge, with
the run's statistics banked for evidence-based tuning. The eval suite
passes. Current work is accumulating runs across more repositories so
the thresholds can be tuned from the stats ledger.

## Requirements

- `git`
- The GitHub CLI, authenticated. The plugin shells out to it and never
  handles a token itself.
- A local clone of the repository whose pull request you are reviewing; the
  skill runs from inside it.

Nothing else. The plugin has no runtime dependencies, no build step, and
nothing to install beyond itself.

## What it does to your repository

Read this before installing. The plugin reads pull requests, posts review
comments to them, pushes commits to their branches, and merges when told to.
It acts with whatever access your GitHub CLI credentials carry, and fix
commits are authored as the signed-in account's noreply address, never
your clone's local git identity. With the
check command configured, it also runs that command against pull request
code (see SECURITY.md).

## Usage

From a clone of the reviewed repository:

```text
/pr-review-workflow:review-pr 128
```

The argument can be a bare number, `owner/repo#128`, or the pull
request URL. One rule about where you run it: start from inside a
clone of the repository the pull request belongs to. If the clone's
origin points anywhere else, the run refuses up front, before
creating state or touching the network. That is the whole tie
between plugin and repository, so review as many repositories as
you like, each from its own clone.

Loading with `--plugin-dir` never shows the settings dialog: run
`/plugin configure pr-review-workflow` in the session to fill it in,
or the run uses the defaults and says so.

The loop: a reviewer agent reads the fetched diff (split, line-annotated,
never entering the orchestrating context) and files findings in seven
categories (correctness, security, performance, best practices,
antipatterns, content leakage, outdated docs). Findings post as inline
comments; suggested-change blocks appear only after being applied and
checked in a scratch worktree. An editor agent fixes each finding with its
own commit and replies to each thread; a verifier agent re-checks only the
claimed fixes, resolving threads or reopening them. When nothing is open,
the merge gate runs.

### Settings

Configured when you enable the plugin. The
[settings reference](https://paxton-meny.github.io/pr-review-workflow/settings.html)
explains each one in plain terms, shows what every value changes on a
pull request, and says when to choose it.

| Option | Default | Meaning |
| --- | --- | --- |
| Auto-approve on convergence | off | Merge without asking once the loop is clean. When off, you get a prompt: merge now or hold. |
| Check command | empty | The reviewed repository's own check command, used to prove suggestions. Empty restricts suggestions to fixes that apply cleanly. |
| Local standards files | empty | Globs, relative to your clone, of untracked files holding the project's own rules. Their substance guides every category of the review; their names and text never reach the pull request. |
| Second review pass | risky | When a gap pass runs after a single-reviewer first review: off, risky (secrets or automation probes fired), or always. It reads the existing findings and reports only what they miss. A sharded review always ends with one, whatever this is set to: shards read disjoint file sets, so only a whole-diff pass sees defects that span them. |
| Ledgers kept per repository | 20 | Finished finding ledgers retained per repository after each merge; older ones are pruned, and runs still holding a worktree never are. |
| Reviewer / editor / verifier model | inherit / inherit / sonnet | Model per role. The first review deserves your strongest model; verification passes are cheap by design. |
| Model routing | auto | auto picks cheaper models where the work is mechanical: a small docs-only or config-only change with no risk probes gets a sonnet reviewer, a first editing round whose findings are all minor and fence-backed gets a sonnet editor, and a finding reopened past the limit gets one strong arbitration pass before the run parks, since repeated reopens sometimes mean the cheap verifier is wrong. With a strong model set, large code changes and probe-flagged sensitive code climb above the session model. The gap pass never routes down. fixed always uses the configured models. |
| Strong model | empty | Model that auto routing climbs to for large code changes, probe-flagged sensitive code (concurrency, crypto, auth, injection surfaces), and arbitration. Example: opus. Empty caps routing at the reviewer model. |
| Cost posture | balanced | How readily auto routing starts a fix on the cheap model: quality (proven suggestions only), balanced (also fixes whose Check line will execute), economy (any fix once a check command gates the round). High-stakes findings never start cheap; a failed fix climbs a rung. |
| Review samples | 1 | Independent reviewer passes per shard on the first review. Above 1, duplicates merge into the richest record with a support count the filter weighs; recall rises at roughly that multiple of the review cost. For repositories where an escaped defect is expensive. |
| Precision filter | on | Before findings post, a cheap second context re-reads the cited code and demotes findings the fresh evidence cannot support into the round summary. Nothing is dropped: demoted findings are still addressed, with the doubt recorded in the ledger. |
| Contract command prefixes | empty | Comma-separated prefixes, beyond the check command itself, that a finding's Check line may start with to be executed during verification. Test runners only, never bare interpreters. |

### Executable contracts

A finding may carry a `Check:` line, the check command narrowed to the
relevant test, and verification then runs it instead of judging prose:
execution is the one judge that cannot be argued with. Containment is
strict because reviewers read untrusted pull request content: a Check
line executes only when it starts with your configured check command or
one of the prefixes above, and never when it contains shell
metacharacters. With no check command configured, nothing ever
executes, exactly as before. Running a narrowed test executes no more
of the pull request's code than the check command you already
configured runs on every round.

### Cost notes

- Each agent runs at a fixed reasoning effort set in its definition,
  independent of your session's level: the reviewer and the arbiter
  high, the editor medium, the verifier and the filter low. Finding
  defects is where thinking pays; checking a fix against a stated
  contract is a narrow question.
- Subagent requests cache with a five-minute lifetime on every billing
  method (the main conversation gets an hour on a subscription). The
  `subagentPromptCacheTtl` setting raises it, at a higher write rate.
- Parallel reviewer shards read disjoint slices of the diff, so the
  cost math never depends on them sharing a prompt cache; documented
  prefix sharing between sibling agents exists only inside workflow
  runs, not for plain subagents.
- The `CLAUDE_CODE_SUBAGENT_MODEL` environment variable sits below the
  plugin's per-spawn model choices, but
  `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` overrides them entirely and will
  defeat model routing; leave it unset when using this plugin.

### Conventions block (optional)

<details>
<summary>Give the reviewed repository a conventions map that reviews
read instead of re-deriving the project every run.</summary>

Give the reviewed repository a marked block in its tracked CLAUDE.md
(see skills/review-pr/project-conventions.md) mapping its layout, test
locations, idioms, and intentional oddities. Reviews read the map from
the base branch instead of re-deriving those facts every run, and the
same file already guides Claude when developing on the repository.

</details>

### Checking the ledger

`/pr-review-workflow:status` lists the runs recorded for the current
repository (`all` for every repository), each with its finding
outcomes and whether it can resume, plus the accumulated statistics
across finished runs. Local state only; nothing is fetched or
written.

### State

Per-PR state lives under the plugin's data directory, outside every
repository: the finding ledger, fetched context, and a detached review
worktree. Re-invoking the skill on the same pull request resumes from the
ledger. Your own checkout is never touched.
State is keyed by repository and pull request, so every worktree of a
clone shares it, and local rule files are found from a linked worktree
by looking in the main one. Run one review per pull request at a time.

<p align="center"><img src="docs/assets/information-flow.svg" width="860" alt="Where information lives and moves: the orchestrating session sees one line per script, counts and ids only, never the diff; below that line, GitHub's diff and your clone feed a per-pull-request ledger on disk holding annotated diffs and probes, the finding records with their Fix and Resolution, the round budget, and a detached worktree; reviewer, filter, editor, and verifier each read their own slice; pushes, replies, resolutions, and the merge flow back to GitHub."></p>

### Limits

- Fork pull requests: full loop when the fork allows maintainer edits;
  review-only (findings and suggestions post, nothing is fixed) when it
  does not.
- Pull requests past the GitHub API diff limits are parked as too large.
- Unattended runs never merge unless auto-approve is on; they park with a
  status comment instead.

## Development

Run the gate before every commit:

```sh
sh scripts/gate.sh
```

Activate the pre-commit hook once per clone:

```sh
git config core.hooksPath .githooks
```

See CONTRIBUTING.md for branch naming, commit style, and the review loop
every change goes through.

## Project structure

- `.claude-plugin/plugin.json`: manifest and settings.
- `skills/review-pr/`: the orchestrating skill and the finding record format.
- `agents/`: reviewer, editor, and verifier definitions.
- `scripts/`: POSIX sh, one proven step each.
- `tests/`: offline suite with a stubbed GitHub CLI.

## License and attribution

Copyright 2026 Paxton-Meny. Licensed under the
[PolyForm Noncommercial License 1.0.0](LICENSE): free to use, change,
and share for any noncommercial purpose, with required credit per the
license.

### Commercial licensing

Use by or for a commercial organization needs a commercial license:
running the plugin on a company's pull requests, selling it, bundling
it into a product, or offering it within a paid service. Terms are
arranged directly and sized to the use. Open an issue titled
"Commercial license inquiry" with a sentence on the intended use, or
reach the maintainer through their GitHub profile for anything better
raised privately.

This is an independent project, not affiliated with or endorsed by
Anthropic. Claude and Claude Code are trademarks of Anthropic, PBC,
named here only to say what the plugin runs on. The [NOTICE](NOTICE) file travels with
every distribution. The name pr-review-workflow identifies this
project: forks and derived works ship under their own name and must
prominently state what they changed, which the license requires. If
this plugin reviews your pull requests, a link back here is
appreciated.
