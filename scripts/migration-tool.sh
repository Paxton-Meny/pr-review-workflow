#!/bin/sh
# Usage: sh scripts/migration-tool.sh <command>
# Exit 3 when the command names migration or database tooling, 0 when it does not, 1 on bad usage.
set -eu

[ $# -ge 1 ] || {
	echo "usage: migration-tool.sh <command>" >&2
	exit 1
}

set -f
prev=''
for word in $*; do
	name=$(printf '%s' "${word##*/}" | tr 'A-Z' 'a-z')
	name=${name%.exe}
	case "$name" in
	migrate | migrate:* | migration | migration:* | makemigrations | db:* | \
		dotnet-ef | update-database | add-migration | remove-migration | script-migration | scaffold-dbcontext | \
		alembic | flyway | liquibase | sqitch | goose | dbmate | sqlpackage | sqlcmd | roundhouse | \
		psql | mysql | sqlite3 | mongosh)
		exit 3
		;;
	db)
		[ "$prev" != prisma ] || exit 3
		;;
	ef)
		[ "$prev" != dotnet ] || exit 3
		;;
	esac
	prev=$name
done
exit 0
