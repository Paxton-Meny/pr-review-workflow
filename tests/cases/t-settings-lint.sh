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

# The overlap check is raise-only for a project, and has an alias.
printf 'overlap_check off\n' >"$SCRATCH/overlap.conf"
if out=$(sh "$REPO_ROOT/scripts/resolve-settings.sh" --lint shared overlap.conf); then
	echo "a shared file lowering overlap_check must fail the lint" >&2
	exit 1
fi
printf '%s\n' "$out" | grep -qx 'settings: ignored project overlap_check: would lower near to off; a project may only raise it'
printf 'overlap judged\n' >"$SCRATCH/overlap.conf"
out=$(sh "$REPO_ROOT/scripts/resolve-settings.sh" --lint shared overlap.conf)
printf '%s\n' "$out" | grep -qx 'settings: overlap_check judged from project'
out=$(sh "$REPO_ROOT/scripts/resolve-settings.sh" --lint personal overlap.conf)
printf '%s\n' "$out" | grep -qx 'settings: overlap_check judged from local'

# A shared file may name the merge method.
printf 'merge_method squash\n' >"$SCRATCH/method.conf"
out=$(sh "$REPO_ROOT/scripts/resolve-settings.sh" --lint shared method.conf)
printf '%s\n' "$out" | grep -qx 'settings: merge_method squash from project'
printf '%s\n' "$out" | grep -qx 'settings: lint shared file 1 set, 0 refused'

# The checks settings only ever raise: a shared file may not turn the
# follow-up down, cut the repairs, or skip the review of them.
printf 'ci_checks wait\nci_fix_rounds 1\nreview_repairs false\nci_wait_minutes 60\n' >"$SCRATCH/ci.conf"
if out=$(sh "$REPO_ROOT/scripts/resolve-settings.sh" --lint shared ci.conf); then
	echo "a shared file lowering the checks settings must fail the lint" >&2
	exit 1
fi
printf '%s\n' "$out" | grep -qx 'settings: ignored project ci_checks: would lower fix to wait; a project may only raise it'
printf '%s\n' "$out" | grep -qx 'settings: ignored project ci_fix_rounds: would lower 2 to 1; a project may only raise it'
printf '%s\n' "$out" | grep -qx 'settings: ignored project review_repairs: would lower true to false; a project may only raise it'
printf '%s\n' "$out" | grep -qx 'settings: ci_wait_minutes 60 from project'
printf '%s\n' "$out" | grep -qx 'settings: lint shared file 1 set, 3 refused'
printf 'ci fix\nci_fix_rounds 3\n' >"$SCRATCH/ci2.conf"
out=$(sh "$REPO_ROOT/scripts/resolve-settings.sh" --lint shared ci2.conf)
printf '%s\n' "$out" | grep -qx 'settings: ci_fix_rounds 3 from project'
printf '%s\n' "$out" | grep -qx 'settings: lint shared file 2 set, 0 refused'
