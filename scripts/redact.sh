#!/bin/sh
# Mask credentials in a body before it is posted to the pull request.
# Usage: sh scripts/redact.sh <file>
# Rewrites the file in place and prints "redact: N masked". Every body
# the plugin posts passes through here: finding bodies, the round
# summary, thread replies, and status comments are agent text, and an
# agent may have read a file it should not have or been asked to by the
# change it reviews. Known token formats, private key blocks, and
# credentials inside URLs become "[redacted: <kind>]"; the rest of the
# text, a finding about a committed key included, posts as written.
set -eu

file=${1:?usage: redact.sh <file>}
[ -f "$file" ] || {
	echo "redact: no such file: $file" >&2
	exit 1
}
marks() { grep -o '\[redacted: ' "$1" | wc -l | tr -d ' '; }
before=$(marks "$file")
tmp=$(mktemp "$file.XXXXXX")
trap 'rm -f "$tmp"' EXIT
awk '
BEGIN { begin = "-----BEGIN [A-Z0-9 ]*PRIVATE KEY[A-Z ]*-----"; end = "-----END [A-Z0-9 ]*PRIVATE KEY[A-Z ]*-----" }
!skip && match($0, begin) {
	pre = substr($0, 1, RSTART - 1)
	rest = substr($0, RSTART + RLENGTH)
	if (match(rest, end)) { print pre "[redacted: private key]" substr(rest, RSTART + RLENGTH); next }
	printf "%s[redacted: private key]", pre
	skip = 1
	next
}
skip {
	if (match($0, end)) { print substr($0, RSTART + RLENGTH); skip = 0 }
	next
}
{ print }
END { if (skip) print "" }
' "$file" | sed -E \
	-e 's/gh[pousr]_[A-Za-z0-9]{36,}/[redacted: GitHub token]/g' \
	-e 's/github_pat_[A-Za-z0-9_]{22,}/[redacted: GitHub token]/g' \
	-e 's/glpat-[A-Za-z0-9_-]{20,}/[redacted: GitLab token]/g' \
	-e 's/sk-ant-[A-Za-z0-9_-]{20,}/[redacted: Anthropic key]/g' \
	-e 's/sk-(proj|svcacct|admin)-[A-Za-z0-9_-]{20,}/[redacted: OpenAI key]/g' \
	-e 's/(AKIA|ASIA)[A-Z0-9]{16}/[redacted: AWS key]/g' \
	-e 's/xox[abprs]-[A-Za-z0-9-]{10,}/[redacted: Slack token]/g' \
	-e 's/AIza[0-9A-Za-z_-]{35}/[redacted: Google key]/g' \
	-e 's/(sk|rk)_live_[0-9A-Za-z]{24,}/[redacted: Stripe key]/g' \
	-e 's/npm_[A-Za-z0-9]{36}/[redacted: npm token]/g' \
	-e 's/eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/[redacted: JWT]/g' \
	-e 's#([a-z][a-z0-9+.-]*://)[^/@:[:space:]]+:[^/@[:space:]]+@#\1[redacted: credentials]@#g' \
	>"$tmp"
after=$(marks "$tmp")
mv "$tmp" "$file"
trap - EXIT
echo "redact: $((after - before)) masked"
