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
# No answer about the author's permission records it as unknown.
grep -qx 'author_permission unknown' "$dir/meta.txt"
grep -qx 'maintainer_can_modify true' "$dir/meta.txt"
grep -q '^head_repo_url https://github.com/Paxton-Meny/widgets.git$' "$dir/meta.txt"
grep -qx '0' "$dir/round.txt"
! grep -q '^state ' "$dir/meta.txt"
# Each invocation opens in the step journal.
[ "$(cat "$dir/steps.txt")" = invoke ]

printf 'write\n' >"$stub/api-repos_Paxton-Meny_widgets_collaborators_Paxton-Meny_permission"
sh "$REPO_ROOT/scripts/init-state.sh" "$data" "Paxton-Meny/widgets#7" >/dev/null
grep -qx 'author_permission write' "$dir/meta.txt"
printf 'pull\n' >"$stub/api-repos_Paxton-Meny_widgets_collaborators_Paxton-Meny_permission"
sh "$REPO_ROOT/scripts/init-state.sh" "$data" "Paxton-Meny/widgets#7" >/dev/null
grep -qx 'author_permission unknown' "$dir/meta.txt"
rm -f "$stub/api-repos_Paxton-Meny_widgets_collaborators_Paxton-Meny_permission"

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

# Until the ledger holds findings the reviewed head is GitHub's head.
grep -qx 'reviewed_head abc123' "$dir/meta.txt"
# Once findings exist a resume keeps the heads the run last saw, never
# GitHub's, so a push made outside the run waits for checkout-pr.sh and
# commits pushed since stay unreviewed.
mkdir -p "$dir/findings"
printf 'id: F001\nstatus: open\n---\nBody.\n' >"$dir/findings/F001"
sed -i 's/^head_sha .*/head_sha 5ee7/' "$dir/meta.txt"
printf 'prev_head 9e70\narrived_base 9e69\n' >>"$dir/meta.txt"
sed 's/^head_sha abc123$/head_sha def456/' "$stub/pr-view" >"$stub/pr-view.new"
mv "$stub/pr-view.new" "$stub/pr-view"
sh "$REPO_ROOT/scripts/init-state.sh" "$data" "Paxton-Meny/widgets#7" >/dev/null
grep -qx 'head_sha 5ee7' "$dir/meta.txt"
grep -qx 'prev_head 9e70' "$dir/meta.txt"
grep -qx 'arrived_base 9e69' "$dir/meta.txt"
[ "$(grep -c '^head_sha ' "$dir/meta.txt")" -eq 1 ]
grep -qx 'reviewed_head abc123' "$dir/meta.txt"
[ "$(grep -c '^reviewed_head ' "$dir/meta.txt")" -eq 1 ]
# A ledger written before the reviewed_head field with an arrival pending
# falls back to the base of the arrival, not the head it already advanced to.
sed -e '/^reviewed_head /d' "$dir/meta.txt" >"$dir/meta.old"
mv "$dir/meta.old" "$dir/meta.txt"
sh "$REPO_ROOT/scripts/init-state.sh" "$data" "Paxton-Meny/widgets#7" >/dev/null
grep -qx 'reviewed_head 9e69' "$dir/meta.txt"
# Without an arrival it falls back to the head it recorded.
sed -e '/^reviewed_head /d' -e '/^arrived_base /d' -e 's/^head_sha .*/head_sha 0ld0ld/' "$dir/meta.txt" >"$dir/meta.old"
mv "$dir/meta.old" "$dir/meta.txt"
sh "$REPO_ROOT/scripts/init-state.sh" "$data" "Paxton-Meny/widgets#7" >/dev/null
grep -qx 'reviewed_head 0ld0ld' "$dir/meta.txt"
# With no findings every head is GitHub's again.
rm -r "$dir/findings"
sh "$REPO_ROOT/scripts/init-state.sh" "$data" "Paxton-Meny/widgets#7" >/dev/null
grep -qx 'head_sha def456' "$dir/meta.txt"
grep -qx 'reviewed_head def456' "$dir/meta.txt"
if grep -q '^prev_head ' "$dir/meta.txt"; then
	echo "prev_head survived a ledger with no findings" >&2
	exit 1
fi

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
