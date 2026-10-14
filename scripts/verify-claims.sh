#!/bin/sh
# Keep only the claims in the cartographers' records that the repository
# itself confirms, and write them as the digest the rest of setup reads.
# Usage: sh scripts/verify-claims.sh <survey-dir>
#
# No records at all, as when every reader stopped before saving, is no
# error: the counts say so. A path claim stands when its ref is a tracked file, or a tracked
# directory written as dir/ or dir/**. A migrations claim stands only as
# such a directory, outside the test directories, that holds a tracked
# .sql file or a file the survey's migration pattern matches. A check
# claim stands when its command equals a check candidate the survey
# printed (the "survey: check" lines in the survey directory's
# survey.txt), or is "sh <tracked script>", or starts with a toolchain
# whose manifest the clone holds; a command holding a shell
# metacharacter, or naming migration or database tooling, never stands.
# Writes digest.txt, one "<id> <kind> <ref> | <statement>" per kept
# claim with the first statement kept where two records cite the same
# kind and ref. Prints "verify: partitions N recorded N missing <ids or
# none>" against the plan, one "verify: dropped <id> <kind> <ref>" line
# per drop, and ends with "verify: records N claims N kept N duplicate N
# dropped N", whose last three add up to the claims.
set -eu

dir=${1:?usage: verify-claims.sh <survey-dir>}
[ -f "$dir/meta.txt" ] || {
	echo "verify-claims: no meta.txt in $dir, run inventory-repo.sh first" >&2
	exit 1
}
root=$(sed -n 's/^repo_root //p' "$dir/meta.txt")
[ -n "$root" ] && [ -d "$root" ] || {
	echo "verify-claims: meta.txt names no clone" >&2
	exit 1
}
METACHARS='[|;&><`$]'
TOOLCHAINS='make:GNUmakefile,makefile,Makefile npm:package.json pnpm:package.json yarn:package.json npx:package.json cargo:Cargo.toml go:go.mod pytest:pyproject.toml,pytest.ini,setup.cfg tox:tox.ini bundle:Gemfile mix:mix.exs mvn:pom.xml ./gradlew:gradlew swift:Package.swift dart:pubspec.yaml dotnet:*.sln,*.csproj'

work=$(mktemp -d "$dir/.verify.XXXXXX")
trap 'rm -rf "$work"' EXIT
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ -f "$dir/survey.txt" ]; then cp "$dir/survey.txt" "$work/survey"; else : >"$work/survey"; fi
git -C "$root" ls-files | LC_ALL=C sort >"$work/tracked"
sed -n 's/^survey: check [^ ]* //p' "$work/survey" >"$work/checks"
: >"$work/manifests"
for pair in $TOOLCHAINS; do
	tool=${pair%%:*}
	for m in $(printf '%s' "${pair#*:}" | tr ',' ' '); do
		for f in "$root"/$m; do
			[ -e "$f" ] && printf '%s\n' "$tool" >>"$work/manifests" && break
		done
	done
done
sort -u "$work/manifests" -o "$work/manifests"
: >"$work/tooling"
for record in "$dir/records"/*.txt; do
	[ -f "$record" ] || continue
	while IFS= read -r line; do
		case "$line" in
		"check "*" | "*)
			cmd=${line#check }
			printf '%s\n' "${cmd%% | *}"
			;;
		esac
	done <"$record"
done | while IFS= read -r cmd; do
	rc=0
	sh "$here/migration-tool.sh" "$cmd" || rc=$?
	case "$rc" in
	0) ;;
	3) printf '%s\n' "$cmd" >>"$work/tooling" ;;
	*) exit 1 ;;
	esac
done

# A migrations claim needs the files to show it: a tracked .sql file, or
# a file the survey's migration pattern matches, under a directory that
# is not a test directory.
: >"$work/migrations"
mig_re=$(sh "$here/survey-project.sh" lists migration-evidence | sed -n 2p)
cat "$dir/records"/*.txt 2>/dev/null | sed -n 's/^migrations \([^ ]*\) | .*/\1/p' | sort -u | while IFS= read -r ref; do
	case "$ref" in */ | */\*\*) ;; *) continue ;; esac
	d=${ref%\*\*}
	d=${d%/}
	if [ "$(printf '%s/x\n' "$d" | sh "$here/classify-change.sh" --classify | cut -f1)" = tests ]; then
		printf '%s test\n' "$ref"
		continue
	fi
	git --literal-pathspecs -C "$root" ls-files -z -- "$d/" | tr '\0' '\n' >"$work/under"
	[ -s "$work/under" ] || continue
	if grep -qE '\.sql$' "$work/under"; then
		printf '%s ok\n' "$ref"
	elif git --literal-pathspecs -C "$root" grep -qE -e "$mig_re" -- "$d/" 2>/dev/null; then
		printf '%s ok\n' "$ref"
	else
		printf '%s none\n' "$ref"
	fi
done >"$work/migrations"

ls "$dir/partitions" 2>/dev/null | grep -E '^[0-9]+\.txt$' | sed 's/\.txt$//' | sort -n >"$work/planned"
ls "$dir/records" 2>/dev/null | grep -E '^[0-9]+\.txt$' | sort -n >"$work/ids" || true
sed 's/\.txt$//' "$work/ids" >"$work/recorded"
missing=$(awk 'FILENAME == ARGV[1] { r[$0] = 1; next } !($0 in r)' "$work/recorded" "$work/planned" | tr '\n' ' ' | sed 's/ $//')
echo "verify: partitions $(grep -c . "$work/planned" || true) recorded $(grep -c . "$work/recorded" || true) missing ${missing:-none}"
awk -v tracked="$work/tracked" -v checks="$work/checks" -v manifests="$work/manifests" -v tooling="$work/tooling" -v migrations="$work/migrations" -v metachars="$METACHARS" -v records="$dir/records" '
function tracked_dir(d) { return (d in dirs) }
function check_ok(cmd,    first, second) {
	if (cmd ~ metachars) return 0
	if (cmd in candidate) return 1
	first = cmd; sub(/ .*$/, "", first)
	if (first == "sh") { second = cmd; sub(/^sh +/, "", second); sub(/ .*$/, "", second); return (second in file) }
	return (first in manifest)
}
BEGIN {
	# Every directory above a tracked file, as "dir/", built once.
	while ((getline line < tracked) > 0) { file[line] = 1; d = line; while (sub(/\/[^\/]*$/, "", d)) dirs[d "/"] = 1 }
	while ((getline line < checks) > 0) candidate[line] = 1
	while ((getline line < manifests) > 0) manifest[line] = 1
	while ((getline line < tooling) > 0) flagged[line] = 1
	while ((getline line < migrations) > 0) { split(line, f, " "); migration[f[1]] = f[2] }
}
{
	id = $0; sub(/\.txt$/, "", id)
	path = records "/" $0
	nrec++
	while ((getline line < path) > 0) {
		if (line ~ /^(## |[ \t]*$)/) continue
		kind = line; sub(/ .*$/, "", kind)
		ref = line; sub(/^[a-z]+ /, "", ref); sub(/ \| .*$/, "", ref)
		statement = line; sub(/^[^|]*\| /, "", statement)
		claims++
		ok = 0
		if (kind == "check" && (ref in flagged)) { dropped++; printf "verify: dropped %s %s %s (migration or database tooling)\n", id, kind, ref; continue }
		if (kind == "check") ok = check_ok(ref)
		else if (kind == "migrations") {
			if (migration[ref] == "test") { dropped++; printf "verify: dropped %s %s %s (a test directory)\n", id, kind, ref; continue }
			if (migration[ref] == "none") { dropped++; printf "verify: dropped %s %s %s (no migration files)\n", id, kind, ref; continue }
			ok = (migration[ref] == "ok")
		}
		else if (ref in file) ok = 1
		else if (ref ~ /\/\*\*$/) { d = ref; sub(/\*\*$/, "", d); ok = tracked_dir(d) }
		else if (ref ~ /\/$/) ok = tracked_dir(ref)
		if (!ok) { dropped++; printf "verify: dropped %s %s %s\n", id, kind, ref; continue }
		if ((kind, ref) in seen) { dupes++; continue }
		seen[kind, ref] = 1
		kept++
		printf "%s %s %s | %s\n", id, kind, ref, statement > "/dev/fd/3"
	}
	close(path)
}
END { printf "verify: records %d claims %d kept %d duplicate %d dropped %d\n", nrec, claims, kept, dupes, dropped }
' "$work/ids" 3>"$work/digest"
mv "$work/digest" "$dir/digest.txt"
