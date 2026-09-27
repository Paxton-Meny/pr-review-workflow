#!/bin/sh
# Run deterministic probes over the fetched diff into probes.txt.
# Usage: sh scripts/probe-diff.sh <state-dir>
set -eu

dir=${1:?usage: probe-diff.sh <state-dir>}
ctx="$dir/pr-context"
[ -f "$ctx/diff.patch" ] || {
	echo "probe-diff: no diff.patch in $ctx, run fetch-pr.sh first" >&2
	exit 1
}

added=$(mktemp "$ctx/.probe.XXXXXX")
out=$(mktemp "$ctx/.probe.XXXXXX")
trap 'rm -f "$added" "$out"' EXIT
rm -f "$ctx/probes.txt"

awk '
/^\+\+\+ / { p = $0; sub(/^\+\+\+ /, "", p); sub(/^b\//, "", p); path = p; next }
/^@@ / { n = $3; sub(/^\+/, "", n); sub(/,.*/, "", n); line = n + 0; inhunk = 1; next }
!inhunk { next }
/^\+/ { printf "%s:%d:%s\n", path, line, substr($0, 2); line++; next }
/^-/ { next }
/^\\/ { next }
{ line++ }
' "$ctx/diff.patch" >"$added"

sections=0
slugs=
probe() {
	hits=$2
	[ -n "$hits" ] || return 0
	printf '## %s\n%s\n\n' "$1" "$hits" >>"$out"
	slugs="$slugs $3"
	sections=$((sections + 1))
}
lead() { grep -iE "$1" "$added" | head -n 40 || true; }
lead_paths() { grep -iE "$1" "$added" | sed 's/^\([^:]*:[0-9]*\):.*/\1/' | head -n 40 || true; }

probe "Added files" "$(awk '/^--- \/dev\/null$/ { want = 1; next } want && /^\+\+\+ / { p = $0; sub(/^\+\+\+ b\//, "", p); print p } { want = 0 }' "$ctx/diff.patch" | head -n 50)" added
probe "Deleted files" "$(awk '/^--- a\// { p = $0; sub(/^--- a\//, "", p); prev = p; next } /^\+\+\+ \/dev\/null$/ { print prev } { prev = "" }' "$ctx/diff.patch" | head -n 50)" deleted
probe "Dependency manifests or lockfiles changed" "$(cut -f1 "$ctx/files.txt" 2>/dev/null | grep -iE '(^|/)(package(-lock)?\.json|yarn\.lock|pnpm-lock\.yaml|cargo\.(toml|lock)|pyproject\.toml|poetry\.lock|uv\.lock|requirements[^/]*\.txt|go\.(mod|sum)|gemfile(\.lock)?|composer\.(json|lock)|.*\.lockb?)$' || true)" deps
probe "Added import lines" "$(lead_paths ':[[:space:]]*(import |from [a-z0-9_.]+ import |require\(|use [a-z]|#include|using [a-z])' | sort -u | head -n 40)" imports
probe "Risky automation lines added" "$(lead 'uses:|pull_request_target|continue-on-error|--no-verify|curl[^|]*\|[[:space:]]*(ba|z)?sh|wget[^|]*\|[[:space:]]*(ba|z)?sh|chmod[[:space:]]+(-r[[:space:]]+)?777')" automation
probe "Possible secrets in added lines (locations only, content withheld)" "$(lead_paths 'akia[0-9a-z]{16}|-----begin [a-z ]*private key|gh[pousr]_[0-9a-z]{30,}|sk-[0-9a-z_-]{20,}|xox[abprs]-|(password|passwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token)[[:space:]]*[:=][[:space:]]*.{8,}')" secrets
probe "Debug leftovers in added lines" "$(lead 'console\.(log|debug)\(|debugger;|pdb\.set_trace|breakpoint\(\)|binding\.pry|dbg!\(|var_dump\(|print_r\(')" debug
probe "Work markers added" "$(lead '(^|[^a-z])(todo|fixme|hack|xxx)([^a-z]|$)')" markers
probe "Large additions (over 800 added lines in one file)" "$(awk -F '\t' '$2 + 0 > 800 { print $1 " (" $2 " added)" }' "$ctx/files.txt" 2>/dev/null || true)" large

if [ "$sections" -gt 0 ]; then
	mv "$out" "$ctx/probes.txt"
	trap 'rm -f "$added"' EXIT
fi
slugs=${slugs# }
echo "probe-diff: $sections sections${slugs:+ ($slugs)}"
