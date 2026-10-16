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
function count(spec) { sub(/^[-+]/, "", spec); return (index(spec, ",") ? substr(spec, index(spec, ",") + 1) : 1) + 0 }
function added() { if (nlo == "") nlo = newl; nhi = newl; if (olo == "") { olo = oldl; ohi = oldl }; newl++ }
function removed() { if (olo == "") olo = oldl; ohi = oldl; if (nlo == "") { nlo = newl; nhi = newl }; oldl++ }
function flush() {
	if (!inhunk) return
	if (olo == "") { olo = oldl; ohi = oldl }
	if (nlo == "") { nlo = newl; nhi = newl }
	printf "%s\t%d\t%d\t%d\t%d\t%s\n", path, olo, ohi, nlo, nhi, fn
	inhunk = 0
}
/^diff --git / { flush(); path = ""; oldpath = ""; next }
# While the hunk header promises more lines, every line is body, so a
# deleted "-- text" or an added "++ text" is never read as a file header.
(oc > 0 || nc > 0) && /^\\/ { next }
oc > 0 || nc > 0 {
	c = substr($0, 1, 1)
	if (c == "+") { nc--; added() }
	else if (c == "-") { oc--; removed() }
	else { oc--; nc--; oldl++; newl++ }
	next
}
/^--- / { flush(); p = $0; sub(/^--- /, "", p); sub(/^a\//, "", p); oldpath = p; next }
/^\+\+\+ / {
	p = $0; sub(/^\+\+\+ /, "", p); sub(/^b\//, "", p)
	path = (p == "/dev/null") ? oldpath : p
	next
}
/^@@ / {
	flush()
	if (path == "") next
	oldl = start($2); newl = start($3); oc = count($2); nc = count($3)
	olo = ""; ohi = ""; nlo = ""; nhi = ""
	fn = $0
	sub(/^@@ [^@]*@@ ?/, "", fn)
	sub(/[ \t]+$/, "", fn)
	inhunk = 1
	next
}
!inhunk { next }
/^\\/ { next }
/^\+/ { added(); next }
/^-/ { removed(); next }
{ oldl++; newl++ }
END { flush() }
'
