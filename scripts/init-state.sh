#!/bin/sh
# Create or refresh the review state directory for one pull request.
# Usage: sh scripts/init-state.sh <data-root> <pr-ref> [key=value ...]
#        sh scripts/init-state.sh <data-root> - <<'END'
#        <pr-ref> [key=value ...]
#        END
# With "-" the invocation text arrives on stdin, so whatever was typed is
# never pasted into a shell command line: quotes and $( ) stay inert.
# The first word is the pull request; the rest are per-run settings,
# key=value, a value with spaces quoted with " or '. They are written to
# overrides.txt (key value, one per line), replaced on every invocation,
# so a resumed run never keeps an earlier invocation's overrides.
# Once the ledger holds findings, head_sha, prev_head and arrived_base carry over and
# never come from GitHub: only push-branch.sh and checkout-pr.sh move
# them, so a push made outside the run surfaces through checkout-pr.sh.
set -eu

data_root=${1:?usage: init-state.sh <data-root> <pr-ref> [key=value ...]}
shift
if [ "${1:-}" = - ]; then
	text=$(cat)
else
	text=$*
fi
# Split into words, honouring quotes, one word per line; a bare word is
# kept as typed so the reference check below can name it.
words=$(printf '%s\n' "$text" | tr '\r\n' '  ' | awk '
{
	line = $0; n = length(line); w = ""; inword = 0; q = ""
	for (i = 1; i <= n; i++) {
		c = substr(line, i, 1)
		if (q != "") {
			if (c == q) q = ""; else w = w c
			continue
		}
		if (c == "\"" || c == "\047") { q = c; inword = 1; continue }
		if (c == " " || c == "\t") {
			if (inword) { print w; w = ""; inword = 0 }
			continue
		}
		w = w c; inword = 1
	}
	if (q != "") { print "init-state: unclosed quote in the arguments" > "/dev/stderr"; exit 2 }
	if (inword) print w
}') || exit 1
ref=$(printf '%s\n' "$words" | sed -n '1p')
[ -n "$ref" ] || {
	echo "usage: init-state.sh <data-root> <pr-ref> [key=value ...]" >&2
	exit 1
}
overrides=$(printf '%s\n' "$words" | sed '1d')
if [ -n "$overrides" ]; then
	bad=$(printf '%s\n' "$overrides" | grep -v '^[a-z_][a-z_]*=' | head -n 1 || true)
	[ -z "$bad" ] || {
		echo "init-state: expected key=value after the pull request, got: $bad" >&2
		exit 1
	}
fi

resolved=$(sh "$(dirname -- "$0")/resolve-ref.sh" "$ref")
owner=${resolved%% *}
rest=${resolved#* }
repo=${rest%% *}
number=${rest#* }
repo_root=$(git rev-parse --show-toplevel)
# The ledger holds review text, settings, and logs: the data root is
# private to the user whatever the umask.
mkdir -p "$data_root"
chmod 700 "$data_root"

meta=$(gh pr view "$number" --repo "$owner/$repo" \
	--json author,headRefName,baseRefName,headRefOid,url,state,isCrossRepository,maintainerCanModify,headRepository,headRepositoryOwner \
	--jq '"author \(.author.login)\nhead_branch \(.headRefName)\nbase_branch \(.baseRefName)\nhead_sha \(.headRefOid)\nurl \(.url)\ncross_repo \(.isCrossRepository)\nmaintainer_can_modify \(.maintainerCanModify)\nhead_repo_url \(if .headRepository then "https://github.com/\(.headRepositoryOwner.login)/\(.headRepository.name).git" else "" end)\nstate \(.state)"')
state=$(printf '%s\n' "$meta" | sed -n 's/^state //p')
if [ "$state" != "OPEN" ]; then
	echo "init-state: pull request $owner/$repo#$number is $state, not open" >&2
	exit 1
fi
self=$(gh api user --jq '"\(.login) \(.id)"')
self_login=${self%% *}
self_id=${self##* }
case "$self_id" in
'' | *[!0-9]*) self_email="${self_login}@users.noreply.github.com" ;;
*) self_email="${self_id}+${self_login}@users.noreply.github.com" ;;
esac

# The author's permission on the repository, for author-trust.sh: what
# GitHub says, or unknown when it cannot say (a bot, a failed call).
author=$(printf '%s\n' "$meta" | sed -n 's/^author //p')
permission=unknown
case "$author" in
'' | . | .. | *[!]A-Za-z0-9_.[-]*) ;;
*)
	permission=$(gh api "repos/$owner/$repo/collaborators/$author/permission" --jq .permission 2>/dev/null) || permission=unknown
	case "$permission" in
	admin | maintain | write | triage | read | none) ;;
	*) permission=unknown ;;
	esac
	;;
esac

dir="$data_root/state/${owner}__${repo}__${number}"
mkdir -p "$dir"
# The heads the run last saw. Once the ledger holds findings a resume
# keeps them, never GitHub's, so a push made outside the run waits for
# checkout-pr.sh (head_sha, prev_head) and commits pushed since stay
# unreviewed until reviewed-head.sh says so (reviewed_head). A ledger from
# before the reviewed_head field falls back to the head it last recorded.
seen=''
reviewed=''
for f in "$dir/findings"/F*; do
	[ -f "$f" ] && [ -f "$dir/meta.txt" ] || break
	seen=$(sed -n -e '/^head_sha ./p' -e '/^prev_head ./p' -e '/^arrived_base ./p' "$dir/meta.txt")
	reviewed=$(sed -n 's/^reviewed_head //p' "$dir/meta.txt")
	[ -n "$reviewed" ] || reviewed=$(sed -n 's/^arrived_base //p' "$dir/meta.txt")
	[ -n "$reviewed" ] || reviewed=$(sed -n 's/^head_sha //p' "$dir/meta.txt")
	break
done
[ -n "$reviewed" ] || reviewed=$(printf '%s\n' "$meta" | sed -n 's/^head_sha //p')
tmp=$(mktemp "$dir/.meta.XXXXXX")
{
	printf 'owner %s\nrepo %s\npr %s\n' "$owner" "$repo" "$number"
	if printf '%s\n' "$seen" | grep -q '^head_sha '; then
		printf '%s\n' "$meta" | sed -e '/^state /d' -e '/^head_sha /d'
		printf '%s\n' "$seen"
	else
		printf '%s\n' "$meta" | sed '/^state /d'
	fi
	printf 'reviewed_head %s\nauthor_permission %s\n' "$reviewed" "$permission"
	printf 'self_login %s\nself_email %s\n' "$self_login" "$self_email"
	printf 'repo_root %s\n' "$repo_root"
} >"$tmp"
mv "$tmp" "$dir/meta.txt"
tmp=$(mktemp "$dir/.overrides.XXXXXX")
[ -z "$overrides" ] || printf '%s\n' "$overrides" | sed 's/=/ /' >"$tmp"
mv "$tmp" "$dir/overrides.txt"
if [ ! -f "$dir/round.txt" ]; then
	tmp=$(mktemp "$dir/.round.XXXXXX")
	printf '0\n' >"$tmp"
	mv "$tmp" "$dir/round.txt"
fi

printf '%s\n' "$dir"
