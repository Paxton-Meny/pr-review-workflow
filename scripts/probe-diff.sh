#!/bin/sh
# Run deterministic probes over the fetched diff into probes.txt.
# Usage: sh scripts/probe-diff.sh <state-dir>
#        sh scripts/probe-diff.sh --pattern sensitive|secrets|automation
# --pattern prints the named probe's regex, so other scripts grep with
# the same one instead of carrying a copy.
set -eu

AUTOMATION_RE='uses:|pull_request_target|continue-on-error|--no-verify|curl[^|]*\|[[:space:]]*(ba|z)?sh|wget[^|]*\|[[:space:]]*(ba|z)?sh|chmod[[:space:]]+(-r[[:space:]]+)?777'
SECRETS_RE='akia[0-9a-z]{16}|-----begin [a-z ]*private key|gh[pousr]_[0-9a-z]{30,}|sk-[0-9a-z_-]{20,}|xox[abprs]-|(password|passwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token)[[:space:]]*[:=][[:space:]]*.{8,}'
SENSITIVE_RE='mutex|semaphore|atomic_|threading\.|goroutine|synchronized|pthread_|crypt|cipher|hmac|jwt|oauth|argon2|eval\(|exec\(|pickle\.loads|yaml\.load|deserializ|os\.system|subprocess\.'
SCHEMA_RE='drop[[:space:]]+(table|column|index|constraint)|rename[[:space:]]+(column|to)|alter[[:space:]]+(table|column)|not[[:space:]]+null|truncate|create[[:space:]]+(unique[[:space:]]+)?index|removefield|renamefield|alterfield|deletemodel|renamemodel|runsql|runpython|op\.(drop_|alter_column|rename_table|execute)|(remove|rename|change)_column|drop_table|change_column_null|sp_rename|(drop|rename|alter)column|(drop|rename)table|dropindex|(delete|rename)\.(column|table)|alter\.column'

if [ "${1:-}" = --pattern ]; then
	case "${2:-}" in
	sensitive) printf '%s\n' "$SENSITIVE_RE" ;;
	secrets) printf '%s\n' "$SECRETS_RE" ;;
	automation) printf '%s\n' "$AUTOMATION_RE" ;;
	*)
		echo "probe-diff: --pattern takes sensitive, secrets, or automation" >&2
		exit 1
		;;
	esac
	exit 0
fi

dir=${1:?usage: probe-diff.sh <state-dir>}
ctx="$dir/pr-context"
[ -f "$ctx/diff.patch" ] || {
	echo "probe-diff: no diff.patch in $ctx, run fetch-pr.sh first" >&2
	exit 1
}

added=$(mktemp "$ctx/.probe.XXXXXX")
out=$(mktemp "$ctx/.probe.XXXXXX")
files=$(mktemp "$ctx/.probe.XXXXXX")
trap 'rm -f "$added" "$out" "$files"' EXIT
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
	# The files each probe touched, slug and path, for per-shard routing.
	printf '%s\n' "$hits" | sed 's/[: (].*//' | sort -u | awk -v s="$3" 'NF { print s "\t" $0 }' >>"$files"
	slugs="$slugs $3"
	sections=$((sections + 1))
}
lead() { grep -iE "$1" "$added" | head -n 40 || true; }
lead_paths() { grep -iE "$1" "$added" | sed 's/^\([^:]*:[0-9]*\):.*/\1/' | head -n 40 || true; }

added_paths=$(awk '/^--- \/dev\/null$/ { want = 1; next } want && /^\+\+\+ / { p = $0; sub(/^\+\+\+ b\//, "", p); print p } { want = 0 }' "$ctx/diff.patch")
deleted_paths=$(awk '/^--- a\// { p = $0; sub(/^--- a\//, "", p); prev = p; next } /^\+\+\+ \/dev\/null$/ { print prev } { prev = "" }' "$ctx/diff.patch")
probe "Added files" "$(printf '%s\n' "$added_paths" | head -n 50)" added
probe "Deleted files" "$(printf '%s\n' "$deleted_paths" | head -n 50)" deleted
probe "Dependency manifests or lockfiles changed" "$(cut -f1 "$ctx/files.txt" 2>/dev/null | grep -iE '(^|/)(package(-lock)?\.json|yarn\.lock|pnpm-lock\.yaml|cargo\.(toml|lock)|pyproject\.toml|poetry\.lock|uv\.lock|requirements[^/]*\.txt|go\.(mod|sum)|gemfile(\.lock)?|composer\.(json|lock)|.*\.lockb?)$' || true)" deps
probe "Added import lines" "$(lead_paths ':[[:space:]]*(import |from [a-z0-9_.]+ import |require\(|use [a-z]|#include|using [a-z])' | sort -u | head -n 40)" imports
probe "Risky automation lines added" "$(lead "$AUTOMATION_RE")" automation
probe "Possible secrets in added lines (locations only, content withheld)" "$(lead_paths "$SECRETS_RE")" secrets
probe "Debug leftovers in added lines" "$(lead 'console\.(log|debug)\(|debugger;|pdb\.set_trace|breakpoint\(\)|binding\.pry|dbg!\(|var_dump\(|print_r\(')" debug
probe "Work markers added" "$(lead '(^|[^a-z])(todo|fixme|hack|xxx)([^a-z]|$)')" markers
probe "Sensitive surfaces in added lines (concurrency, crypto, auth, injection)" "$(lead "$SENSITIVE_RE")" sensitive
probe "Test files shrink (more deleted than added, assertions may be weakening)" "$(awk -F '\t' '{
	b = $1; sub(/.*\//, "", b)
	t = ($1 ~ /(^|\/)(test|tests|__tests__|spec)\//) || (b ~ /^test_/) || (b ~ /_test\./) || (b ~ /\.test\./) || (b ~ /\.spec\./) || (b ~ /_spec\./) || (b == "conftest.py")
	if (t && $3 + 0 > $2 + 0 && $3 + 0 >= 5) print $1 " (" $2 " added, " $3 " deleted)"
}' "$ctx/files.txt" 2>/dev/null || true)" test-shrink
# Paths the project or the user declared sensitive, and migrations, from
# the resolved settings. Migrations count as sensitive for routing.
if [ -f "$dir/settings.txt" ]; then
	declared=$(cut -f1 "$ctx/files.txt" 2>/dev/null | sh "$(dirname "$0")/match-paths.sh" "$dir" sensitive_paths)
	migrations=$(cut -f1 "$ctx/files.txt" 2>/dev/null | sh "$(dirname "$0")/match-paths.sh" "$dir" migration_paths)
	probe "Declared sensitive paths changed" "$declared" sensitive
	probe "Migration files changed (a modified or deleted one may already have run on teammates' databases; a snapshot is regenerated with every migration)" "$(printf '%s\n' "$migrations" | while IFS= read -r p; do
		[ -n "$p" ] || continue
		case "${p##*/}" in
		*ModelSnapshot.cs | *.Designer.cs) state=snapshot ;;
		*) state='' ;;
		esac
		if [ -n "$state" ]; then
			:
		elif printf '%s\n' "$added_paths" | grep -qxF -- "$p"; then
			state=added
		elif printf '%s\n' "$deleted_paths" | grep -qxF -- "$p"; then
			state=deleted
		else
			state=modified
		fi
		printf '%s (%s)\n' "$p" "$state"
	done | head -n 50)" sensitive
	probe "Schema operations in added migration lines" "$(printf '%s\n' "$migrations" | awk 'NR == FNR { if ($0 != "") want[$0] = 1; next }
	{ p = $0; sub(/:[0-9]+:.*/, "", p) }
	p in want { rest = substr($0, length(p) + 2); n = rest; sub(/:.*/, "", n); print p ":" n "\t" substr(rest, length(n) + 2) }' - "$added" | grep -iE "	.*($SCHEMA_RE)" | cut -f1 | head -n 40 || true)" schema
fi
probe "Large additions (over 800 added lines in one file)" "$(awk -F '\t' '$2 + 0 > 800 { print $1 " (" $2 " added)" }' "$ctx/files.txt" 2>/dev/null || true)" large

if [ "$sections" -gt 0 ]; then
	mv "$out" "$ctx/probes.txt"
fi
mv "$files" "$ctx/probe-files.txt"
trap 'rm -f "$added" "$out"' EXIT
slugs=${slugs# }
# The fired slugs, one line, for the router.
printf '%s\n' "$slugs" >"$ctx/probe-slugs.txt"
echo "probe-diff: $sections sections${slugs:+ ($slugs)}"
