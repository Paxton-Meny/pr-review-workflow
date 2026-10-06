#!/bin/sh
# Resolve the settings for one run from every source, highest last.
# Usage: sh scripts/resolve-settings.sh <state-dir> <<'END'
#        <key> <value from the user's plugin configuration>
#        ...
#        END
#
# Sources, lowest to highest: the manifest defaults, the user's plugin
# configuration (stdin, one "key value" line each), and the per-run
# overrides init-state recorded in overrides.txt. A value still reading
# as a literal ${user_config...} placeholder, as on an install with no
# saved configuration, counts as unset, and so does an empty user value.
# An invalid value is reported and the key keeps what the source below
# it gave, never jumping to the default.
#
# Writes <state-dir>/settings.txt (key value, read-only), sources.txt
# (key source), and a hash of settings.txt under the data root's
# trust/runs/ that the executing scripts check. Prints a summary line,
# a line of the facts the orchestrator branches on, one line per value
# set above the user's own configuration, and one per ignored entry.
set -eu

dir=${1:?usage: resolve-settings.sh <state-dir>}
[ -f "$dir/meta.txt" ] || {
	echo "resolve-settings: no meta.txt in $dir, run init-state.sh first" >&2
	exit 1
}
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
manifest="$here/../.claude-plugin/plugin.json"
[ -f "$manifest" ] || {
	echo "resolve-settings: no plugin manifest at $manifest" >&2
	exit 1
}

work=$(mktemp -d "$dir/.settings.XXXXXX")
trap 'rm -rf "$work"' EXIT

# key|type|default|options|min|max, one line per userConfig entry.
awk '
/^  "userConfig": \{/ { inside = 1; next }
!inside { next }
/^  \}/ { inside = 0; next }
/^    "[a-z_]+": \{/ {
	key = $1; gsub(/[":]/, "", key); type = ""; def = ""; opts = ""; lo = ""; hi = ""; next
}
/^      "type":/ { type = $2; gsub(/[",]/, "", type) }
/^      "default":/ { def = $0; sub(/^[^:]*: */, "", def); sub(/,$/, "", def); gsub(/"/, "", def) }
/^      "options":/ {
	opts = $0; sub(/^[^\[]*\[/, "", opts); sub(/\].*$/, "", opts); gsub(/[",]/, "", opts)
}
/^      "min":/ { lo = $2; gsub(/,/, "", lo) }
/^      "max":/ { hi = $2; gsub(/,/, "", hi) }
/^    \}/ { print key "|" type "|" def "|" opts "|" lo "|" hi }
' "$manifest" >"$work/spec"
[ -s "$work/spec" ] || {
	echo "resolve-settings: no settings found in the manifest" >&2
	exit 1
}

# Each source as "key value" lines; the user's arrive on stdin.
tr -d '\r' >"$work/user"
: >"$work/run"
[ -f "$dir/overrides.txt" ] && tr -d '\r' <"$dir/overrides.txt" >"$work/run"

awk -v spec="$work/spec" -v out="$work/settings" -v src="$work/sources" '
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function canon(k) { return (k in alias) ? alias[k] : k }
# Returns the normalised value, or sets err and returns "".
function check(k, v,    n) {
	err = ""
	if (type[k] == "boolean") {
		v = tolower(v)
		if (v == "true" || v == "on" || v == "yes") return "true"
		if (v == "false" || v == "off" || v == "no") return "false"
		err = "not true or false"; return ""
	}
	if (type[k] == "number") {
		if (v !~ /^[0-9]+(\.0*)?$/) { err = "not a whole number"; return "" }
		n = v + 0
		if (lo[k] != "" && n < lo[k] + 0) { err = "below the minimum " lo[k]; return "" }
		if (hi[k] != "" && n > hi[k] + 0) { err = "above the maximum " hi[k]; return "" }
		return n ""
	}
	if (opts[k] != "") {
		if ((" " opts[k] " ") !~ (" " v " ")) { err = "not one of: " opts[k]; return "" }
		return v
	}
	if (v == "" && def[k] != "") { err = "cannot be empty"; return "" }
	return v
}
BEGIN {
	while ((getline line < spec) > 0) {
		split(line, f, "|")
		k = f[1]; keys[++nk] = k
		type[k] = f[2]; def[k] = f[3]; opts[k] = f[4]; lo[k] = f[5]; hi[k] = f[6]
		val[k] = def[k]; from[k] = "default"
	}
	split("posture:cost_posture samples:review_samples check:check_command prefixes:contract_commands standards:local_standards routing:model_routing strong:strong_model reviewer:reviewer_model editor:editor_model verifier:verifier_model filter:finding_filter second_review:double_review ledgers:keep_ledgers", pairs, " ")
	for (i in pairs) { split(pairs[i], p, ":"); alias[p[1]] = p[2] }
}
FNR == 1 { source = (FILENAME == ARGV[1]) ? "user" : "run" }
{
	line = trim($0)
	if (line ~ /^(#|$)/) next
	k = line; sub(/[ \t].*$/, "", k)
	v = line; sub(/^[^ \t]*/, "", v); v = trim(v)
	k = canon(k)
	if (!(k in type)) { ignored[++ni] = source " " k ": unknown setting"; next }
	if (source == "user") {
		if (v == "" || v ~ /^\$\{user_config\./) next
	}
	nv = check(k, v)
	if (err != "") { ignored[++ni] = source " " k ": " err; next }
	val[k] = nv; from[k] = source
}
END {
	for (i = 1; i <= nk; i++) {
		k = keys[i]
		printf "%s%s%s\n", k, (val[k] == "" ? "" : " "), val[k] > out
		print k " " from[k] > src
		count[from[k]]++
	}
	printf "settings: resolved %d default %d user %d run %d ignored %d\n", nk, count["default"] + 0, count["user"] + 0, count["run"] + 0, ni + 0
	# The facts the orchestrator branches on, never the commands themselves.
	printf "settings: for this run auto_approve %s check %s standards %s double_review %s finding_filter %s review_samples %s\n", \
		val["auto_approve"], (val["check_command"] == "" ? "unset" : "set"), \
		(val["local_standards"] == "" ? "unset" : "set"), val["double_review"], \
		val["finding_filter"], val["review_samples"]
	for (i = 1; i <= nk; i++) {
		k = keys[i]
		if (from[k] != "default" && from[k] != "user") printf "settings: %s %s from %s\n", k, (val[k] == "" ? "(empty)" : val[k]), from[k]
	}
	for (i = 1; i <= ni; i++) print "settings: ignored " ignored[i]
}
' "$work/user" "$work/run" >"$work/report"

# Publish atomically, read-only, and record its hash outside the state
# directory, where the executing scripts check it.
for f in settings sources; do
	[ -f "$dir/$f.txt" ] && chmod u+w "$dir/$f.txt"
	mv "$work/$f" "$dir/$f.txt"
	chmod 0444 "$dir/$f.txt"
done
data_root=$(CDPATH= cd -- "$dir/../.." && pwd)
mkdir -p "$data_root/trust/runs"
git hash-object "$dir/settings.txt" >"$data_root/trust/runs/$(basename "$dir").hash"
cat "$work/report"
