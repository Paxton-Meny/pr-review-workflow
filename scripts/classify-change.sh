#!/bin/sh
# Classify the fetched change by file kind and size for model routing.
# Writes class.txt (the summary line) and files-kind.txt (one line per
# file: number, path, class, changed lines) under pr-context/.
# Usage: sh scripts/classify-change.sh <state-dir>
#        sh scripts/classify-change.sh --classify < paths
# --classify reads one path per line and prints "<class>\t<path>", the
# same classes the diff mode uses, so other scripts share this one home.
set -eu

class_of() {
	case "$1" in
	*/test/* | test/* | */tests/* | tests/* | */__tests__/* | __tests__/* | */spec/* | spec/*)
		class=tests
		return
		;;
	esac
	base=${1##*/}
	case "$base" in
	test_*.* | *_test.* | *.test.* | *.spec.* | *_spec.* | conftest.py) class=tests ;;
	requirements*.txt | constraints*.txt) class=config ;;
	*.md | *.rst | *.adoc | *.txt | LICENSE* | NOTICE* | AUTHORS*) class=docs ;;
	*.json | *.yml | *.yaml | *.toml | *.ini | *.cfg | .gitignore | .gitattributes | .editorconfig) class=config ;;
	*) class=code ;;
	esac
}

if [ "${1:-}" = --classify ]; then
	while IFS= read -r path; do
		[ -n "$path" ] || continue
		class_of "$path"
		printf '%s\t%s\n' "$class" "$path"
	done
	exit 0
fi

dir=${1:?usage: classify-change.sh <state-dir>}
ctx="$dir/pr-context"
[ -f "$ctx/diff-index.txt" ] || {
	echo "classify-change: no diff-index.txt in $ctx, run fetch-pr.sh first" >&2
	exit 1
}

docs=0 tests=0 config=0 code=0 files=0 lines=0 code_lines=0
table=$(mktemp "$ctx/.class.XXXXXX")
while IFS='	' read -r num path; do
	[ -n "$path" ] || continue
	files=$((files + 1))
	class_of "$path"
	counts=$(awk -F '\t' -v p="$path" '$1 == p { print $2 + $3; exit }' "$ctx/files.txt" 2>/dev/null || true)
	counts=${counts:-0}
	case $class in
	docs) docs=$((docs + 1)) ;;
	tests) tests=$((tests + 1)) ;;
	config) config=$((config + 1)) ;;
	code)
		code=$((code + 1))
		code_lines=$((code_lines + counts))
		;;
	esac
	lines=$((lines + counts))
	printf '%s\t%s\t%s\t%s\n' "$num" "$path" "$class" "$counts" >>"$table"
done <"$ctx/diff-index.txt"
# One line per file for the router: number, path, class, changed lines.
mv "$table" "$ctx/files-kind.txt"

kind=mixed
[ "$code" -gt 0 ] && kind=code
[ "$files" -eq "$docs" ] && kind=docs-only
[ "$files" -eq "$tests" ] && kind=tests-only
[ "$files" -eq "$config" ] && kind=config-only
[ "$files" -eq 0 ] && kind=empty

line="classify-change: kind $kind files $files lines $lines code_lines $code_lines"
printf '%s\n' "$line" >"$ctx/class.txt"
echo "$line"
