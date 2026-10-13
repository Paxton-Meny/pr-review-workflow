#!/bin/sh
# migration-tool: names migration and database tooling, .NET and SQL
# Server included, and nothing else.
set -eu

tool() { sh "$REPO_ROOT/scripts/migration-tool.sh" "$@"; }
while IFS= read -r cmd; do
	rc=0
	tool "$cmd" || rc=$?
	[ "$rc" -eq 3 ] || {
		echo "expected migration or database tooling: $cmd" >&2
		exit 1
	}
done <<'END'
python manage.py migrate
python manage.py makemigrations --check
alembic upgrade head
npx prisma migrate deploy
npx prisma db push
bundle exec rake db:migrate
knex migrate:latest
dotnet ef database update
dotnet ef migrations add AddEmail
dotnet ef dbcontext scaffold Server=. Microsoft.EntityFrameworkCore.SqlServer
dotnet-ef database update
Update-Database
Add-Migration AddEmail
sqlpackage /Action:Publish /SourceFile:Schema.dacpac
sqlcmd -S . -i deploy.sql
SQLCMD.EXE -S . -i deploy.sql
flyway check
psql -c select
END
while IFS= read -r cmd; do
	tool "$cmd" || {
		echo "not migration or database tooling: $cmd" >&2
		exit 1
	}
done <<'END'
dotnet test
dotnet test src/App.sln
dotnet build ef
pytest tests/test_models.py
npx prisma generate
npm test
make check
END
if tool 2>/dev/null; then
	echo "expected refusal without a command" >&2
	exit 1
fi
