#!/bin/sh
# resolve-settings --lint: a file judged as the shared or a personal
# source before it exists anywhere, every refusal named, commands
# flagged for approval, and nothing written.
set -eu

cat >"$SCRATCH/shared.conf" <<'CONF'
# profile: careful
check_command npm test -- --ci
prefixes npx vitest
double_review always
finding_filter false
cost_posture quality
samples 2
auto_approve true
standards RULES.md
sensitive_paths src/auth/**
CONF

cd "$SCRATCH"
if out=$(sh "$REPO_ROOT/scripts/resolve-settings.sh" --lint shared shared.conf); then
	echo "a shared file setting auto_approve must fail the lint" >&2
	exit 1
fi
printf '%s\n' "$out" | grep -qx 'settings: ignored project auto_approve: only you can set this, in your own configuration or local file'
printf '%s\n' "$out" | grep -qx 'settings: ignored project local_standards: only you can set this, in your own configuration or local file'
printf '%s\n' "$out" | grep -qx 'settings: ignored project finding_filter: would lower true to false; a project may only raise it'
printf '%s\n' "$out" | grep -q '^settings: trust pending [0-9a-f]* check_command npm test -- --ci$'
printf '%s\n' "$out" | grep -q '^settings: trust pending [0-9a-f]* contract_commands npx vitest$'
printf '%s\n' "$out" | grep -qx 'settings: double_review always from project'
printf '%s\n' "$out" | grep -qx 'settings: review_samples 2 from project'
printf '%s\n' "$out" | grep -qxF 'settings: sensitive_paths src/auth/** from project'
printf '%s\n' "$out" | grep -qx 'settings: lint shared file 4 set, 3 refused'
! printf '%s\n' "$out" | grep -q 'project file'

# The same file is fine as a personal one.
out=$(sh "$REPO_ROOT/scripts/resolve-settings.sh" --lint personal shared.conf)
printf '%s\n' "$out" | grep -qx 'settings: auto_approve true from local'
printf '%s\n' "$out" | grep -qx 'settings: check_command npm test -- --ci from local'
printf '%s\n' "$out" | grep -qx 'settings: local_standards RULES.md from local'
printf '%s\n' "$out" | grep -qx 'settings: lint personal file 9 set, 0 refused'
! printf '%s\n' "$out" | grep -q 'trust pending'

# Unknown keys and bad values are refused in either role.
printf 'double_review sometimes\nmystery 1\n' >"$SCRATCH/bad.conf"
if out=$(sh "$REPO_ROOT/scripts/resolve-settings.sh" --lint personal bad.conf); then
	echo "a bad value must fail the lint" >&2
	exit 1
fi
printf '%s\n' "$out" | grep -qx 'settings: ignored local mystery: unknown setting'
printf '%s\n' "$out" | grep -qx 'settings: ignored local double_review: not one of: off risky always'
printf '%s\n' "$out" | grep -qx 'settings: lint personal file 0 set, 2 refused'

# Bad arguments refuse up front.
if sh "$REPO_ROOT/scripts/resolve-settings.sh" --lint team shared.conf 2>/dev/null; then
	echo "expected refusal of an unknown lint role" >&2
	exit 1
fi
if sh "$REPO_ROOT/scripts/resolve-settings.sh" --lint shared missing.conf 2>/dev/null; then
	echo "expected refusal of a missing file" >&2
	exit 1
fi

# Nothing was written anywhere near the files.
[ "$(ls "$SCRATCH" | grep -vx log)" = "$(printf 'bad.conf\nshared.conf')" ]
