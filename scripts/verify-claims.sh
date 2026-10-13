#!/bin/sh
# Keep only the claims in the cartographers' records that the repository
# itself confirms, and write them as the digest the rest of setup reads.
# Usage: sh scripts/verify-claims.sh <survey-dir> < survey lines
#
# A path claim stands when its ref is a tracked file, or a tracked
# directory written as dir/ or dir/**. A check claim stands when its
# command equals a check candidate the survey printed (the "survey:
# check" lines on stdin), or is "sh <tracked script>", or starts with a
# toolchain whose manifest the clone holds; a command holding a shell
# metacharacter never stands. Writes digest.txt, one "<id> <kind> <ref>
# | <statement>" per kept claim with the first statement kept where two
# records cite the same kind and ref, prints one "verify: dropped <id>
# <kind> <ref>" line per drop, and ends with
# "verify: records N claims N kept N dropped N".
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
[ -d "$dir/records" ] || {
	echo "verify-claims: no records in $dir, nothing to verify" >&2
	exit 1
}
METACHARS='[|;&><`$]'
TOOLCHAINS='make:GNUmakefile,makefile,Makefile npm:package.json pnpm:package.json yarn:package.json npx:package.json cargo:Cargo.toml go:go.mod pytest:pyproject.toml,pytest.ini,setup.cfg tox:tox.ini bundle:Gemfile mix:mix.exs mvn:pom.xml ./gradlew:gradlew swift:Package.swift dart:pubspec.yaml dotnet:*.sln,*.csproj'

work=$(mktemp -d "$dir/.verify.XXXXXX")
trap 'rm -rf "$work"' EXIT
cat >"$work/survey"
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

ls "$dir/records" | grep -E '^[0-9]+\.txt$' | sort -n >"$work/ids"
awk -v tracked="$work/tracked" -v checks="$work/checks" -v manifests="$work/manifests" -v metachars="$METACHARS" -v records="$dir/records" '
function tracked_dir(d,    i) { for (i = 1; i <= nt; i++) if (index(t[i], d) == 1) return 1; return 0 }
function check_ok(cmd,    first, second) {
	if (cmd ~ metachars) return 0
	if (cmd in candidate) return 1
	first = cmd; sub(/ .*$/, "", first)
	if (first == "sh") { second = cmd; sub(/^sh +/, "", second); sub(/ .*$/, "", second); return (second in file) }
	return (first in manifest)
}
BEGIN {
	while ((getline line < tracked) > 0) { t[++nt] = line; file[line] = 1 }
	while ((getline line < checks) > 0) candidate[line] = 1
	while ((getline line < manifests) > 0) manifest[line] = 1
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
		if (kind == "check") ok = check_ok(ref)
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
END { printf "verify: records %d claims %d kept %d dropped %d\n", nrec, claims, kept, dropped }
' "$work/ids" 3>"$work/digest"
mv "$work/digest" "$dir/digest.txt"
