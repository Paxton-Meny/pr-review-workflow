#!/bin/sh
# phase-figures: the six phase figures are current, sound, and referenced
# by the site and the README. The generator needs Python 3; without it the
# check is skipped with a line, so the gate does not depend on Python.
set -eu

figures='phase-stage.svg phase-review.svg phase-post.svg phase-fix.svg phase-land.svg phase-merge.svg'
for f in $figures; do
	[ -f "$REPO_ROOT/docs/assets/$f" ] || {
		echo "missing figure: docs/assets/$f" >&2
		exit 1
	}
	grep -q "assets/$f" "$REPO_ROOT/docs/index.html" || {
		echo "docs/index.html does not show $f" >&2
		exit 1
	}
	grep -q "docs/assets/$f" "$REPO_ROOT/README.md" || {
		echo "README.md does not show $f" >&2
		exit 1
	}
	grep -q 'prefers-reduced-motion' "$REPO_ROOT/docs/assets/$f"
	grep -q '<title id=' "$REPO_ROOT/docs/assets/$f"
done

if command -v python3 >/dev/null 2>&1; then
	python3 "$REPO_ROOT/docs/tools/phase-figures.py" --check | grep -qx 'phase-figures: 6 figures current and sound'
else
	echo "phase-figures: python3 not found, generator check skipped"
fi
