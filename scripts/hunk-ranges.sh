#!/bin/sh
# List the hunks of a unified diff as line ranges.
# Usage: sh scripts/hunk-ranges.sh [<diff>]   (stdin when no file is given)
# Prints one line per hunk, tab-separated: path, old start, old end,
# new start, new end, and the enclosing function the hunk header names
# (empty when it names none). The ranges cover the changed lines only,
# never the context lines around them. A pure insertion has an empty
# old range, written as start and end both at the old line it inserts
# before; a pure deletion likewise on the new side. The path is the new
# one, or the old one for a deleted file, with the a/ and b/ prefixes
# dropped.
set -eu

[ $# -le 1 ] || {
	echo "usage: hunk-ranges.sh [<diff>]" >&2
	exit 1
}
if [ $# -eq 1 ]; then
	[ -f "$1" ] || {
		echo "hunk-ranges: no such file: $1" >&2
		exit 1
	}
	exec <"$1"
fi

awk '
function start(spec) { sub(/^[-+]/, "", spec); sub(/,.*/, "", spec); return spec + 0 }
function flush() {
	if (!inhunk) return
	if (olo == "") { olo = oldl; ohi = oldl }
	if (nlo == "") { nlo = newl; nhi = newl }
	printf "%s\t%d\t%d\t%d\t%d\t%s\n", path, olo, ohi, nlo, nhi, fn
	inhunk = 0
}
/^diff --git / { flush(); path = ""; oldpath = ""; next }
/^--- / { flush(); p = $0; sub(/^--- /, "", p); sub(/^a\//, "", p); oldpath = p; next }
/^\+\+\+ / {
	p = $0; sub(/^\+\+\+ /, "", p); sub(/^b\//, "", p)
	path = (p == "/dev/null") ? oldpath : p
	next
}
/^@@ / {
	flush()
	if (path == "") next
	oldl = start($2); newl = start($3)
	olo = ""; ohi = ""; nlo = ""; nhi = ""
	fn = $0
	sub(/^@@ [^@]*@@ ?/, "", fn)
	sub(/[ \t]+$/, "", fn)
	inhunk = 1
	next
}
!inhunk { next }
/^\\/ { next }
/^\+/ { if (nlo == "") nlo = newl; nhi = newl; if (olo == "") { olo = oldl; ohi = oldl }; newl++; next }
/^-/ { if (olo == "") olo = oldl; ohi = oldl; if (nlo == "") { nlo = newl; nhi = newl }; oldl++; next }
{ oldl++; newl++ }
END { flush() }
'
