#!/bin/sh
# Print the line naming the plugin, for the first comment a run posts.
# Usage: sh scripts/attribution.sh <state-dir>
# Prints nothing once a review round has posted, so later comments
# never repeat it.
set -eu

dir=${1:?usage: attribution.sh <state-dir>}
[ -f "$dir/round.txt" ] || {
	echo "attribution: no round.txt in $dir, run init-state.sh first" >&2
	exit 1
}
[ "$(cat "$dir/round.txt")" = 0 ] || exit 0

manifest="$(dirname -- "$0")/../.claude-plugin/plugin.json"
name=$(sed -n 's/^  "name": "\(.*\)",$/\1/p' "$manifest")
url=$(sed -n 's/^  "repository": "\(.*\)",$/\1/p' "$manifest")
[ -n "$name" ] && [ -n "$url" ] || {
	echo "attribution: no name or repository in $manifest" >&2
	exit 1
}
printf '<sub>Reviewed with [%s](%s).</sub>\n' "$name" "$url"
