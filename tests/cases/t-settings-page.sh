#!/bin/sh
# The settings reference page states every setting exactly as the plugin
# manifest defines it, and its markup and script stay within the page's
# own content security policy.
set -eu

manifest="$REPO_ROOT/.claude-plugin/plugin.json"
page="$REPO_ROOT/docs/settings.html"
script="$REPO_ROOT/docs/assets/settings.js"

# One line per setting: key|default|options|min|max, taken from the manifest.
awk '
/^  "userConfig": \{/ { inside = 1; next }
!inside { next }
/^  \}/ { inside = 0; next }
/^    "[a-z_]+": \{/ {
	key = $1; gsub(/[":]/, "", key); def = ""; opts = ""; lo = ""; hi = ""; next
}
/^      "default":/ { def = $2; gsub(/[",]/, "", def) }
/^      "options":/ {
	opts = $0; sub(/^[^\[]*\[/, "", opts); sub(/\].*$/, "", opts); gsub(/[",]/, "", opts)
}
/^      "min":/ { lo = $2; gsub(/,/, "", lo) }
/^      "max":/ { hi = $2; gsub(/,/, "", hi) }
/^    \}/ { print key "|" def "|" opts "|" lo "|" hi }
' "$manifest" >"$SCRATCH/manifest.txt"

count=$(awk 'END { print NR }' "$SCRATCH/manifest.txt")
[ "$count" -gt 0 ] || {
	echo "no settings parsed from the manifest" >&2
	exit 1
}

attr() {
	printf '%s\n' "$1" | sed -n "s/.* $2=\"\([^\"]*\)\".*/\1/p"
}

while IFS='|' read -r key def opts lo hi; do
	line=$(grep " data-key=\"$key\"" "$page" || true)
	[ -n "$line" ] || {
		echo "settings page has no entry for $key" >&2
		exit 1
	}
	[ "$(printf '%s\n' "$line" | awk 'END { print NR }')" -eq 1 ] || {
		echo "settings page describes $key more than once" >&2
		exit 1
	}
	[ "$(attr "$line" data-default)" = "$def" ] || {
		echo "$key: page default '$(attr "$line" data-default)' is not the manifest's '$def'" >&2
		exit 1
	}
	[ "$(attr "$line" data-options)" = "$opts" ] || {
		echo "$key: page options '$(attr "$line" data-options)' are not the manifest's '$opts'" >&2
		exit 1
	}
	[ "$(attr "$line" data-min)" = "$lo" ] && [ "$(attr "$line" data-max)" = "$hi" ] || {
		echo "$key: page bounds differ from the manifest's '$lo' to '$hi'" >&2
		exit 1
	}
done <"$SCRATCH/manifest.txt"

# The page describes nothing the manifest does not define.
[ "$(grep -c ' data-key="' "$page")" -eq "$count" ] || {
	echo "settings page has entries the manifest does not define" >&2
	exit 1
}
grep -q "Filter $count settings" "$page"

# Every in-page link lands on an element that exists.
grep -o 'href="#[^"]*"' "$page" | sed 's/^href="#//; s/"$//' | sort -u >"$SCRATCH/links.txt"
while read -r id; do
	grep -q " id=\"$id\"" "$page" || {
		echo "settings page links to #$id, which does not exist" >&2
		exit 1
	}
done <"$SCRATCH/links.txt"

# The policy allows only the page's own files, so nothing may be inline.
grep -q "script-src 'self'; style-src 'self'" "$page"
if grep -qE ' style="|<style| on[a-z]+="|javascript:' "$page"; then
	echo "settings page carries inline style or script" >&2
	exit 1
fi
[ "$(grep -c '<script' "$page")" -eq 1 ]
grep -q '<script src="assets/settings.js" defer></script>' "$page"

# The script writes text, never markup, and reaches for nothing outside the page.
if grep -qE 'innerHTML|outerHTML|insertAdjacentHTML|document\.write|eval\(|new Function|setAttribute\(.style|fetch\(|XMLHttpRequest|localStorage|sessionStorage|document\.cookie|location\.(hash|search|href)|import\(' "$script"; then
	echo "settings script uses a construct this page forbids" >&2
	exit 1
fi
grep -q "'use strict';" "$script"

# What the page says a project's shared file may do matches the resolver.
resolver="$REPO_ROOT/scripts/resolve-settings.sh"
list() { sed -n "s/^PROJECT_$1='\(.*\)'\$/\1/p" "$resolver"; }
: >"$SCRATCH/classes.txt"
for cls in NEVER RAISE TRUSTED ADDS; do
	for key in $(list "$cls"); do
		printf '%s %s\n' "$key" "$(printf '%s' "$cls" | tr 'A-Z' 'a-z')" >>"$SCRATCH/classes.txt"
	done
done
[ "$(awk 'END { print NR }' "$SCRATCH/classes.txt")" -eq "$count" ] || {
	echo "every manifest setting must be in exactly one of the resolver's PROJECT_ lists" >&2
	exit 1
}
[ "$(cut -d' ' -f1 "$SCRATCH/classes.txt" | sort -u | awk 'END { print NR }')" -eq "$count" ]
while read -r key cls; do
	line=$(grep " data-key=\"$key\"" "$page")
	[ "$(attr "$line" data-project)" = "$cls" ] || {
		echo "$key: the page says a project file may '$(attr "$line" data-project)', the resolver says '$cls'" >&2
		exit 1
	}
done <"$SCRATCH/classes.txt"
