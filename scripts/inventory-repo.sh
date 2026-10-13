#!/bin/sh
# Inventory the clone this runs in and plan how much of it a model should
# read, so setup can size its reading to the repository.
# Usage: sh scripts/inventory-repo.sh <data-root> [max-partitions]
#
# Writes <data-root>/survey/<owner>__<repo>/: meta.txt, head.txt,
# files.txt (class, lines, path for every tracked file outside the
# skipped directories), rules.txt (every CLAUDE.md and AGENTS.md at any
# depth, with whether it holds a review-conventions block), docs.txt,
# sensitive.txt (directories whose code matches the sensitive probe),
# secrets.txt (locations only), partitions.txt and partitions/<id>.txt
# (the reading plan), and inventory.txt (every line printed, replayed
# when HEAD has not moved, then one line counting the records already
# filed against the plan). Vendored, generated, and example trees are
# skipped; test trees are not, since their classes are counted. Prints "inventory:" lines: the size tier,
# the rules and docs found, sensitive directories, churn, one line per
# partition, and an upfront estimate of the reading. Partition 1 is
# always the docs; the rest pack the largest directories first into
# the lightest bin, each listing at most a budget of files and lines,
# with one test file per directory first, then code ordered by churn on
# a huge repository and by size otherwise. Nothing
# is fetched, and nothing is written outside the survey directory.
set -eu

data_root=${1:?usage: inventory-repo.sh <data-root> [max-partitions]}
max_arg=${2:-}
case "$max_arg" in
'' | [1-9] | [1-9][0-9]) ;;
*)
	echo "inventory-repo: max-partitions must be a number from 1 to 99: $max_arg" >&2
	exit 1
	;;
esac
clone=$(git rev-parse --show-toplevel 2>/dev/null) || {
	echo "inventory-repo: run it from inside a clone" >&2
	exit 1
}
url=$(git -C "$clone" remote get-url origin 2>/dev/null) || {
	echo "inventory-repo: the clone at $clone has no origin remote" >&2
	exit 1
}
trimmed=${url%/}
trimmed=${trimmed%.git}
repo=${trimmed##*/}
rest=${trimmed%/*}
owner=${rest##*[:/]}
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
base=$(sh "$here/origin-base.sh" "$clone" 2>/dev/null) || base=''
head=$(git -C "$clone" rev-parse HEAD 2>/dev/null) || {
	echo "inventory-repo: the clone has no commits" >&2
	exit 1
}

SMALL_CODE_LINES=8000 SMALL_FILES=150
MEDIUM_CODE_LINES=60000 MEDIUM_FILES=1500
LARGE_CODE_LINES=400000 LARGE_FILES=10000
MEDIUM_PARTITIONS=4 LARGE_PARTITIONS=8 HUGE_PARTITIONS=16
DOC_BUDGET_LINES=6000
FILE_BUDGET=40
LINE_BUDGET=12000
MAX_TEXT_BYTES=262144
TOKENS_PER_LINE=10
TOKENS_PER_AGENT=8000
SENSITIVE_MIN_HITS=3
SENSITIVE_MIN_RATIO=0.2
MAX_SENSITIVE_DIRS=8
MAX_SECRET_LOCATIONS=20
BINARY_EXT='png|jpe?g|gif|ico|bmp|webp|svgz|pdf|zip|gz|tgz|bz2|xz|7z|tar|jar|war|woff2?|ttf|otf|eot|mp[34]|wav|ogg|mov|avi|wasm|so|dylib|dll|exe|bin|class|pyc|o|a|lockb|db|sqlite'
BEGIN_MARK='<!-- review-conventions:begin -->'

dir="$data_root/survey/${owner}__${repo}"
mkdir -p "$dir"
printf 'owner %s\nrepo %s\nbase %s\nrepo_root %s\n' "$owner" "$repo" "$base" "$clone" >"$dir/meta.txt"
if [ -f "$dir/head.txt" ] && [ "$(cat "$dir/head.txt")" = "$head" ] && [ -f "$dir/inventory.txt" ]; then
	sed "s/^inventory: head $head cached no\$/inventory: head $head cached yes/" "$dir/inventory.txt"
	planned=$(grep -c '^partition ' "$dir/partitions.txt" 2>/dev/null || true)
	recorded=$(ls "$dir/records" 2>/dev/null | grep -c '^[0-9][0-9]*\.txt$' || true)
	echo "inventory: records $recorded of $planned"
	exit 0
fi

work=$(mktemp -d "$dir/.inventory.XXXXXX")
trap 'rm -rf "$work"' EXIT
cd "$clone"
skip_re=$(sh "$here/survey-project.sh" lists skip | sed 's/^test|tests|spec|specs|__tests__|//; s/|docs|doc|/|/')
sensitive_re=$(sh "$here/probe-diff.sh" --pattern sensitive)
secrets_re=$(sh "$here/probe-diff.sh" --pattern secrets)

git ls-tree -r -l HEAD | tr -d '\r' | awk -F '\t' -v skip="(^|/)($skip_re)/" -v binary="\\.($BINARY_EXT)\$" -v max="$MAX_TEXT_BYTES" '
{
	path = $2
	split($1, m, " ")
	if (m[1] == "120000") next
	if (path ~ skip) { print "skipped\t" path > "/dev/stderr"; next }
	text = (tolower(path) !~ binary && m[4] + 0 <= max) ? "text" : "opaque"
	print text "\t" path
}' >"$work/paths" 2>"$work/skipped"
skipped=$(grep -c . "$work/skipped" || true)
cut -f2 "$work/paths" | sh "$here/classify-change.sh" --classify >"$work/classes"
awk -F '\t' '$1 == "text" { print $2 }' "$work/paths" | tr '\n' '\0' | xargs -0 wc -l 2>/dev/null |
	sed -n 's/^[[:space:]]*\([0-9][0-9]*\) \(.*\)$/\1\t\2/p' | grep -v '	total$' >"$work/wc" || true
awk -F '\t' '
FILENAME == ARGV[1] { lines[$2] = $1; next }
{ print $1 "\t" (($2 in lines) ? lines[$2] : 0) "\t" $2 }
' "$work/wc" "$work/classes" | sort -t '	' -k3 >"$work/files.txt"

awk -F '\t' -v langs_file="$work/langs" '
{ n[$1]++; l[$1] += $2; files++; lines += $2 }
$1 == "code" && $2 > 0 { ext = $3; sub(/.*\//, "", ext); if (index(ext, ".")) { sub(/.*\./, "", ext); el[tolower(ext)] += $2 } }
END {
	printf "%d %d %d %d %d %d %d\n", files, n["code"], n["tests"], n["docs"], n["config"], lines, l["code"]
	for (e in el) printf "%d %s\n", el[e], e > langs_file
	close(langs_file)
}' "$work/files.txt" >"$work/counts"
: >>"$work/langs"
read -r files code tests docs config lines code_lines <"$work/counts"
langs=$(cat "$work/langs")
languages=$(printf '%s' "$langs" | sort -rn | head -n 6 | awk '{ printf "%s%s %d", (NR > 1 ? " " : ""), $2, $1 }')

if [ "$code_lines" -lt "$SMALL_CODE_LINES" ] && [ "$files" -lt "$SMALL_FILES" ]; then
	tier=small cap=0
elif [ "$code_lines" -lt "$MEDIUM_CODE_LINES" ] && [ "$files" -lt "$MEDIUM_FILES" ]; then
	tier=medium cap=$MEDIUM_PARTITIONS
elif [ "$code_lines" -lt "$LARGE_CODE_LINES" ] && [ "$files" -lt "$LARGE_FILES" ]; then
	tier=large cap=$LARGE_PARTITIONS
else
	tier=huge cap=$HUGE_PARTITIONS
fi
[ -n "$max_arg" ] && [ "$max_arg" -lt "$cap" ] && cap=$max_arg

out="$work/inventory.txt"
say() { printf '%s\n' "$*" | tee -a "$out"; }
say "inventory: dir $dir"
say "inventory: head $head cached no"
say "inventory: files $files code $code tests $tests docs $docs config $config skipped $skipped"
say "inventory: lines total $lines code $code_lines"
say "inventory: languages ${languages:-none}"
say "inventory: tier $tier"

git ls-tree -r --name-only HEAD | grep -E '(^|/)(CLAUDE|AGENTS)\.md$' | sort >"$work/rule-paths" || true
: >"$work/rules.txt"
while IFS= read -r p; do
	[ -f "$p" ] && [ ! -L "$p" ] || continue
	rl=$(grep -c '' "$p" || true)
	if grep -qF -- "$BEGIN_MARK" "$p"; then block=yes; else block=no; fi
	printf '%s %s block %s\n' "$p" "$rl" "$block" >>"$work/rules.txt"
	say "inventory: rules $p $rl block $block"
done <"$work/rule-paths"

awk -F '\t' '
$1 == "docs" || $3 ~ /(^|\/)docs?\// {
	p = $3; b = p; sub(/.*\//, "", b)
	rank = 3
	if (b ~ /^README/) rank = 1
	else if (b ~ /^CONTRIBUTING/) rank = 2
	print rank "\t" $2 "\t" p
}' "$work/files.txt" | sort -t '	' -k1,1n -k2,2nr | awk -F '\t' '{ print $3 " " $2 }' >"$work/docs.txt"
doc_files=$(grep -c . "$work/docs.txt" || true)
doc_lines=$(awk '{ s += $2 } END { print s + 0 }' "$work/docs.txt")
readme=no
contributing=no
grep -qE '^README' "$work/docs.txt" && readme=yes
grep -qE '^CONTRIBUTING' "$work/docs.txt" && contributing=yes
docs_dir=none
for d in docs doc; do [ -d "$d" ] && docs_dir=$d && break; done
say "inventory: docs $doc_files files $doc_lines lines, readme $readme, contributing $contributing, docs-dir $docs_dir"

codeowners_line='inventory: codeowners none'
for f in CODEOWNERS .github/CODEOWNERS docs/CODEOWNERS; do
	[ -f "$f" ] || continue
	rules=$(grep -cvE '^[[:space:]]*(#|$)' "$f" || true)
	owners=$(grep -vE '^[[:space:]]*(#|$)' "$f" | tr ' \t' '\n\n' | grep -c '^@' || true)
	codeowners_line="inventory: codeowners $f rules $rules owners $owners"
	break
done
say "$codeowners_line"

unit_of() {
	awk -F '/' '{ if (NF == 1) print "."; else if (NF == 2) print $1; else print $1 "/" $2 }'
}
awk -F '\t' '$1 == "code" { print $3 }' "$work/files.txt" >"$work/code-paths"
awk -F '\t' 'FILENAME == ARGV[1] && $1 == "text" { text[$2] = 1; next } ($0 in text)' "$work/paths" "$work/code-paths" |
	tr '\n' '\0' | xargs -0 grep -liE -- "$sensitive_re" 2>/dev/null >"$work/sensitive-files" || true
unit_of <"$work/code-paths" | sort | uniq -c | awk '{ print $2 "\t" $1 }' >"$work/unit-code-files"
unit_of <"$work/sensitive-files" | sort | uniq -c | awk '{ print $2 "\t" $1 }' >"$work/unit-hits"
awk -F '\t' -v min_hits="$SENSITIVE_MIN_HITS" -v min_ratio="$SENSITIVE_MIN_RATIO" '
FILENAME == ARGV[1] { total[$1] = $2; next }
{ if ($2 >= min_hits || ($2 >= 2 && $2 / total[$1] >= min_ratio)) print $2 "\t" $1 "\t" total[$1] }
' "$work/unit-code-files" "$work/unit-hits" | sort -t '	' -k1,1nr -k2,2 | head -n "$MAX_SENSITIVE_DIRS" |
	awk -F '\t' '{ print $2 " " $1 " " $3 }' >"$work/sensitive.txt"
while read -r d hits total; do
	say "inventory: sensitive-dir $d hits $hits of $total files"
done <"$work/sensitive.txt"

awk -F '\t' '$1 == "text" { print $2 }' "$work/paths" | tr '\n' '\0' | xargs -0 grep -nHiE -- "$secrets_re" 2>/dev/null |
	sed -n 's/^\([^:]*:[0-9]*\):.*/\1/p' | head -n "$MAX_SECRET_LOCATIONS" >"$work/secrets.txt" || true
while IFS= read -r loc; do
	say "inventory: secret-location $loc"
done <"$work/secrets.txt"

commits=$(git log --since='1 year ago' --format=%ae 2>/dev/null | grep -c . || true)
authors=$(git log --since='1 year ago' --format=%ae 2>/dev/null | sort -u | grep -c . || true)
say "inventory: churn commits $commits authors $authors since 1 year"
: >"$work/churn"
if [ "$tier" = huge ]; then
	git log --since='1 year ago' --name-only --format= 2>/dev/null | grep . | sort | uniq -c | awk '{ c = $1; $1 = ""; sub(/^ /, ""); print c "\t" $0 }' >"$work/churn" || true
fi

mkdir -p "$work/partitions"
awk -F '\t' -v cap="$cap" -v out="$work/partitions" -v plan="$work/partitions.txt" -v inv="$out" \
	-v root="$clone" -v docbudget="$DOC_BUDGET_LINES" -v filebudget="$FILE_BUDGET" -v linebudget="$LINE_BUDGET" \
	-v tpl="$TOKENS_PER_LINE" -v tpa="$TOKENS_PER_AGENT" \
	-v docs_list="$work/docs.txt" -v rules_list="$work/rules.txt" -v sens_list="$work/sensitive.txt" -v churn_list="$work/churn" '
function unit(p,    n, a) { n = split(p, a, "/"); if (n == 1) return "."; if (n == 2) return a[1]; return a[1] "/" a[2] }
function say(s) { print s; print s >> inv }
BEGIN {
	while ((getline line < docs_list) > 0) { split(line, f, " "); isdoc[f[1]] = 1; docl[f[1]] = f[2]; docorder[++nd] = f[1] }
	while ((getline line < rules_list) > 0) { split(line, f, " "); if (!(f[1] in isdoc)) { isdoc[f[1]] = 1; docl[f[1]] = f[2]; docorder[++nd] = f[1] } }
	while ((getline line < sens_list) > 0) { split(line, f, " "); sens[f[1]] = 1 }
	while ((getline line < churn_list) > 0) { split(line, f, "\t"); churn[f[2]] = f[1] }
}
!($3 in isdoc) {
	u = unit($3)
	ulines[u] += $2; ufiles[u]++
	if ($1 == "code" || $1 == "tests") { n = ++nf[u]; fpath[u, n] = $3; flines[u, n] = $2; fclass[u, n] = $1 }
}
END {
	if (cap == 0) { say("inventory: plan partitions 0 max 0"); say("inventory: estimate read_lines 0 tokens ~0 agents 0"); exit }
	id = 1
	file = out "/" id ".txt"
	printf "root %s\npartition %d\nbudget files %d lines %d\nsensitive no\n", root, id, nd, docbudget > file
	dl = 0; dcount = 0
	for (i = 1; i <= nd; i++) {
		p = docorder[i]
		if (dl >= docbudget) { unread_docs++; continue }
		printf "doc %s %d\n", p, docl[p] > file
		dl += docl[p]; dcount++
	}
	if (unread_docs) printf "more docs %d unread\n", unread_docs > file
	close(file)
	plines[id] = dl; pfiles[id] = dcount; pdocs[id] = dcount; psens[id] = "no"; punits[id] = "docs"
	read_lines = dl
	nu = 0
	for (u in ulines) if (nf[u] > 0) order[++nu] = u
	for (i = 1; i <= nu; i++) for (j = i + 1; j <= nu; j++) if (ulines[order[j]] > ulines[order[i]]) { t = order[i]; order[i] = order[j]; order[j] = t }
	bins = cap - 1
	if (bins < 1) bins = 1
	if (nu < bins) bins = nu
	for (b = 1; b <= bins; b++) bl[b] = 0
	for (i = 1; i <= nu; i++) {
		best = 1
		for (b = 2; b <= bins; b++) if (bl[b] < bl[best]) best = b
		bl[best] += ulines[order[i]]
		bu[best] = bu[best] (bu[best] == "" ? "" : " ") order[i]
	}
	for (b = 1; b <= bins; b++) {
		if (bu[b] == "") continue
		id++
		file = out "/" id ".txt"
		nunits = split(bu[b], units, " ")
		s = "no"
		for (k = 1; k <= nunits; k++) if (units[k] in sens) s = "yes"
		printf "root %s\npartition %d\nbudget files %d lines %d\nsensitive %s\n", root, id, filebudget, linebudget, s > file
		m = 0
		for (k = 1; k <= nunits; k++) {
			u = units[k]
			for (n = 1; n <= nf[u]; n++) { m++; cp[m] = fpath[u, n]; cl[m] = flines[u, n]; cc[m] = fclass[u, n]; cu[m] = u; ck[m] = (cp[m] in churn) ? churn[cp[m]] : 0 }
		}
		for (i = 1; i <= m; i++) for (j = i + 1; j <= m; j++) {
			swap = 0
			if (cc[j] == "tests" && cc[i] != "tests") swap = 1
			else if (cc[j] == cc[i]) {
				if (ck[j] > ck[i]) swap = 1
				else if (ck[j] == ck[i] && cl[j] > cl[i]) swap = 1
			}
			if (swap) { t = cp[i]; cp[i] = cp[j]; cp[j] = t; t = cl[i]; cl[i] = cl[j]; cl[j] = t; t = cc[i]; cc[i] = cc[j]; cc[j] = t; t = cu[i]; cu[i] = cu[j]; cu[j] = t; t = ck[i]; ck[i] = ck[j]; ck[j] = t }
		}
		pl = 0; pf = 0
		delete testseen
		for (i = 1; i <= m; i++) {
			if (pf >= filebudget || pl >= linebudget) break
			if (cc[i] == "tests") { if (cu[i] in testseen) continue; testseen[cu[i]] = 1 }
			printf "%s %s %d\n", (cc[i] == "tests" ? "test" : "code"), cp[i], cl[i] > file
			pl += cl[i]; pf++
		}
		for (k = 1; k <= nunits; k++) printf "dir %s files %d lines %d\n", units[k], ufiles[units[k]], ulines[units[k]] > file
		close(file)
		plines[id] = pl; pfiles[id] = pf; pdocs[id] = 0; psens[id] = s; punits[id] = bu[b]
		read_lines += pl
	}
	for (i = 1; i <= id; i++) {
		say(sprintf("inventory: partition %d lines %d files %d docs %d sensitive %s", i, plines[i], pfiles[i], pdocs[i], psens[i]))
		printf "partition %d lines %d files %d docs %d sensitive %s units %s\n", i, plines[i], pfiles[i], pdocs[i], psens[i], punits[i] > plan
	}
	say(sprintf("inventory: plan partitions %d max %d", id, cap))
	say(sprintf("inventory: estimate read_lines %d tokens ~%d agents %d", read_lines, read_lines * tpl + id * tpa, id))
}' "$work/files.txt"
[ -f "$work/partitions.txt" ] || : >"$work/partitions.txt"

rm -rf "$dir/partitions"
mv "$work/partitions" "$dir/partitions"
for f in files.txt rules.txt docs.txt sensitive.txt secrets.txt partitions.txt inventory.txt; do
	mv "$work/$f" "$dir/$f"
done
printf '%s\n' "$head" >"$dir/head.txt"
