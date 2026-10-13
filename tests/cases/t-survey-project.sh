#!/bin/sh
# survey-project: facts read from the clone alone, candidates best first
# and never duplicated, test directories skipped, ignored root markdown
# found from the main worktree, and the conventions block from the base.
set -eu

mkdir -p "$SCRATCH/Paxton-Meny"
remote="$SCRATCH/Paxton-Meny/widgets.git"
git init --quiet --bare "$remote"
clone="$SCRATCH/clone"
git clone --quiet "$remote" "$clone" 2>/dev/null
git -C "$clone" config user.name tester
git -C "$clone" config user.email tester@example.invalid
mkdir -p "$clone/src/auth" "$clone/src/payments/stripe" "$clone/tests/auth" "$clone/.github/workflows" "$clone/.claude"
printf 'check:\n\tnpm test\n' >"$clone/Makefile"
cat >"$clone/package.json" <<'JSON'
{
  "name": "widgets",
  "scripts": {
    "test": "vitest run",
    "lint": "eslint ."
  },
  "devDependencies": {
    "vitest": "^2.0.0",
    "@playwright/test": "^1.40.0"
  }
}
JSON
printf 'name: ci\njobs:\n  test:\n    steps:\n      - run: npm test\n      - run: npm run lint\n      - run: echo done | tee log\n' >"$clone/.github/workflows/ci.yml"
printf 'x\n' >"$clone/src/auth/login.js"
printf 'x\n' >"$clone/src/payments/stripe/charge.js"
printf 'x\n' >"$clone/tests/auth/login.test.js"
printf 'Notes.\n<!-- review-conventions:begin -->\ntests live in tests/\nrun them with npm test\n<!-- review-conventions:end -->\n' >"$clone/CLAUDE.md"
printf 'double_review always\n' >"$clone/.claude/pr-review-workflow.conf"
git -C "$clone" add -A
git -C "$clone" commit --quiet -m first
git -C "$clone" -c user.email=other@example.invalid commit --quiet --allow-empty -m second
git -C "$clone" push --quiet origin HEAD:main
git -C "$clone" update-ref refs/remotes/origin/main HEAD
git -C "$clone" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
printf 'RULES.md\nNOTES.md\n' >>"$clone/.git/info/exclude"
printf 'rules\n' >"$clone/RULES.md"
printf 'notes\n' >"$clone/NOTES.md"
printf 'cost_posture economy\n' >"$clone/.claude/pr-review-workflow.local.conf"

cd "$clone/src"
out=$(sh "$REPO_ROOT/scripts/survey-project.sh" facts)
printf '%s\n' "$out" | grep -qx "survey: clone $clone"
printf '%s\n' "$out" | grep -qx 'survey: origin Paxton-Meny/widgets base main'
printf '%s\n' "$out" | grep -qx 'survey: authors 2 in the last year, codeowners no'
printf '%s\n' "$out" | grep -qx 'survey: project file tracked, local file present'
printf '%s\n' "$out" | grep -qx 'survey: audience team suggested'
printf '%s\n' "$out" | grep -qx 'survey: existing .claude/pr-review-workflow.conf: double_review always'
printf '%s\n' "$out" | grep -qx 'survey: existing .claude/pr-review-workflow.local.conf: cost_posture economy'
printf '%s\n' "$out" | grep -qx 'survey: conventions block 2 lines'
# Best first: the Makefile target, then the manifest's script. The CI run
# line duplicating it is not repeated; the lint line and the piped line
# never appear.
[ "$(printf '%s\n' "$out" | grep -c '^survey: check ')" -eq 2 ]
printf '%s\n' "$out" | grep -qx 'survey: check makefile make check'
printf '%s\n' "$out" | grep -qx 'survey: check package.json npm test'
printf '%s\n' "$out" | grep '^survey: check ' | head -n 1 | grep -q 'make check'
! printf '%s\n' "$out" | grep -q 'npm run lint'
! printf '%s\n' "$out" | grep -q 'tee log'
printf '%s\n' "$out" | grep -qx 'survey: prefix package.json npx vitest'
printf '%s\n' "$out" | grep -qx 'survey: prefix package.json npx playwright test'
# Sensitive directories, deepest match, test trees skipped.
printf '%s\n' "$out" | grep -qxF 'survey: sensitive src/auth/**'
printf '%s\n' "$out" | grep -qxF 'survey: sensitive src/payments/**'
! printf '%s\n' "$out" | grep -q 'tests/auth'
printf '%s\n' "$out" | grep -qx 'survey: standards RULES.md'
! printf '%s\n' "$out" | grep -q 'survey: standards CLAUDE.md'
! printf '%s\n' "$out" | grep -q 'survey: standards NOTES.md'
printf '%s\n' "$out" | grep -qx 'survey: found check 2 prefix 2 sensitive 2 standards 1'

# The conventions mode prints the block alone, from the base branch.
printf 'changed locally\n' >"$clone/CLAUDE.md"
out=$(sh "$REPO_ROOT/scripts/survey-project.sh" conventions)
[ "$out" = "$(printf 'tests live in tests/\nrun them with npm test')" ]

# A linked worktree finds the ignored rules file through the main one.
git -C "$clone" worktree add --quiet --detach "$SCRATCH/linked" 2>/dev/null
cd "$SCRATCH/linked"
sh "$REPO_ROOT/scripts/survey-project.sh" facts | grep -qx 'survey: standards RULES.md'

# One author, no settings file, nothing detected: personal, and zero
# counts. With no origin/HEAD recorded, origin/main stands in as the base.
mkdir -p "$SCRATCH/Paxton-Meny"
solo_remote="$SCRATCH/Paxton-Meny/solo.git"
git init --quiet --bare "$solo_remote"
solo="$SCRATCH/solo"
git clone --quiet "$solo_remote" "$solo" 2>/dev/null
git -C "$solo" config user.name tester
git -C "$solo" config user.email tester@example.invalid
printf 'readme\n' >"$solo/README.md"
git -C "$solo" add -A
git -C "$solo" commit --quiet -m root
git -C "$solo" push --quiet origin HEAD:main
cd "$solo"
out=$(sh "$REPO_ROOT/scripts/survey-project.sh" facts)
printf '%s\n' "$out" | grep -qx 'survey: origin Paxton-Meny/solo base main'
printf '%s\n' "$out" | grep -qx 'survey: audience personal suggested'
printf '%s\n' "$out" | grep -qx 'survey: project file absent, local file absent'
printf '%s\n' "$out" | grep -qx 'survey: conventions block absent'
printf '%s\n' "$out" | grep -qx 'survey: found check 0 prefix 0 sensitive 0 standards 0'
if sh "$REPO_ROOT/scripts/survey-project.sh" conventions 2>/dev/null; then
	echo "conventions must fail without a block" >&2
	exit 1
fi
# With no remote-tracking branch at all, the base is unknown, not an error.
git -C "$solo" update-ref -d refs/remotes/origin/main
out=$(sh "$REPO_ROOT/scripts/survey-project.sh" facts)
printf '%s\n' "$out" | grep -qx 'survey: origin Paxton-Meny/solo base unknown'
printf '%s\n' "$out" | grep -qx 'survey: conventions block unknown, no base branch fetched'

# Outside a clone, or with a bad mode, it refuses before doing anything.
cd "$SCRATCH"
if sh "$REPO_ROOT/scripts/survey-project.sh" facts 2>/dev/null; then
	echo "expected refusal outside a clone" >&2
	exit 1
fi
cd "$solo"
if sh "$REPO_ROOT/scripts/survey-project.sh" everything 2>/dev/null; then
	echo "expected refusal of an unknown mode" >&2
	exit 1
fi

# lists hands the directory name lists to other scripts.
sh "$REPO_ROOT/scripts/survey-project.sh" lists skip | grep -q '^test|tests|'
printf 'payments\n' | grep -qxE "$(sh "$REPO_ROOT/scripts/survey-project.sh" lists sensitive-names)"
if sh "$REPO_ROOT/scripts/survey-project.sh" lists rulebook 2>/dev/null; then
	echo "expected refusal of an unknown list" >&2
	exit 1
fi
