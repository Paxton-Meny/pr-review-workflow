#!/bin/sh
# Report what the clone this runs in already states about itself, for the
# setup skill to decide from instead of asking.
# Usage: sh scripts/survey-project.sh facts
#        sh scripts/survey-project.sh conventions
#        sh scripts/survey-project.sh lists skip|sensitive-names
#
# facts prints one line per fact, every one prefixed "survey:": the
# clone and its origin, the base branch (origin/HEAD, else the one of
# origin/main or origin/master that exists), how many people committed
# in the last year and whether a CODEOWNERS file exists, which of the
# two settings files exist and whether git tracks them, their current
# lines, whether the base branch's CLAUDE.md holds a conventions block,
# then the candidates: check commands best first (a Makefile target, a
# scripts/ gate, a package manifest's test script, a language
# toolchain's test command, a CI run line), test runner prefixes a
# Check line could start with, directories whose names suggest a defect
# costs most, and markdown files at the root that git ignores whose
# names say they hold rules (laws, standards, conventions, guidelines,
# policies), which is where untracked rules files live. The last line
# counts each kind. Nothing is fetched and nothing written.
#
# conventions prints the review-conventions block from the base
# branch's CLAUDE.md, nothing else, and exits 3 when there is none.
#
# lists prints one of this script's name lists as the regex alternation
# it uses, so other scripts share it: skip (directories no scan enters)
# or sensitive-names (directory names where a defect costs most).
set -eu

mode=${1:?usage: survey-project.sh facts|conventions|lists skip|sensitive-names}
case "$mode" in
facts | conventions | lists) ;;
*)
	echo "survey-project: mode must be facts, conventions, or lists: $mode" >&2
	exit 1
	;;
esac

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

SHARED=.claude/pr-review-workflow.conf
LOCAL=.claude/pr-review-workflow.local.conf
BEGIN_MARK='<!-- review-conventions:begin -->'
END_MARK='<!-- review-conventions:end -->'
MAX_EXISTING_LINES=60
MAX_SENSITIVE=12
MAX_CI_LINES_PER_WORKFLOW=3
SENSITIVE_NAMES='auth|authn|authz|oauth|oidc|sso|login|session|sessions|identity|password|passwords|credential|credentials|secret|secrets|token|tokens|crypto|kms|vault|payment|payments|billing|checkout|invoice|invoices|wallet|ledger|migration|migrations|permission|permissions|acl|rbac|policy|policies|security|admin'
SKIP_DIRS='test|tests|spec|specs|__tests__|fixtures|fixture|testdata|mocks|docs|doc|examples|example|node_modules|vendor|third_party|dist|build'
RULEBOOK_NAMES='laws|rules|standards|conventions|guidelines?|polic(y|ies)|principles|requirements'

if [ "$mode" = lists ]; then
	case "${2:-}" in
	skip) printf '%s\n' "$SKIP_DIRS" ;;
	sensitive-names) printf '%s\n' "$SENSITIVE_NAMES" ;;
	*)
		echo "survey-project: lists takes skip or sensitive-names" >&2
		exit 1
		;;
	esac
	exit 0
fi

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

file_state() {
	if [ -L "$1" ]; then
		echo refused
	elif git ls-files --error-unmatch "$1" >/dev/null 2>&1; then
		echo tracked
	elif [ -f "$1" ]; then
		echo untracked
	else
		echo absent
	fi
}
shared_state=$(file_state "$SHARED")
local_state=$(file_state "$LOCAL")
case "$local_state" in untracked) local_state=present ;; esac
echo "survey: project file $shared_state, local file $local_state"

case "$shared_state$local_state" in
tracked*) audience=team ;;
untracked*) audience=personal ;;
*present) audience=local ;;
*)
	if [ "$authors" -gt 1 ] || [ "$codeowners" = yes ]; then
		audience=team
	else
		audience=personal
	fi
	;;
esac
echo "survey: audience $audience suggested"

show_existing() {
	[ -f "$1" ] && [ ! -L "$1" ] || return 0
	head -n "$MAX_EXISTING_LINES" "$1" | tr -d '\r' | sed "s|^|survey: existing $1: |"
	total=$(grep -c '' "$1" || true)
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
check() {
	grep -qxF -- "$2" "$work/checks" && return 0
	printf '%s\n' "$2" >>"$work/checks"
	echo "survey: check $1 $2"
}
prefix() {
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
if ls ./*.sln >/dev/null 2>&1 || ls ./*.csproj >/dev/null 2>&1; then
	check dotnet 'dotnet test'
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

main_root=$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')
[ -n "$main_root" ] && [ "$main_root" != "$clone" ] || main_root=''
: >"$work/standards"
for root in "$clone" $main_root; do
	git -C "$root" ls-files --others --ignored --exclude-standard 2>/dev/null | grep -E '^[^/]+\.md$' | grep -vx CLAUDE.md | grep -iE "$RULEBOOK_NAMES" >"$work/ignored" || true
	while IFS= read -r f; do
		grep -qxF -- "$f" "$work/standards" && continue
		[ -L "$root/$f" ] && continue
		printf '%s\n' "$f" >>"$work/standards"
		echo "survey: standards $f"
	done <"$work/ignored"
done

count() { grep -c '' "$1" || true; }
echo "survey: found check $(count "$work/checks") prefix $(count "$work/prefixes") sensitive $(count "$work/sensitive") standards $(count "$work/standards")"
