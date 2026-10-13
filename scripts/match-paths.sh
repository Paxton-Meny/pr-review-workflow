#!/bin/sh
# Print the paths on stdin that match a resolved path-glob setting.
# Usage: sh scripts/match-paths.sh <state-dir> <setting-key> <paths
set -eu

dir=${1:?usage: match-paths.sh <state-dir> <setting-key>}
key=${2:?usage: match-paths.sh <state-dir> <setting-key>}
case "$key" in
sensitive_paths | migration_paths) ;;
*)
	echo "match-paths: not a path setting: $key" >&2
	exit 1
	;;
esac
globs=$(sh "$(dirname "$0")/setting.sh" "$dir" "$key")

set -f
while IFS= read -r path; do
	[ -n "$path" ] || continue
	for glob in $globs; do
		case "$path" in
		$glob)
			printf '%s\n' "$path"
			break
			;;
		esac
	done
done
