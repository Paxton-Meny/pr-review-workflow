#!/bin/sh
# List criteria growth signals: other-category findings and criteria notes.
# Usage: sh scripts/criteria-signals.sh <state-dir>
set -eu

dir=${1:?usage: criteria-signals.sh <state-dir>}
findings="$dir/findings"
[ -d "$findings" ] || {
	echo "criteria-signals: no findings directory in $dir" >&2
	exit 1
}

others=0
notes=0
for f in "$findings"/F*; do
	[ -f "$f" ] || continue
	id=$(sed -n 's/^id: //p' "$f")
	if [ "$(sed -n 's/^category: //p' "$f")" = "other" ]; then
		echo "other $id: $(sed -n 's/^title: //p' "$f")"
		others=$((others + 1))
	fi
	while IFS= read -r note; do
		[ -n "$note" ] || continue
		echo "note $id: $note"
		notes=$((notes + 1))
	done <<-NOTES
	$(sed -n 's/^Criteria note: //p' "$f")
	NOTES
done

echo "criteria-signals: other $others notes $notes"
