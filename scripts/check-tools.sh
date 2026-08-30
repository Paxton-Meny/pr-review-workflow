#!/bin/sh
# Prove git and an authenticated GitHub CLI are available.
# Usage: sh scripts/check-tools.sh
set -eu

for tool in git gh; do
	command -v "$tool" >/dev/null 2>&1 || {
		echo "check-tools: $tool not found" >&2
		exit 1
	}
done

gh auth status >/dev/null 2>&1 || {
	echo "check-tools: gh is not authenticated, run gh auth login" >&2
	exit 1
}

echo "check-tools: git and gh ready"
