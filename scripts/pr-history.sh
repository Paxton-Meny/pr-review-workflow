#!/bin/sh
# Read the repository's merged pull request history, so setup can fit the
# configuration to how the project and its developers actually ship.
# Usage: sh scripts/pr-history.sh <survey-dir> [limit]
#
# One gh call lists the last <limit> merged pull requests (default 100,
# at most 200) with their sizes and authors; when that call fails, a
# REST fallback lists them without sizes and the output says so. Writes
# history.txt (one record per pull request: number, author, added,
# deleted, files, fork, merged) and history-summary.txt (the printed
# lines), and prints "history:" lines: the source and count, the user's
# own login, the p50, p90, and maximum changed lines with their ratio,
# the share of pull requests over each size the review loop reacts to,
# the fork share and author count, and per-author lines for the most
# frequent authors and always for the user. Nothing is posted.
set -eu

dir=${1:?usage: pr-history.sh <survey-dir> [limit]}
limit=${2:-100}
[ -f "$dir/meta.txt" ] || {
	echo "pr-history: no meta.txt in $dir, run inventory-repo.sh first" >&2
	exit 1
}
case "$limit" in
'' | *[!0-9]* | 0)
	echo "pr-history: limit must be a positive number: $limit" >&2
	exit 1
	;;
esac
[ "$limit" -le 200 ] || limit=200
owner=$(sed -n 's/^owner //p' "$dir/meta.txt")
repo=$(sed -n 's/^repo //p' "$dir/meta.txt")
[ -n "$owner" ] && [ -n "$repo" ] || {
	echo "pr-history: meta.txt names no owner and repo" >&2
	exit 1
}

SMALL_LINES=300
LARGE_CODE_LINES=800
SHARD_LINES=1500
SIZE_WARN_LINES=4000
MAX_AUTHORS=8

work=$(mktemp -d "$dir/.history.XXXXXX")
trap 'rm -rf "$work"' EXIT

source=pr-list
if ! gh pr list --repo "$owner/$repo" --state merged --limit "$limit" \
	--json number,author,additions,deletions,changedFiles,isCrossRepository,mergedAt \
	--jq '.[] | "\(.number) \(.author.login) \(.additions) \(.deletions) \(.changedFiles) \(.isCrossRepository) \(.mergedAt)"' >"$work/raw" 2>/dev/null; then
	source=api-fallback
	gh api "repos/$owner/$repo/pulls" -X GET -f state=closed -F per_page=100 \
		--jq ".[] | select(.merged_at != null) | \"\\(.number) \\(.user.login) - - - \\(.head.repo.full_name != \"$owner/$repo\") \\(.merged_at)\"" >"$work/raw" 2>/dev/null || {
		echo "pr-history: gh could list no merged pull requests for $owner/$repo" >&2
		exit 1
	}
fi
tr -d '\r' <"$work/raw" | awk 'NF == 7 && $1 ~ /^[0-9]+$/' >"$work/history.txt"
self=$(gh api user --jq '"\(.login) \(.id)"' 2>/dev/null) || self=''
self_login=${self%% *}

awk -v source="$source" -v self="$self_login" -v small="$SMALL_LINES" -v large="$LARGE_CODE_LINES" \
	-v shard="$SHARD_LINES" -v warn="$SIZE_WARN_LINES" -v max_authors="$MAX_AUTHORS" '
function pct(k, n) { return (n > 0) ? int(k * 100 / n + 0.5) : 0 }
function sortn(arr, n,    i, j, t) { for (i = 2; i <= n; i++) { t = arr[i]; j = i - 1; while (j > 0 && arr[j] > t) { arr[j + 1] = arr[j]; j-- } arr[j + 1] = t } }
function quant(arr, n, q,    k) { k = int(n * q + 0.999999); if (k < 1) k = 1; if (k > n) k = n; return arr[k] }
{
	n++
	login = $2
	if (!(login in seen)) { seen[login] = 1; authors++ }
	count[login]++
	if ($7 != "" && (oldest == "" || $7 < oldest)) oldest = $7
	if ($6 == "true") forks++
	if ($3 == "-") { sizes = 0; next }
	sizes = 1
	changed = $3 + $4
	all[n] = changed
	by[login, count[login]] = changed
	if (changed > small) over_small++
	if (changed > large) over_large++
	if (changed > shard) over_shard++
	if (changed > warn) over_warn++
}
END {
	since = (oldest == "") ? "unknown" : substr(oldest, 1, 10)
	printf "history: source %s prs %d merged since %s\n", source, n, since
	printf "history: self %s\n", (self == "" ? "unknown" : self)
	if (n == 0) { print "history: no merged pull requests"; exit }
	if (!sizes) { print "history: sizes unavailable"; printf "history: forks %d%% authors %d\n", pct(forks, n), authors; exit }
	sortn(all, n)
	p50 = quant(all, n, 0.5); p90 = quant(all, n, 0.9); mx = all[n]
	disp = (p50 > 0) ? p90 / p50 : (p90 > 0 ? 99 : 1)
	printf "history: lines p50 %d p90 %d max %d dispersion %.1f\n", p50, p90, mx, disp
	printf "history: share over %d %d%% over %d %d%% over %d %d%% over %d %d%%\n", small, pct(over_small, n), large, pct(over_large, n), shard, pct(over_shard, n), warn, pct(over_warn, n)
	printf "history: forks %d%% authors %d\n", pct(forks, n), authors
	na = 0
	for (a in count) order[++na] = a
	for (i = 1; i <= na; i++) for (j = i + 1; j <= na; j++) if (count[order[j]] > count[order[i]] || (count[order[j]] == count[order[i]] && order[j] < order[i])) { t = order[i]; order[i] = order[j]; order[j] = t }
	shown = 0
	for (i = 1; i <= na; i++) {
		a = order[i]
		if (shown >= max_authors && a != self) continue
		m = count[a]
		delete vals
		for (k = 1; k <= m; k++) vals[k] = by[a, k]
		sortn(vals, m)
		printf "history: author %s prs %d p50 %d p90 %d max %d self %s\n", a, m, quant(vals, m, 0.5), quant(vals, m, 0.9), vals[m], (a == self ? "yes" : "no")
		shown++
	}
}' "$work/history.txt" >"$work/history-summary.txt"

mv "$work/history.txt" "$dir/history.txt"
mv "$work/history-summary.txt" "$dir/history-summary.txt"
cat "$dir/history-summary.txt"
