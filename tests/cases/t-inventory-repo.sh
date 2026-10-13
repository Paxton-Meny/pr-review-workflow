#!/bin/sh
# inventory-repo: tiers from code lines and files, nested rules files found,
# docs first and code partitions balanced, sensitive directories by
# content, secrets as locations only, a replay when HEAD has not moved.
set -eu

mkdir -p "$SCRATCH/Paxton-Meny"
remote="$SCRATCH/Paxton-Meny/widgets.git"
git init --quiet --bare "$remote"
clone="$SCRATCH/clone"
git clone --quiet "$remote" "$clone" 2>/dev/null
git -C "$clone" config user.name tester
git -C "$clone" config user.email tester@example.invalid
data="$SCRATCH/data"
inventory() { sh "$REPO_ROOT/scripts/inventory-repo.sh" "$@"; }

# A tiny repository: small tier, nothing to read.
printf 'readme\n' >"$clone/README.md"
mkdir -p "$clone/src"
printf 'print(1)\n' >"$clone/src/app.py"
git -C "$clone" add -A
git -C "$clone" commit --quiet -m root
git -C "$clone" push --quiet origin HEAD:main
cd "$clone/src"
out=$(inventory "$data")
printf '%s\n' "$out" | grep -qx "inventory: dir $data/survey/Paxton-Meny__widgets"
printf '%s\n' "$out" | grep -qx 'inventory: files 2 code 1 tests 0 docs 1 config 0 skipped 0'
printf '%s\n' "$out" | grep -qx 'inventory: tier small'
printf '%s\n' "$out" | grep -qx 'inventory: plan partitions 0 max 0'
printf '%s\n' "$out" | grep -qx 'inventory: estimate read_lines 0 tokens ~0 agents 0'
printf '%s\n' "$out" | grep -qx 'inventory: docs 1 files 1 lines, readme yes, contributing no, docs-dir none'
[ ! -s "$data/survey/Paxton-Meny__widgets/partitions.txt" ]
[ ! -e "$data/state" ]

# A medium repository: twelve equal directories, nested rules files, a
# sensitive directory, a planted key, a docs directory, a vendored tree.
cd "$clone"
for d in core api web cli db cache queue mail auth search export import; do
	mkdir -p "src/$d"
	for n in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
		awk -v n="$n" 'BEGIN { for (i = 1; i <= 60; i++) printf "def f%d_%d():\n", n, i }' >"src/$d/m$n.py"
	done
done
for n in 1 2 3; do printf 'token = jwt.decode(x)\nhmac.new(k)\n' >>"src/auth/m$n.py"; done
mkdir -p tests/auth docs vendor/lib pkg/a .github
printf 'jwt.decode(x)\n' >tests/auth/test_login.py
printf 'x = 1\n' >vendor/lib/big.py
printf 'Guide.\n' >docs/guide.md
printf 'Contribute.\n' >CONTRIBUTING.md
printf 'Notes.\n<!-- review-conventions:begin -->\ntests live in tests/\n<!-- review-conventions:end -->\n' >CLAUDE.md
printf 'Package rules.\n' >pkg/a/CLAUDE.md
printf 'Agent notes.\n' >pkg/a/AGENTS.md
printf 'api_key = "0123456789abcdef"\n' >src/core/settings.py
printf '* @Paxton-Meny\nsrc/auth/ @Paxton-Meny @other_owner\n' >.github/CODEOWNERS
printf 'binary\n' >logo.png
git add -A
git -c user.email=other@example.invalid commit --quiet -m medium
git push --quiet origin HEAD:main
out=$(inventory "$data")
printf '%s\n' "$out" | grep -qx 'inventory: tier medium'
printf '%s\n' "$out" | grep -q '^inventory: head [0-9a-f]* cached no$'
printf '%s\n' "$out" | grep -q '^inventory: files 191 code 184 tests 1 docs 6 config 0 skipped 1$'
printf '%s\n' "$out" | grep -qx 'inventory: languages py 10808'
printf '%s\n' "$out" | grep -qx 'inventory: rules CLAUDE.md 4 block yes'
printf '%s\n' "$out" | grep -qx 'inventory: rules pkg/a/AGENTS.md 1 block no'
printf '%s\n' "$out" | grep -qx 'inventory: rules pkg/a/CLAUDE.md 1 block no'
printf '%s\n' "$out" | grep -q '^inventory: docs 6 files .* readme yes, contributing yes, docs-dir docs$'
printf '%s\n' "$out" | grep -qx 'inventory: codeowners .github/CODEOWNERS rules 2 owners 3'
printf '%s\n' "$out" | grep -qx 'inventory: sensitive-dir src/auth hits 3 of 15 files'
[ "$(printf '%s\n' "$out" | grep -c '^inventory: sensitive-dir ')" -eq 1 ]
printf '%s\n' "$out" | grep -qx 'inventory: secret-location src/core/settings.py:1'
! printf '%s\n' "$out" | grep -q '0123456789abcdef'
printf '%s\n' "$out" | grep -qx 'inventory: churn commits 2 authors 2 since 1 year'
printf '%s\n' "$out" | grep -qx 'inventory: plan partitions 4 max 4'
printf '%s\n' "$out" | grep -q '^inventory: partition 1 lines [0-9]* files 6 docs 6 sensitive no$'
[ "$(printf '%s\n' "$out" | grep -c '^inventory: partition ')" -eq 4 ]
printf '%s\n' "$out" | grep -q '^inventory: estimate read_lines [0-9]* tokens ~[0-9]* agents 4$'
# The three code partitions carry four directories each and balance within 1.5x.
printf '%s\n' "$out" | sed -n 's/^inventory: partition [234] lines \([0-9]*\) .*/\1/p' | sort -n >"$SCRATCH/sizes"
[ "$(wc -l <"$SCRATCH/sizes" | tr -d ' ')" -eq 3 ]
[ $(($(tail -n 1 "$SCRATCH/sizes") * 2)) -le $(($(head -n 1 "$SCRATCH/sizes") * 3)) ]
survey="$data/survey/Paxton-Meny__widgets"
grep -qx 'doc README.md 1' "$survey/partitions/1.txt"
grep -qx 'doc pkg/a/CLAUDE.md 1' "$survey/partitions/1.txt"
grep -qx 'doc docs/guide.md 1' "$survey/partitions/1.txt"
head -n 1 "$survey/partitions/1.txt" | grep -qx "root $clone"
grep -q '^partition 2$' "$survey/partitions/2.txt"
grep -q '^code src/' "$survey/partitions/2.txt"
grep -q '^dir src/' "$survey/partitions/2.txt"
grep -l '^test tests/auth/test_login.py 1$' "$survey"/partitions/*.txt >/dev/null
grep -l '^sensitive yes$' "$survey"/partitions/*.txt >/dev/null
[ "$(grep -c '^partition ' "$survey/partitions.txt")" -eq 4 ]
grep -q 'units docs$' "$survey/partitions.txt"
! grep -q 'vendor' "$survey/files.txt"
grep -q '^code	0	logo.png$' "$survey/files.txt"
[ "$(cat "$survey/head.txt")" = "$(git rev-parse HEAD)" ]
[ ! -e "$survey/.inventory."* ] 2>/dev/null || [ -z "$(ls -d "$survey"/.inventory.* 2>/dev/null)" ]

# A second run on the same HEAD replays without rescanning.
again=$(inventory "$data")
printf '%s\n' "$again" | grep -q '^inventory: head [0-9a-f]* cached yes$'
printf '%s\n' "$again" | grep -qx 'inventory: records 0 of 4'
[ "$(printf '%s\n' "$again" | grep -vc 'cached yes\|^inventory: records ')" -eq "$(printf '%s\n' "$out" | grep -vc 'cached no')" ]
mkdir -p "$survey/records"
printf '## layout\n' >"$survey/records/1.txt"
inventory "$data" | grep -qx 'inventory: records 1 of 4'

# A partition cap below the tier's shrinks the plan.
git commit --quiet --allow-empty -m move
out=$(inventory "$data" 2)
printf '%s\n' "$out" | grep -qx 'inventory: plan partitions 2 max 2'

# Refusals: a bad cap, no clone.
if inventory "$data" 0 2>/dev/null; then
	echo "expected refusal of a zero cap" >&2
	exit 1
fi
cd "$SCRATCH"
if inventory "$data" 2>/dev/null; then
	echo "expected refusal outside a clone" >&2
	exit 1
fi
