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
! printf '%s\n' "$out" | grep -q '^survey: audience'
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
printf '%s\n' "$out" | grep -qx 'survey: found check 2 prefix 2 sensitive 2 migrations 0 standards 1'

# The conventions mode prints the block alone, from the base branch.
printf 'changed locally\n' >"$clone/CLAUDE.md"
out=$(sh "$REPO_ROOT/scripts/survey-project.sh" conventions)
[ "$out" = "$(printf 'tests live in tests/\nrun them with npm test')" ]

# A linked worktree finds the ignored rules file, and the local settings
# file of your own, through the main one.
git -C "$clone" worktree add --quiet --detach "$SCRATCH/linked" 2>/dev/null
cd "$SCRATCH/linked"
out=$(sh "$REPO_ROOT/scripts/survey-project.sh" facts)
printf '%s\n' "$out" | grep -qx 'survey: standards RULES.md'
printf '%s\n' "$out" | grep -qx 'survey: project file tracked, local file present'
printf '%s\n' "$out" | grep -qx "survey: located .claude/pr-review-workflow.local.conf in the main worktree $clone"
printf '%s\n' "$out" | grep -qx 'survey: existing .claude/pr-review-workflow.local.conf: cost_posture economy'

# One author, no settings file, nothing detected: zero counts. With no origin/HEAD recorded, origin/main stands in as the base.
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
printf '%s\n' "$out" | grep -qx 'survey: project file absent, local file absent'
printf '%s\n' "$out" | grep -qx 'survey: conventions block absent'
printf '%s\n' "$out" | grep -qx 'survey: found check 0 prefix 0 sensitive 0 migrations 0 standards 0'
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

# Migrations are found by reading tracked files: content markers, file
# names, and the configuration that names a location, including the .NET
# and SQL Server layouts. A directory only named like migrations is
# reported apart, migration and database tooling is never offered as a
# check, and a solution below the root yields its dotnet test command.
cd "$solo"
mkdir -p src/App/Data/Migrations db/Schema/dbo/Tables tools/Upgrader/Scripts docs/migration schema/versions .github/workflows
printf 'public partial class AddEmail : Migration\n{\n    protected override void Up(MigrationBuilder migrationBuilder) { }\n}\n' >src/App/Data/Migrations/20261013120000_AddEmail.cs
printf '<Project />\n' >src/App.sln
printf '<Project Sdk="Microsoft.Build.Sql" />\n' >db/Schema/Schema.sqlproj
printf 'CREATE TABLE dbo.Users (Id INT NOT NULL);\n' >db/Schema/dbo/Tables/Users.sql
printf '<Project><ItemGroup><PackageReference Include="dbup-sqlserver" Version="5.0.0" /></ItemGroup></Project>\n' >tools/Upgrader/Upgrader.csproj
printf 'ALTER TABLE dbo.Users ADD Email NVARCHAR(200) NULL;\n' >tools/Upgrader/Scripts/0001_email.sql
printf 'How to upgrade.\n' >docs/migration/guide.md
printf '[alembic]\nscript_location = %%(here)s/schema\n' >alembic.ini
printf 'revision = "ab12"\ndown_revision = None\n' >schema/versions/ab12_init.py
printf 'jobs:\n  db:\n    steps:\n      - run: alembic check\n      - run: flyway check\n' >.github/workflows/db.yml
git add -A
git commit --quiet -m migrations
out=$(sh "$REPO_ROOT/scripts/survey-project.sh" facts)
printf '%s\n' "$out" | grep '^survey: migration' >"$SCRATCH/migrations"
cat >"$SCRATCH/migrations-want" <<'END'
survey: migrations schema/versions alembic
survey: migrations src/App/Data/Migrations ef-core
survey: migrations db/Schema ssdt
survey: migrations tools/Upgrader/Scripts dbup
survey: migration-named docs/migration
END
cmp "$SCRATCH/migrations-want" "$SCRATCH/migrations"
printf '%s\n' "$out" | grep -qx 'survey: skipped ci:db.yml alembic check (migration or database tooling)'
printf '%s\n' "$out" | grep -qx 'survey: skipped ci:db.yml flyway check (migration or database tooling)'
if printf '%s\n' "$out" | grep -E '^survey: (check|prefix) ' | grep -qE 'alembic|flyway'; then
	echo "migration or database tooling must never be offered as a check" >&2
	exit 1
fi
printf '%s\n' "$out" | grep -qx 'survey: check App.sln dotnet test src/App.sln'
printf '%s\n' "$out" | grep -qx 'survey: prefix App.sln dotnet test'
if printf '%s\n' "$out" | grep -q '^survey: sensitive .*[Mm]igration'; then
	echo "migrations have their own setting, not sensitive paths" >&2
	exit 1
fi
printf '%s\n' "$out" | grep -qx 'survey: found check 1 prefix 1 sensitive 0 migrations 4 standards 0'

# Several test projects, one a browser suite: each other project is offered
# on its own, the largest first, and the browser suite prints as skipped,
# since a bare dotnet test would run it too.
mkdir -p App.Test/Planning Wiki.Tests App.UiTests
printf '<Project><ItemGroup><PackageReference Include="Microsoft.NET.Test.Sdk" /></ItemGroup></Project>\n' >App.Test/App.Test.csproj
for n in 1 2 3; do printf 'class T%s {}\n' "$n" >"App.Test/Planning/T$n.cs"; done
printf '<Project><ItemGroup><PackageReference Include="xunit" /></ItemGroup></Project>\n' >Wiki.Tests/Wiki.Tests.csproj
printf '<Project><ItemGroup><PackageReference Include="Microsoft.NET.Test.Sdk" /><PackageReference Include="Microsoft.Playwright" /></ItemGroup></Project>\n' >App.UiTests/App.UiTests.csproj
printf '<Project />\n' >App.sln
git add -A
git commit --quiet -m tests
out=$(sh "$REPO_ROOT/scripts/survey-project.sh" facts)
printf '%s\n' "$out" | grep '^survey: check ' >"$SCRATCH/checks"
printf 'survey: check App.Test.csproj dotnet test App.Test/App.Test.csproj\nsurvey: check Wiki.Tests.csproj dotnet test Wiki.Tests/Wiki.Tests.csproj\n' | cmp - "$SCRATCH/checks"
printf '%s\n' "$out" | grep -qx 'survey: skipped App.UiTests.csproj dotnet test App.UiTests/App.UiTests.csproj (browser suite: it needs the app running)'
printf '%s\n' "$out" | grep -qx 'survey: prefix App.sln dotnet test'

# A browser suite alone offers no check: running it needs the app up.
br_remote="$SCRATCH/Paxton-Meny/browser.git"
git init --quiet --bare "$br_remote"
br="$SCRATCH/browser"
git clone --quiet "$br_remote" "$br" 2>/dev/null
git -C "$br" config user.name tester
git -C "$br" config user.email tester@example.invalid
mkdir -p "$br/App.UiTests"
printf '<Project />\n' >"$br/My App.sln"
printf '<Project><ItemGroup><PackageReference Include="Microsoft.Playwright" /><PackageReference Include="Microsoft.NET.Test.Sdk" /></ItemGroup></Project>\n' >"$br/App.UiTests/App.UiTests.csproj"
git -C "$br" add -A
git -C "$br" commit --quiet -m root
git -C "$br" push --quiet origin HEAD:main
cd "$br"
out=$(sh "$REPO_ROOT/scripts/survey-project.sh" facts)
! printf '%s\n' "$out" | grep -q '^survey: check '
! printf '%s\n' "$out" | grep -q '^survey: prefix '
printf '%s\n' "$out" | grep -qx 'survey: skipped App.UiTests.csproj dotnet test App.UiTests/App.UiTests.csproj (browser suite: it needs the app running)'
# A root solution whose name holds a space is labelled dotnet, so the
# command stays the third word on.
rm -r App.UiTests
git add -A
git commit --quiet -m nobrowser
out=$(sh "$REPO_ROOT/scripts/survey-project.sh" facts)
printf '%s\n' "$out" | grep -qx 'survey: check dotnet dotnet test'

# A file the main worktree tracks is the team's, even from a linked
# worktree on a branch that never had it.
git -C "$br" worktree add --quiet -b old "$SCRATCH/br-old" HEAD 2>/dev/null
mkdir -p "$br/.claude"
printf 'double_review always\n' >"$br/.claude/pr-review-workflow.conf"
git -C "$br" add -A
git -C "$br" commit --quiet -m team
cd "$SCRATCH/br-old"
out=$(sh "$REPO_ROOT/scripts/survey-project.sh" facts)
printf '%s\n' "$out" | grep -qx 'survey: project file tracked, local file absent'
cd "$solo"

# Given the survey directory, facts saves its lines there for the later
# scripts, and refuses a directory inventory never made.
mkdir -p "$SCRATCH/sv"
if sh "$REPO_ROOT/scripts/survey-project.sh" facts "$SCRATCH/sv" 2>/dev/null; then
	echo "expected refusal of a survey directory without meta.txt" >&2
	exit 1
fi
printf 'owner Paxton-Meny\n' >"$SCRATCH/sv/meta.txt"
saved=$(sh "$REPO_ROOT/scripts/survey-project.sh" facts "$SCRATCH/sv")
[ "$saved" = "$(cat "$SCRATCH/sv/survey.txt")" ]
printf '%s\n' "$saved" | grep -q '^survey: found '
[ -z "$(ls -A "$SCRATCH/sv" | grep -v '^meta.txt$' | grep -v '^survey.txt$')" ]
