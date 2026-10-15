#!/bin/sh
# init-state: creates the ledger, validates refs, refuses non-open PRs, idempotent.
set -eu

stub="$SCRATCH/stub"
mkdir -p "$stub"
export GH_STUB_DIR="$stub"
export PATH="$REPO_ROOT/tests/stubs:$PATH"
data="$SCRATCH/data"

printf 'author Paxton-Meny\nhead_branch feat-thing\nbase_branch main\nhead_sha abc123\nurl https://github.com/Paxton-Meny/widgets/pull/7\ncross_repo false\nmaintainer_can_modify true\nhead_repo_url https://github.com/Paxton-Meny/widgets.git\nstate OPEN\n' >"$stub/pr-view"
printf 'Paxton-Meny 308824607\n' >"$stub/api-user"

clone="$SCRATCH/clone"
git init -q "$clone"
git -C "$clone" remote add origin https://github.com/Paxton-Meny/widgets.git
cd "$clone"

dir=$(sh "$REPO_ROOT/scripts/init-state.sh" "$data" "Paxton-Meny/widgets#7")
[ "$dir" = "$data/state/Paxton-Meny__widgets__7" ]
grep -qx 'owner Paxton-Meny' "$dir/meta.txt"
grep -qx 'head_sha abc123' "$dir/meta.txt"
grep -qx 'self_login Paxton-Meny' "$dir/meta.txt"
grep -qx 'self_email 308824607+Paxton-Meny@users.noreply.github.com' "$dir/meta.txt"
grep -qx 'cross_repo false' "$dir/meta.txt"
grep -qx 'maintainer_can_modify true' "$dir/meta.txt"
grep -q '^head_repo_url https://github.com/Paxton-Meny/widgets.git$' "$dir/meta.txt"
grep -qx '0' "$dir/round.txt"
! grep -q '^state ' "$dir/meta.txt"

url_dir=$(sh "$REPO_ROOT/scripts/init-state.sh" "$data" "https://github.com/Paxton-Meny/widgets/pull/7")
[ "$url_dir" = "$dir" ]

grep -q "^repo_root $clone\$" "$dir/meta.txt" || grep -q '^repo_root .*/clone$' "$dir/meta.txt"
[ ! -s "$dir/overrides.txt" ]

# Per-run overrides arrive on stdin, quoted values keep their spaces, and
# nothing typed is ever executed.
marker="$SCRATCH/ran"
sh "$REPO_ROOT/scripts/init-state.sh" "$data" - >/dev/null <<EOF
  Paxton-Meny/widgets#7   posture=quality check_command="npm test -- --ci" note='it'"'"'s \$(touch $marker)'
EOF
[ ! -e "$marker" ]
printf 'posture quality\ncheck_command npm test -- --ci\nnote it'"'"'s $(touch %s)\n' "$marker" >"$SCRATCH/want"
cmp -s "$dir/overrides.txt" "$SCRATCH/want" || { cat "$dir/overrides.txt" >&2; exit 1; }

# A later invocation without overrides clears them.
printf 'Paxton-Meny/widgets#7\n' | sh "$REPO_ROOT/scripts/init-state.sh" "$data" - >/dev/null
[ ! -s "$dir/overrides.txt" ]

for bad in 'Paxton-Meny/widgets#7 posture' 'Paxton-Meny/widgets#7 Posture=x' "Paxton-Meny/widgets#7 check=\"npm test"; do
	if printf '%s\n' "$bad" | sh "$REPO_ROOT/scripts/init-state.sh" "$data" - 2>"$SCRATCH/err" >/dev/null; then
		echo "expected refusal of: $bad" >&2
		exit 1
	fi
done
grep -q "unclosed quote" "$SCRATCH/err"

printf '2\n' >"$dir/round.txt"
sh "$REPO_ROOT/scripts/init-state.sh" "$data" "Paxton-Meny/widgets#7" >/dev/null
grep -qx '2' "$dir/round.txt"

if sh "$REPO_ROOT/scripts/init-state.sh" "$data" "Paxton-Meny/widgets#nope" 2>"$SCRATCH/err"; then
	echo "expected failure on a bad number" >&2
	exit 1
fi
grep -q "no pull request number" "$SCRATCH/err"

if sh "$REPO_ROOT/scripts/init-state.sh" "$data" "not a ref" 2>"$SCRATCH/err"; then
	echo "expected failure on a bad ref" >&2
	exit 1
fi

printf 'author Paxton-Meny\nhead_branch feat-thing\nbase_branch main\nhead_sha abc123\nurl u\nstate MERGED\n' >"$stub/pr-view"
if sh "$REPO_ROOT/scripts/init-state.sh" "$data" "Paxton-Meny/widgets#7" 2>"$SCRATCH/err"; then
	echo "expected failure on a merged pull request" >&2
	exit 1
fi
grep -q "MERGED, not open" "$SCRATCH/err"

other="$SCRATCH/other-clone"
git init -q "$other"
git -C "$other" remote add origin git@github.com:Paxton-Meny/other-widgets.git
cd "$other"
if sh "$REPO_ROOT/scripts/init-state.sh" "$data" "Paxton-Meny/widgets#7" 2>"$SCRATCH/err"; then
	echo "expected refusal from a clone of the wrong repository" >&2
	exit 1
fi
grep -q "origin of .* is .*not Paxton-Meny/widgets" "$SCRATCH/err"
[ ! -d "$data/state/Paxton-Meny__widgets__7.wrong" ]

plain="$SCRATCH/plain"
mkdir -p "$plain"
cd "$plain"
if sh "$REPO_ROOT/scripts/init-state.sh" "$data" "Paxton-Meny/widgets#7" 2>"$SCRATCH/err"; then
	echo "expected refusal outside any clone" >&2
	exit 1
fi
grep -q "run from inside a clone" "$SCRATCH/err"

# The data root is private whatever the umask, fresh or already there.
cd "$clone"
printf 'author Paxton-Meny\nhead_branch feat-thing\nbase_branch main\nhead_sha abc123\nurl u\nstate OPEN\n' >"$stub/pr-view"
for fresh in "$SCRATCH/private-new" "$SCRATCH/private-loose"; do
	[ "$fresh" = "$SCRATCH/private-new" ] || { mkdir -p "$fresh" && chmod 775 "$fresh"; }
	(umask 002 && sh "$REPO_ROOT/scripts/init-state.sh" "$fresh" "Paxton-Meny/widgets#7" >/dev/null)
	[ "$(ls -ld "$fresh" | cut -c1-10)" = drwx------ ] || {
		echo "data root is not private: $(ls -ld "$fresh")" >&2
		exit 1
	}
done
