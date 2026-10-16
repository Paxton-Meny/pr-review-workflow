#!/bin/sh
# redact: masks known credential formats, key blocks, and URL
# credentials, leaves ordinary text alone; every posting script uses it.
set -eu

stub="$SCRATCH/stub"
mkdir -p "$stub"
export GH_STUB_DIR="$stub"
export PATH="$REPO_ROOT/tests/stubs:$PATH"
. "$REPO_ROOT/tests/fixture-identity.sh"

# Built at run time so the repository never holds a credential-shaped string.
rep() { printf "%${2}s" '' | tr ' ' "$1"; }
gh_token="ghp_$(rep a 36)"
pat="github_pat_$(rep B 30)"
ant="sk-ant-api03-$(rep c 40)"
aws="AKIA$(rep D 16)"
slack="xoxb-$(rep 1 12)-$(rep e 10)"
jwt="eyJ$(rep f 12).eyJ$(rep g 12).$(rep h 12)"
pem_begin="-----BEGIN OPENSSH PRIVATE"" KEY-----"
pem_end="-----END OPENSSH PRIVATE"" KEY-----"

body="$SCRATCH/body"
cat >"$body" <<EOF2
The test fixture embeds $gh_token in config.
Also $pat, $ant and $aws.
Webhook $slack, session $jwt.
Clone https://deploy:$(rep x 20)@git.example.com/app.git
Keep: commit abc1234, sk-short, ghp_short, AKIAshort, user@example.com
Key file:
$pem_begin
$(rep Q 64)
$(rep R 64)
$pem_end
done
EOF2
[ "$(sh "$REPO_ROOT/scripts/redact.sh" "$body")" = "redact: 8 masked" ]
cat >"$SCRATCH/want" <<'EOF2'
The test fixture embeds [redacted: GitHub token] in config.
Also [redacted: GitHub token], [redacted: Anthropic key] and [redacted: AWS key].
Webhook [redacted: Slack token], session [redacted: JWT].
Clone https://[redacted: credentials]@git.example.com/app.git
Keep: commit abc1234, sk-short, ghp_short, AKIAshort, user@example.com
Key file:
[redacted: private key]
done
EOF2
cmp -s "$body" "$SCRATCH/want" || { diff "$SCRATCH/want" "$body" >&2; exit 1; }
# Masking twice changes nothing and counts nothing.
[ "$(sh "$REPO_ROOT/scripts/redact.sh" "$body")" = "redact: 0 masked" ]
cmp -s "$body" "$SCRATCH/want"
# A key block that never ends is masked to the end.
printf 'before %s\n%s\n' "$pem_begin" "$(rep Z 40)" >"$body"
sh "$REPO_ROOT/scripts/redact.sh" "$body" >/dev/null
[ "$(cat "$body")" = "before [redacted: private key]" ]

dir="$SCRATCH/state"
mkdir -p "$dir/pr-context"
printf 'owner %s\nrepo widgets\npr 7\nhead_sha abc123\n' "$fixture_owner" >"$dir/meta.txt"
printf '0\n' >"$dir/round.txt"

# A status comment goes to the run's pull request only, masked, with
# the attribution on the run's first comment.
: >"$stub/pr-comment"
out=$(printf 'Parked: the token %s leaked in CI.\n' "$gh_token" | sh "$REPO_ROOT/scripts/post-comment.sh" "$dir")
[ "$out" = "post-comment: posted, 1 masked" ]
grep -q "^pr comment 7 --repo $fixture_owner/widgets --body-file " "$stub/calls.log"
grep -qx 'Parked: the token \[redacted: GitHub token\] leaked in CI.' "$stub/bodies.log"
grep -q 'Reviewed with \[pr-review-workflow\]' "$stub/bodies.log"
if grep -q "$gh_token" "$stub/bodies.log"; then
	echo "a status comment posted a token" >&2
	exit 1
fi
if printf '  \n' | sh "$REPO_ROOT/scripts/post-comment.sh" "$dir" 2>"$SCRATCH/err"; then
	echo "expected refusal of an empty comment" >&2
	exit 1
fi
grep -q "empty body" "$SCRATCH/err"

# Thread replies are masked too.
: >"$stub/bodies.log"
printf '5555\n' >"$stub/api-repos_${fixture_owner}_widgets_pulls_7_comments_9001_replies"
out=$(printf 'Still leaks %s here.\n' "$ant" | sh "$REPO_ROOT/scripts/reply-thread.sh" "$dir" 9001)
[ "$out" = "reply-thread: replied to 9001 as 5555, 1 masked" ]
grep -qx 'Still leaks \[redacted: Anthropic key\] here.' "$stub/bodies.log"

# So are finding bodies, inline and in the round summary.
: >"$stub/bodies.log"
printf 'src/app.py\tRIGHT\t2\n' >"$dir/pr-context/commentable.txt"
sh "$REPO_ROOT/scripts/save-findings.sh" "$dir" >/dev/null <<EOF2
=== finding
category: security
severity: blocker
path: src/app.py
line: 2
side: RIGHT
title: Hardcoded token
---
The file commits $gh_token as a literal.
Fix: read it from the environment.
Resolution: no token literal remains in src/app.py.
=== finding
category: security
severity: major
path: src/other.py
line: 5
side: RIGHT
title: Hardcoded key
---
The module embeds $aws.
Fix: read it from the environment.
Resolution: no key literal remains in src/other.py.
EOF2
printf '9001\n' >"$stub/api-repos_${fixture_owner}_widgets_pulls_7_comments.1"
out=$(sh "$REPO_ROOT/scripts/post-review.sh" "$dir")
[ "$out" = "post-review: 1 posted inline, 1 in the summary, round 1, 2 masked" ]
grep -qx 'The file commits \[redacted: GitHub token\] as a literal.' "$stub/bodies.log"
grep -qx 'The module embeds \[redacted: AWS key\].' "$stub/bodies.log"
if grep -qe "$gh_token" -e "$aws" "$stub/bodies.log"; then
	echo "a finding body posted a credential" >&2
	exit 1
fi

# A failing redact.sh stops the posting scripts before anything reaches gh.
bad="$SCRATCH/badscripts"
mkdir -p "$bad"
cp "$REPO_ROOT"/scripts/*.sh "$bad/"
printf 'exit 1\n' >"$bad/redact.sh"
sh "$REPO_ROOT/scripts/save-findings.sh" "$dir" >/dev/null <<EOF2
=== finding
category: security
severity: minor
path: src/third.py
line: 9
side: RIGHT
title: Another literal
---
The module embeds a literal.
Fix: read it from the environment.
Resolution: no literal remains in src/third.py.
EOF2
calls_before=$(wc -l <"$stub/calls.log")
if printf 'Reply text.\n' | sh "$bad/reply-thread.sh" "$dir" 9001 2>/dev/null; then
	echo "reply-thread.sh posted although redact.sh failed" >&2
	exit 1
fi
if sh "$bad/post-review.sh" "$dir" >/dev/null 2>&1; then
	echo "post-review.sh posted although redact.sh failed" >&2
	exit 1
fi
[ "$(wc -l <"$stub/calls.log")" -eq "$calls_before" ]
