#!/bin/sh
# Update header fields of one finding record, enforcing status transitions.
# Usage: sh scripts/update-finding.sh <state-dir> <id> <field>=<value>...
# Only header lines change, never the body; a field the record does not
# carry yet (accepted, proven) is added at the end of the header.
set -eu

dir=${1:?usage: update-finding.sh <state-dir> <id> <field>=<value>...}
id=${2:?usage: update-finding.sh <state-dir> <id> <field>=<value>...}
shift 2
[ "$#" -gt 0 ] || {
	echo "update-finding: nothing to update" >&2
	exit 1
}

record="$dir/findings/$id"
[ -f "$record" ] || {
	echo "update-finding: unknown finding: $id" >&2
	exit 1
}

current=$(sed -n 's/^status: //p' "$record")
reopen=0 arbitrated=0
new_status=''
for arg in "$@"; do
	field=${arg%%=*}
	value=${arg#*=}
	case "$field" in
	status)
		# open->verified is the arbitration verdict: a reopened finding
		# re-judged against code that already changed in an earlier round.
		case "$current->$value" in
		'open->addressed' | 'open->wont-fix' | 'addressed->verified') ;;
		'open->verified') arbitrated=1 ;;
		'addressed->open') reopen=1 ;;
		*)
			echo "update-finding: illegal transition $current to $value on $id" >&2
			exit 1
			;;
		esac
		new_status=$value
		;;
	comment_id | commit | proven)
		case "$value" in
		*[!A-Za-z0-9]*)
			echo "update-finding: $field must be alphanumeric: $value" >&2
			exit 1
			;;
		esac
		;;
	placement)
		case "$value" in
		inline | summary) ;;
		*)
			echo "update-finding: placement must be inline or summary: $value" >&2
			exit 1
			;;
		esac
		;;
	accepted)
		# A person accepted the wont-fix reasoning; merge-pr.sh merges
		# over no wont-fix record without it.
		[ "$value" = yes ] || {
			echo "update-finding: accepted must be yes: $value" >&2
			exit 1
		}
		[ "$current" = wont-fix ] || {
			echo "update-finding: only a wont-fix finding can be accepted, $id is $current" >&2
			exit 1
		}
		;;
	*)
		echo "update-finding: unknown field: $field" >&2
		exit 1
		;;
	esac
done

tmp=$(mktemp "$dir/findings/.$id.XXXXXX")
trap 'rm -f "$tmp" "$tmp.u"' EXIT
for arg in "$@"; do
	printf '%s\t%s\n' "${arg%%=*}" "$(printf '%s' "${arg#*=}" | tr -d '\n')"
done >"$tmp.u"
awk -v updates="$tmp.u" '
BEGIN {
	while ((getline u < updates) > 0) {
		k = substr(u, 1, index(u, "\t") - 1)
		if (!(k in val)) order[++n] = k
		val[k] = substr(u, index(u, "\t") + 1)
	}
	head = 1
}
head && /^---$/ {
	for (i = 1; i <= n; i++) if (!(order[i] in seen)) print order[i] ": " val[order[i]]
	head = 0
}
head && match($0, /^[a-z_]+:/) {
	k = substr($0, 1, RLENGTH - 1)
	if (k in val) { print k ": " val[k]; seen[k] = 1; next }
}
{ print }
' "$record" >"$tmp"
rm -f "$tmp.u"
if [ "$reopen" -eq 1 ]; then
	count=$(sed -n 's/^reopens: //p' "$tmp")
	sed "s|^reopens:.*|reopens: $((count + 1))|" "$tmp" >"$tmp.2"
	mv "$tmp.2" "$tmp"
fi
[ "$arbitrated" -eq 1 ] && printf '\nArbitrated: verified from open, over the last reopen.\n' >>"$tmp"
mv "$tmp" "$record"
trap - EXIT

echo "update-finding: $id updated${new_status:+ to $new_status}"
