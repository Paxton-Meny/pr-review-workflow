#!/bin/sh
# Update header fields of one finding record, enforcing status transitions.
# Usage: sh scripts/update-finding.sh <state-dir> <id> <field>=<value>...
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
reopen=0
new_status=''
for arg in "$@"; do
	field=${arg%%=*}
	value=${arg#*=}
	case "$field" in
	status)
		case "$current->$value" in
		'open->addressed' | 'open->wont-fix' | 'addressed->verified') ;;
		'addressed->open') reopen=1 ;;
		*)
			echo "update-finding: illegal transition $current to $value on $id" >&2
			exit 1
			;;
		esac
		new_status=$value
		;;
	comment_id | commit)
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
	*)
		echo "update-finding: unknown field: $field" >&2
		exit 1
		;;
	esac
done

tmp=$(mktemp "$dir/findings/.$id.XXXXXX")
trap 'rm -f "$tmp"' EXIT
cp "$record" "$tmp"
for arg in "$@"; do
	field=${arg%%=*}
	value=$(printf '%s' "${arg#*=}" | tr -d '\n')
	sed "s|^$field:.*|$field: $value|" "$tmp" >"$tmp.2"
	mv "$tmp.2" "$tmp"
done
if [ "$reopen" -eq 1 ]; then
	count=$(sed -n 's/^reopens: //p' "$tmp")
	sed "s|^reopens:.*|reopens: $((count + 1))|" "$tmp" >"$tmp.2"
	mv "$tmp.2" "$tmp"
fi
mv "$tmp" "$record"
trap - EXIT

echo "update-finding: $id updated${new_status:+ to $new_status}"
