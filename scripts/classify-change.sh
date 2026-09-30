#!/bin/sh
# Classify the fetched change by file kind and size for model routing.
# Usage: sh scripts/classify-change.sh <state-dir>
set -eu

dir=${1:?usage: classify-change.sh <state-dir>}
ctx="$dir/pr-context"
[ -f "$ctx/diff-index.txt" ] || {
	echo "classify-change: no diff-index.txt in $ctx, run fetch-pr.sh first" >&2
	exit 1
}

class_of() {
	case "$1" in
	*/test/* | test/* | */tests/* | tests/* | */__tests__/* | __tests__/* | */spec/* | spec/*)
		echo tests
		return
		;;
	esac
	base=${1##*/}
	case "$base" in
	test_*.* | *_test.* | *.test.* | *.spec.* | *_spec.* | conftest.py)
		echo tests
		;;
	requirements*.txt | constraints*.txt)
		echo config
		;;
	*.md | *.rst | *.adoc | *.txt | LICENSE* | NOTICE* | AUTHORS*)
		echo docs
		;;
	*.json | *.yml | *.yaml | *.toml | *.ini | *.cfg | .gitignore | .gitattributes | .editorconfig)
		echo config
		;;
	*)
		echo code
		;;
	esac
}

docs=0 tests=0 config=0 code=0 files=0 lines=0
while IFS='	' read -r _num path; do
	[ -n "$path" ] || continue
	files=$((files + 1))
	case $(class_of "$path") in
	docs) docs=$((docs + 1)) ;;
	tests) tests=$((tests + 1)) ;;
	config) config=$((config + 1)) ;;
	code) code=$((code + 1)) ;;
	esac
	counts=$(awk -F '\t' -v p="$path" '$1 == p { print $2 + $3; exit }' "$ctx/files.txt" 2>/dev/null || true)
	lines=$((lines + ${counts:-0}))
done <"$ctx/diff-index.txt"

kind=mixed
[ "$code" -gt 0 ] && kind=code
[ "$files" -eq "$docs" ] && kind=docs-only
[ "$files" -eq "$tests" ] && kind=tests-only
[ "$files" -eq "$config" ] && kind=config-only
[ "$files" -eq 0 ] && kind=empty

line="classify-change: kind $kind files $files lines $lines"
printf '%s\n' "$line" >"$ctx/class.txt"
echo "$line"
