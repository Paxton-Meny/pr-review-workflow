#!/bin/sh
# Run every quality gate for this repository.
# Usage: sh scripts/gate.sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
status=0

[ -f "$root/scripts/gate.env" ] && . "$root/scripts/gate.env"
cli=${CLAUDE_CLI:-claude}

if [ -f "$root/.claude-plugin/plugin.json" ]; then
	if command -v "$cli" >/dev/null 2>&1; then
		ship=$(mktemp -d)
		trap 'rm -rf "$ship"' EXIT
		git -C "$root" checkout-index -a --prefix="$ship/"
		"$cli" plugin validate --strict "$ship" || status=1
		rm -rf "$ship"
		trap - EXIT
	else
		echo "gate: claude CLI not found, cannot validate the plugin" >&2
		status=1
	fi
fi

sh "$root/tests/run.sh" || status=1

if [ -f "$root/scripts/gate.local.sh" ]; then
	sh "$root/scripts/gate.local.sh" "$root" || status=1
fi

[ "$status" -eq 0 ] && echo "gate: all checks passed"
exit "$status"
