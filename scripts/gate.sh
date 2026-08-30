#!/bin/sh
# Run every quality gate for this repository.
# Usage: sh scripts/gate.sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
status=0

if [ -f "$root/.claude-plugin/plugin.json" ]; then
	if command -v claude >/dev/null 2>&1; then
		claude plugin validate --strict "$root" || status=1
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
