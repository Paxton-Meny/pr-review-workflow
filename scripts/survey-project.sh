#!/bin/sh
# Report what the clone this runs in already states about itself, for the
# setup skill to decide from instead of asking.
# Usage: sh scripts/survey-project.sh facts [survey-dir]
#        sh scripts/survey-project.sh conventions
#        sh scripts/survey-project.sh lists skip|sensitive-names
#
# facts prints one line per fact, every one prefixed "survey:": the
# clone and its origin, the base branch (origin/HEAD, else the one of
# origin/main or origin/master that exists), how many people committed
# in the last year and whether a CODEOWNERS file exists, which of the
# two settings files exist and whether git tracks them (a file of your
# own counts when it sits in the main worktree, where setup writes it
# from a linked one), their current lines, whether the base branch's
# CLAUDE.md holds a conventions block, then the candidates: check
# commands best first (a Makefile target, a scripts/ gate, a package
# manifest's test script, a language toolchain's test command, each
# .NET test project apart when there are several or a browser suite
# among them, a CI run line), each named after the file that backs it,
# test runner prefixes a
# Check line could start with, directories whose names suggest a defect
# costs most, directories that hold database migrations with the
# evidence for each, directories named like migrations that hold none,
# and markdown files at the root that git ignores whose names say they
# hold rules (laws, standards, conventions, guidelines, policies), which
# is where untracked rules files live. A candidate command that names
# migration or database tooling is never offered; it prints as skipped.
# The last line counts each kind. Given the survey directory that
# inventory-repo.sh made, facts also saves its lines there as
# survey.txt, where the later setup scripts read them. Nothing else is
# written, nothing is fetched, and nothing in the clone is run:
# migrations are found by reading.
#
# conventions prints the review-conventions block from the base
# branch's CLAUDE.md, nothing else, and exits 3 when there is none.
#
# lists prints one of this script's name lists as the regex alternation
# it uses, so other scripts share it: skip (directories no scan enters),
# sensitive-names (directory names where a defect costs most), or
# migration-evidence (two lines: the file names searched for migration
# code, then the pattern that marks a file as a migration). It needs no
# clone.
set -eu

mode=${1:?usage: survey-project.sh facts|conventions|lists skip|sensitive-names|migration-evidence}
case "$mode" in
facts | conventions | lists) ;;
*)
	echo "survey-project: mode must be facts, conventions, or lists: $mode" >&2
	exit 1
	;;
esac

SHARED=.claude/pr-review-workflow.conf
LOCAL=.claude/pr-review-workflow.local.conf
BEGIN_MARK='<!-- review-conventions:begin -->'
END_MARK='<!-- review-conventions:end -->'
MAX_EXISTING_LINES=60
MAX_SENSITIVE=12
MAX_CI_LINES_PER_WORKFLOW=3
MAX_MIGRATION_DIRS=20
MAX_SLN_DEPTH=3
MIGRATION_EXT='\.(py|rb|php|ex|exs|js|mjs|cjs|ts|cs|sql|xml|ya?ml)$'
MIGRATION_RE='class [A-Za-z0-9_]+\(migrations\.Migration\)|^down_revision[^=]*=|ActiveRecord::Migration|use Ecto\.Migration|implements MigrationInterface|exports\.up[[:space:]]*=|extends Migration|-- \+goose Up|databaseChangeLog|\[Migration\(|MigrationBuilder'
SENSITIVE_NAMES='auth|authn|authz|oauth|oidc|sso|login|session|sessions|identity|password|passwords|credential|credentials|secret|secrets|token|tokens|crypto|kms|vault|payment|payments|billing|checkout|invoice|invoices|wallet|ledger|permission|permissions|acl|rbac|policy|policies|security|admin'
SKIP_DIRS='test|tests|spec|specs|__tests__|fixtures|fixture|testdata|mocks|docs|doc|examples|example|node_modules|vendor|third_party|dist|build'
RULEBOOK_NAMES='laws|rules|standards|conventions|guidelines?|polic(y|ies)|principles|requirements'

if [ "$mode" = lists ]; then
	case "${2:-}" in
	skip) printf '%s\n' "$SKIP_DIRS" ;;
	sensitive-names) printf '%s\n' "$SENSITIVE_NAMES" ;;
	migration-evidence) printf '%s\n%s\n' "$MIGRATION_EXT" "$MIGRATION_RE" ;;
	*)
		echo "survey-project: lists takes skip, sensitive-names, or migration-evidence" >&2
		exit 1
		;;
	esac
	exit 0
fi

if [ "$mode" = facts ] && [ -n "${2:-}" ]; then
	[ -f "$2/meta.txt" ] || {
		echo "survey-project: no meta.txt in $2, run inventory-repo.sh first" >&2
		exit 1
	}
	saved=$(mktemp "$2/.survey.XXXXXX")
	rc=0
	sh "$0" facts >"$saved" || rc=$?
	if [ "$rc" -ne 0 ]; then
		cat "$saved"
		rm -f "$saved"
		exit "$rc"
	fi
	mv "$saved" "$2/survey.txt"
	cat "$2/survey.txt"
	exit 0
fi

clone=$(git rev-parse --show-toplevel 2>/dev/null) || {
	echo "survey-project: run it from inside a clone" >&2
	exit 1
}
url=$(git -C "$clone" remote get-url origin 2>/dev/null) || {
	echo "survey-project: the clone at $clone has no origin remote" >&2
	exit 1
}
trimmed=${url%/}
trimmed=${trimmed%.git}
repo=${trimmed##*/}
rest=${trimmed%/*}
owner=${rest##*[:/]}
base=$(sh "$(dirname -- "$0")/origin-base.sh" "$clone" 2>/dev/null) || base=''
base_ref=''
[ -n "$base" ] && git -C "$clone" rev-parse --verify --quiet "refs/remotes/origin/$base" >/dev/null && base_ref="refs/remotes/origin/$base"


conventions_block() {
	[ -n "$base_ref" ] || return 1
	git -C "$clone" show "$base_ref:CLAUDE.md" 2>/dev/null | awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
	index($0, b) { take = 1; next }
	index($0, e) { take = 0 }
	take' | grep . || return 1
}

if [ "$mode" = conventions ]; then
	conventions_block || {
		echo "survey-project: no conventions block on the base branch" >&2
		exit 3
	}
	exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$clone"
echo "survey: clone $clone"
echo "survey: origin $owner/$repo base ${base:-unknown}"

authors=$(git log --since='1 year ago' --format=%ae 2>/dev/null | sort -u | grep -c . || true)
codeowners=no
for f in CODEOWNERS .github/CODEOWNERS docs/CODEOWNERS; do
	[ -f "$f" ] && codeowners=yes
done
echo "survey: authors $authors in the last year, codeowners $codeowners"

# A file of your own may live in the main worktree, where setup writes it
# from a linked one so every worktree reads it.
main_root=$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')
[ -n "$main_root" ] && [ "$main_root" != "$clone" ] || main_root=''
located() {
	if [ -n "$main_root" ] && [ ! -e "$1" ] && [ ! -L "$1" ] && { [ -e "$main_root/$1" ] || [ -L "$main_root/$1" ]; }; then
		printf '%s\n' "$main_root/$1"
	else
		printf '%s\n' "$1"
	fi
}
file_state() {
	if git ls-files --error-unmatch "$1" >/dev/null 2>&1; then
		[ -L "$1" ] && echo refused || echo tracked
		return
	fi
	at=$(located "$1")
	if [ -L "$at" ]; then
		echo refused
	elif [ "$at" != "$1" ] && git -C "$main_root" ls-files --error-unmatch "$1" >/dev/null 2>&1; then
		echo tracked
	elif [ -f "$at" ]; then
		echo untracked
	else
		echo absent
	fi
}
shared_state=$(file_state "$SHARED")
local_state=$(file_state "$LOCAL")
case "$local_state" in untracked) local_state=present ;; esac
echo "survey: project file $shared_state, local file $local_state"


show_existing() {
	at=$(located "$1")
	[ -f "$at" ] && [ ! -L "$at" ] || return 0
	[ "$at" = "$1" ] || echo "survey: located $1 in the main worktree $main_root"
	head -n "$MAX_EXISTING_LINES" "$at" | tr -d '\r' | sed "s|^|survey: existing $1: |"
	total=$(grep -c '' "$at" || true)
	[ "$total" -le "$MAX_EXISTING_LINES" ] || echo "survey: existing $1: ... $((total - MAX_EXISTING_LINES)) more lines"
}
show_existing "$SHARED"
show_existing "$LOCAL"

if block=$(conventions_block); then
	echo "survey: conventions block $(printf '%s\n' "$block" | grep -c .) lines"
elif [ -n "$base_ref" ]; then
	echo "survey: conventions block absent"
else
	echo "survey: conventions block unknown, no base branch fetched"
fi

: >"$work/checks"
: >"$work/prefixes"
: >"$work/skipped"
tooling() {
	rc=0
	sh "$(dirname -- "$0")/migration-tool.sh" "$2" || rc=$?
	case "$rc" in
	0) return 1 ;;
	3)
		grep -qxF -- "$2" "$work/skipped" && return 0
		printf '%s\n' "$2" >>"$work/skipped"
		echo "survey: skipped $1 $2 (migration or database tooling)"
		return 0
		;;
	*) exit 1 ;;
	esac
}
check() {
	tooling "$1" "$2" && return 0
	grep -qxF -- "$2" "$work/checks" && return 0
	printf '%s\n' "$2" >>"$work/checks"
	echo "survey: check $1 $2"
}
prefix() {
	tooling "$1" "$2" && return 0
	grep -qxF -- "$2" "$work/checks" && return 0
	grep -qxF -- "$2" "$work/prefixes" && return 0
	printf '%s\n' "$2" >>"$work/prefixes"
	echo "survey: prefix $1 $2"
}

make_target() {
	for m in GNUmakefile makefile Makefile; do
		[ -f "$m" ] && grep -qE "^$1[[:space:]]*:" "$m" && return 0
	done
	return 1
}
make_target check && check makefile 'make check'
[ -f scripts/gate.sh ] && check scripts 'sh scripts/gate.sh'
make_target test && check makefile 'make test'
[ -f scripts/check.sh ] && check scripts 'sh scripts/check.sh'
[ -f scripts/test.sh ] && check scripts 'sh scripts/test.sh'

if [ -f package.json ]; then
	pm=npm
	[ -f pnpm-lock.yaml ] && pm=pnpm
	[ -f yarn.lock ] && pm=yarn
	awk '/"scripts"[[:space:]]*:[[:space:]]*\{/ { take = 1; next } take && /^[[:space:]]*\}/ { exit } take' package.json >"$work/scripts"
	script_named() { grep -qE "^[[:space:]]*\"$1\"[[:space:]]*:" "$work/scripts"; }
	script_named check && check package.json "$pm run check"
	if script_named test && ! grep -qE '"test"[[:space:]]*:[[:space:]]*"echo .*no test specified' "$work/scripts"; then
		check package.json "$pm test"
	fi
	dev_dep() { grep -qE "^[[:space:]]*\"$1\"[[:space:]]*:" package.json; }
	dev_dep vitest && prefix package.json 'npx vitest'
	dev_dep jest && prefix package.json 'npx jest'
	dev_dep mocha && prefix package.json 'npx mocha'
	dev_dep '@playwright/test' && prefix package.json 'npx playwright test'
fi
if [ -f Cargo.toml ]; then
	check Cargo.toml 'cargo test'
	prefix Cargo.toml 'cargo test'
fi
if [ -f go.mod ]; then
	check go.mod 'go test ./...'
	prefix go.mod 'go test'
fi
[ -f tox.ini ] && check tox.ini tox
pytest_configured() {
	[ -f pytest.ini ] && return 0
	[ -f pyproject.toml ] && grep -qE '^\[tool\.pytest|pytest' pyproject.toml && return 0
	[ -f setup.cfg ] && grep -q '\[tool:pytest\]' setup.cfg && return 0
	return 1
}
if pytest_configured; then
	check pytest pytest
	prefix pytest pytest
fi
if [ -f Gemfile ]; then
	[ -f Rakefile ] && check Rakefile 'bundle exec rake'
	grep -qE "^[[:space:]]*gem ['\"]rspec" Gemfile && prefix Gemfile 'bundle exec rspec'
fi
[ -f mix.exs ] && check mix.exs 'mix test'
[ -f pom.xml ] && check pom.xml 'mvn -q test'
[ -f gradlew ] && check gradlew './gradlew test'
[ -f Package.swift ] && check Package.swift 'swift test'
[ -f pubspec.yaml ] && check pubspec.yaml 'dart test'
# .NET: a solution or project at the root, else the one solution near it,
# runs every test project it holds. When the tree holds more than one test
# project, or a browser suite that needs the app running, each project
# other than the browser suites is offered on its own instead, the one
# with the most files first, and each browser suite prints as skipped.
# A candidate is named after the file that backs it, or "dotnet" when
# that name holds a space.
git ls-files 2>/dev/null >"$work/tracked"
dotnet_root=''
for f in ./*.sln ./*.csproj; do
	[ -f "$f" ] && dotnet_root=${f#./} && break
done
if [ -z "$dotnet_root" ]; then
	awk -F/ -v max="$MAX_SLN_DEPTH" '/\.sln$/ && !/ / && NF - 1 <= max' "$work/tracked" >"$work/sln"
	[ "$(grep -c '' "$work/sln" || true)" -eq 1 ] && dotnet_root=$(cat "$work/sln")
fi
if [ -n "$dotnet_root" ]; then
	label=${dotnet_root##*/}
	case "$label" in *' '*) label=dotnet ;; esac
	grep -E '\.(cs|fs|vb)proj$' "$work/tracked" | grep -v ' ' >"$work/projects" || true
	: >"$work/sdk-projects"
	: >"$work/browser-projects"
	if [ -s "$work/projects" ]; then
		tr '\n' '\0' <"$work/projects" | xargs -0 grep -liE 'Microsoft\.NET\.Test\.Sdk|Include="(xunit|nunit|MSTest)' -- >"$work/sdk-projects" 2>/dev/null || true
		tr '\n' '\0' <"$work/projects" | xargs -0 grep -liE 'Playwright|Selenium|Appium' -- >"$work/browser-candidates" 2>/dev/null || true
	fi
	# One pass: the test projects (by package or by name), the browser
	# suites among them, and each other one's tracked file count.
	awk -v sdk="$work/sdk-projects" -v browser="$work/browser-candidates" -v browsers="$work/browser-projects" -v tracked="$work/tracked" '
	BEGIN {
		while ((getline p < sdk) > 0) is_sdk[p] = 1
		while ((getline p < browser) > 0) is_browser[p] = 1
	}
	{
		name = $0; sub(/.*\//, "", name)
		if (!($0 in is_sdk) && name !~ /([.]Tests?|Tests)[.](cs|fs|vb)proj$/) next
		if ($0 in is_browser) { print $0 > browsers; next }
		d = $0; if (d ~ /\//) sub(/\/[^\/]*$/, "", d); else d = ""
		dir[d] = 1; proj[++n] = $0; pdir[n] = d
	}
	END {
		while ((getline f < tracked) > 0) {
			count[""]++
			p = f
			while (sub(/\/[^\/]*$/, "", p)) if (p in dir) count[p]++
		}
		for (i = 1; i <= n; i++) printf "%d\t%s\n", count[pdir[i]], proj[i]
	}' "$work/projects" >"$work/test-projects"
	tests_n=$(grep -c '' "$work/test-projects" || true)
	browsers_n=$(grep -c '' "$work/browser-projects" || true)
	if [ "$tests_n" -gt 1 ] || [ "$browsers_n" -ge 1 ]; then
		sort -t "$(printf '\t')" -k1,1nr -k2,2 "$work/test-projects" | cut -f2 | while IFS= read -r proj; do
			check "${proj##*/}" "dotnet test $proj"
		done
		while IFS= read -r proj; do
			echo "survey: skipped ${proj##*/} dotnet test $proj (browser suite: it needs the app running)"
		done <"$work/browser-projects"
	elif [ "${dotnet_root%/*}" = "$dotnet_root" ]; then
		check "$label" 'dotnet test'
	else
		check "$label" "dotnet test $dotnet_root"
	fi
	[ "$tests_n" -eq 0 ] && [ "$browsers_n" -ge 1 ] || prefix "$label" 'dotnet test'
fi

for wf in .github/workflows/*.yml .github/workflows/*.yaml; do
	[ -f "$wf" ] || continue
	sed -n 's/^[[:space:]]*-\{0,1\}[[:space:]]*run:[[:space:]]*//p' "$wf" | tr -d '\r' |
		grep -E '(^|[[:space:]])(test|check|verify)([[:space:]]|$)' | grep -vE '[|;&><`$]' |
		head -n "$MAX_CI_LINES_PER_WORKFLOW" >"$work/ci"
	while IFS= read -r cmd; do
		[ -n "$cmd" ] && check "ci:${wf##*/}" "$cmd"
	done <"$work/ci"
done

git ls-files -z 2>/dev/null | tr '\0' '\n' | awk -v names="^($SENSITIVE_NAMES)\$" -v skip="^($SKIP_DIRS)\$" -v max="$MAX_SENSITIVE" '
{
	n = split($0, part, "/")
	path = ""
	hit = ""
	for (i = 1; i < n; i++) {
		if (tolower(part[i]) ~ skip) break
		path = (path == "" ? part[i] : path "/" part[i])
		if (tolower(part[i]) ~ names) hit = path
	}
	if (hit != "" && !(hit in seen)) { seen[hit] = 1; order[++count] = hit }
}
END { for (i = 1; i <= count && i <= max; i++) print order[i] }
' >"$work/sensitive"
while IFS= read -r d; do
	echo "survey: sensitive $d/**"
done <"$work/sensitive"

grep -E "$MIGRATION_EXT" "$work/tracked" | tr '\n' '\0' |
	xargs -0 grep -HoE -m 1 -- "$MIGRATION_RE" 2>/dev/null | awk '{
	i = index($0, ":"); path = substr($0, 1, i - 1); m = substr($0, i + 1)
	d = path; if (d ~ /\//) sub(/\/[^\/]*$/, "", d); else d = "."
	if (m ~ /migrations\.Migration/) f = "django"
	else if (m ~ /down_revision/) f = "alembic"
	else if (m ~ /ActiveRecord/) f = "rails"
	else if (m ~ /Ecto/) f = "ecto"
	else if (m ~ /MigrationInterface/) f = "typeorm"
	else if (m ~ /exports\.up/) f = "knex"
	else if (m ~ /goose/) f = "goose"
	else if (m ~ /databaseChangeLog/) f = "liquibase"
	else if (m ~ /MigrationBuilder/) f = "ef-core"
	else if (m ~ /\[Migration\(/) f = "ef-core-or-fluentmigrator"
	else f = "laravel"
	print d "\t" f
}' >"$work/mig-evidence" || true
awk '{
	n = split($0, part, "/"); base = part[n]
	d = $0; if (d ~ /\//) sub(/\/[^\/]*$/, "", d); else d = "."
	up = d; if (up ~ /\//) sub(/\/[^\/]*$/, "", up); else up = "."
	if (base ~ /\.up\.sql$/) print d "\tgolang-migrate"
	else if (base == "up.sql") print up "\tdiesel"
	else if (base ~ /^V[0-9][0-9_.]*__.*\.sql$/) print d "\tflyway"
	else if ($0 ~ /(^|\/)prisma\/migrations\/[^\/]+\/migration\.sql$/) print up "\tprisma"
	else if (base ~ /\.sqlproj$/) print d "\tssdt"
	else if (base == "sqitch.plan") { p = (d == "." ? "" : d "/"); print p "deploy\tsqitch"; print p "revert\tsqitch"; print p "verify\tsqitch" }
}' "$work/tracked" >>"$work/mig-evidence"
grep -E '(^|/)alembic\.ini$' "$work/tracked" | while IFS= read -r ini; do
	loc=$(sed -n 's/^[[:space:]]*script_location[[:space:]]*=[[:space:]]*//p' "$ini" | tr -d '\r' | sed 's/^%(here)s\///' | head -n 1)
	[ -n "$loc" ] || continue
	case "$ini" in */*) loc="${ini%/*}/$loc" ;; esac
	printf '%s/versions\talembic\n' "${loc%/}"
done >>"$work/mig-evidence"
grep -E '(^|/)flyway\.(conf|toml)$' "$work/tracked" | while IFS= read -r conf; do
	grep -oE 'filesystem:[^,"[:space:]]+' "$conf" | sed 's/^filesystem://; s/\/$//' | while IFS= read -r loc; do
		printf '%s\tflyway\n' "$loc"
	done
done >>"$work/mig-evidence"
grep -E '\.csproj$' "$work/tracked" | while IFS= read -r proj; do
	grep -qiE 'Include="dbup' "$proj" || continue
	pdir=.
	case "$proj" in */*) pdir=${proj%/*} ;; esac
	awk -v pre="$pdir/" '/\.sql$/ && (pre == "./" || index($0, pre) == 1) { d = $0; sub(/\/[^\/]*$/, "", d); print d "\tdbup" }' "$work/tracked"
done >>"$work/mig-evidence"
awk -F '\t' -v max="$MAX_MIGRATION_DIRS" -v tracked="$work/tracked" '
BEGIN { while ((getline t < tracked) > 0) { n = split(t, part, "/"); p = ""; for (i = 1; i < n; i++) { p = (p == "" ? part[i] : p "/" part[i]); has[p] = 1 } } }
$1 != "." && $1 != "" && ($1 in has) && !($1 in seen) { seen[$1] = 1; if (++count <= max) print $1 " " $2 }
' "$work/mig-evidence" >"$work/migrations"
while IFS= read -r line; do
	echo "survey: migrations $line"
done <"$work/migrations"
awk -v ev="$work/migrations" '
BEGIN { while ((getline e < ev) > 0) { split(e, f, " "); dirs[f[1]] = 1 } }
{
	n = split($0, part, "/"); p = ""
	for (i = 1; i < n; i++) {
		p = (p == "" ? part[i] : p "/" part[i])
		if (tolower(part[i]) ~ /^(migrations?|migrate)$/ && !(p in named)) named[p] = 1
	}
}
END {
	for (p in named) {
		covered = 0
		for (d in dirs) if (d == p || index(d, p "/") == 1 || index(p, d "/") == 1) covered = 1
		if (!covered) print p
	}
}' "$work/tracked" | sort >"$work/migration-named"
while IFS= read -r d; do
	echo "survey: migration-named $d"
done <"$work/migration-named"

: >"$work/standards"
for root in "$clone" ${main_root:+"$main_root"}; do
	git -C "$root" ls-files --others --ignored --exclude-standard 2>/dev/null | grep -E '^[^/]+\.md$' | grep -vx CLAUDE.md | grep -iE "$RULEBOOK_NAMES" >"$work/ignored" || true
	while IFS= read -r f; do
		grep -qxF -- "$f" "$work/standards" && continue
		[ -L "$root/$f" ] && continue
		printf '%s\n' "$f" >>"$work/standards"
		echo "survey: standards $f"
	done <"$work/ignored"
done

count() { grep -c '' "$1" || true; }
echo "survey: found check $(count "$work/checks") prefix $(count "$work/prefixes") sensitive $(count "$work/sensitive") migrations $(count "$work/migrations") standards $(count "$work/standards")"
