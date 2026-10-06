#!/bin/sh
# Print one resolved setting for a run, after checking the record.
# Usage: sh scripts/setting.sh <state-dir> <key>
# Exit 1 when the run has no resolved settings, the key is unknown, or
# settings.txt no longer matches the hash resolve-settings.sh recorded
# outside the state directory: a changed record is never trusted.
set -eu

dir=${1:?usage: setting.sh <state-dir> <key>}
key=${2:?usage: setting.sh <state-dir> <key>}
file="$dir/settings.txt"
[ -f "$file" ] || {
	echo "setting: no settings.txt in $dir, run resolve-settings.sh first" >&2
	exit 1
}
data_root=$(CDPATH= cd -- "$dir/../.." && pwd)
recorded="$data_root/trust/runs/$(basename "$dir").hash"
[ -f "$recorded" ] && [ "$(git hash-object "$file")" = "$(cat "$recorded")" ] || {
	echo "setting: settings.txt in $dir does not match its recorded hash; resolve again" >&2
	exit 1
}
grep -q "^$key\( \|\$\)" "$file" || {
	echo "setting: unknown setting: $key" >&2
	exit 1
}
sed -n "s/^$key\$//p; s/^$key //p" "$file" | head -n 1
