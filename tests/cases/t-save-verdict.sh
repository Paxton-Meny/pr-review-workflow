#!/bin/sh
# save-verdict: exactly one well-formed verdict line for an existing
# bundle is recorded beside the base it judged; anything else is refused
# and nothing is written.
set -eu

dir="$SCRATCH/state"
bundle="$dir/pr-context/overlap/base"
mkdir -p "$bundle" "$dir/pr-context/overlap/pr-12"
printf 'label base\nbase abc123\nmerge_base def456\ncommits 2\nnear\tsrc/app.py\t10-12\t20-20\t\nlevel near files 1 near 1 same 0\n' >"$bundle/summary.txt"
printf 'label pr-12\npull_request 12\nlevel same files 1 near 0 same 1\n' >"$dir/pr-context/overlap/pr-12/summary.txt"
save() { sh "$REPO_ROOT/scripts/save-verdict.sh" "$dir" "$@"; }

printf '\n\nverdict base independent: alpha gains a constant; ours renames another.\n\n' | save base | grep -qx 'save-verdict: base independent'
[ "$(cat "$bundle/verdict.txt")" = "$(printf 'label base\nbase abc123\nverdict base independent: alpha gains a constant; ours renames another.')" ]
printf 'verdict pr-12 duplicate: both guard the same null.\n' | save pr-12 | grep -qx 'save-verdict: pr-12 duplicate'
[ "$(cat "$dir/pr-context/overlap/pr-12/verdict.txt")" = "$(printf 'label pr-12\nverdict pr-12 duplicate: both guard the same null.')" ]

refuse() {
	# refuse <label> <message fragment> <report...>
	label=$1 want=$2
	shift 2
	before=$(cat "$bundle/verdict.txt")
	if printf '%s\n' "$@" | save "$label" 2>"$SCRATCH/err"; then
		echo "expected refusal: $want" >&2
		exit 1
	fi
	grep -q "$want" "$SCRATCH/err"
	[ "$(cat "$bundle/verdict.txt")" = "$before" ]
}
refuse base 'exactly one verdict line' 'verdict base independent: a.' 'verdict base duplicate: b.'
refuse base 'exactly one verdict line' ''
refuse base 'not a verdict line for base' 'verdict pr-12 independent: wrong label.'
refuse base 'not a verdict line for base' 'verdict base unsure: not a kind.'
refuse base 'not a verdict line for base' 'verdict base independent:'
refuse base 'not a verdict line for base' 'I judged it independent.'
refuse pr-9 'no overlap bundle for pr-9' 'verdict pr-9 independent: no bundle.'
refuse 'pr-9x' 'label must be base or pr-<number>' 'verdict pr-9x independent: x.'
refuse other 'label must be base or pr-<number>' 'verdict other independent: x.'
