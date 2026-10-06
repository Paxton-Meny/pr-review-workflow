#!/bin/sh
# Resolve the settings for one run from every source, highest last.
# Usage: sh scripts/resolve-settings.sh <state-dir> <<'END'
#        <key> <value from the user's plugin configuration>
#        ...
#        END
#        sh scripts/resolve-settings.sh <state-dir> --approve <hash>
#
# Sources, lowest to highest: the manifest defaults; the user's plugin
# configuration (stdin, one "key value" line each); the project's shared
# file .claude/pr-review-workflow.conf, read from origin/<base> and never
# from disk, so a pull request cannot change how it is reviewed; the
# user's personal .claude/pr-review-workflow.local.conf, untracked, from
# the clone; and the per-run overrides init-state recorded. A value
# still reading as a literal ${user_config...} placeholder, as on an
# install with no saved configuration, counts as unset, and so does an
# empty user value. An invalid value is reported and the key keeps what
# the source below it gave, never jumping to the default.
#
# The shared file is the team's, so it may set less than the others:
# never auto_approve, the models, routing, keep_ledgers, or
# local_standards; the quality settings only upward (a project may raise
# the bar, only the user may lower it); and the check command and
# contract prefixes, which execute, only once the user approved that
# exact pair (trust on first use). An unapproved pair is ignored and
# reported with its hash as pending; --approve records the pending hash
# and nothing else.
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
data_root=$(CDPATH= cd -- "$dir/../.." && pwd)
owner=$(sed -n 's/^owner //p' "$dir/meta.txt")
repo=$(sed -n 's/^repo //p' "$dir/meta.txt")
trusted="$data_root/trust/${owner}__${repo}.trusted"
pending="$data_root/trust/${owner}__${repo}.pending"

if [ "${2:-}" = --approve ]; then
	want=${3:?usage: resolve-settings.sh <state-dir> --approve <hash>}
	[ -f "$pending" ] && [ "$(cat "$pending")" = "$want" ] || {
		echo "resolve-settings: $want is not the pending approval for $owner/$repo" >&2
		exit 1
	}
	printf '%s\n' "$want" >>"$trusted"
	rm -f "$pending"
	echo "resolve-settings: approved $want for $owner/$repo"
	exit 0
fi

SHARED=.claude/pr-review-workflow.conf
LOCAL=.claude/pr-review-workflow.local.conf
MAX_BYTES=16384
ALIASES='posture:cost_posture samples:review_samples check:check_command prefixes:contract_commands standards:local_standards routing:model_routing strong:strong_model reviewer:reviewer_model editor:editor_model verifier:verifier_model filter:finding_filter second_review:double_review ledgers:keep_ledgers'
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
: >"$work/notes"

# Normalise a file to canonical "key value" lines: comments and blank
# lines dropped, indentation and CRLF removed, aliases resolved, and
# lines over 1 KB refused.
normalise() {
	# normalise <in> <out> <source name>
	tr -d '\r' <"$1" | awk -v aliases="$ALIASES" -v src="$3" -v notes="$work/notes" '
	BEGIN { n = split(aliases, a, " "); for (i = 1; i <= n; i++) { split(a[i], p, ":"); alias[p[1]] = p[2] } }
	{
		line = $0; sub(/^[ \t]+/, "", line); sub(/[ \t]+$/, "", line)
		if (line ~ /^(#|$)/) next
		if (length(line) > 1024) { print "settings: ignored " src " line " NR ": longer than 1024 characters" >> notes; next }
		k = line; sub(/[ \t].*$/, "", k)
		v = line; sub(/^[^ \t]*[ \t]*/, "", v)
		if (k in alias) k = alias[k]
		print k (v == "" ? "" : " " v)
	}' >"$2"
}

# The shared file, from the base branch only.
: >"$work/project"
shared_state=absent
base=$(sed -n 's/^base_branch //p' "$dir/meta.txt")
repo_root=$(sed -n 's/^repo_root //p' "$dir/meta.txt")
if [ -n "$base" ] && [ -n "$repo_root" ] && [ -d "$repo_root" ]; then
	fetch=$(sh "$here/fetch-base.sh" "$repo_root" "$base" 2>/dev/null || true)
	freshness=${fetch##* }
	if [ "$freshness" = unavailable ] || [ -z "$fetch" ]; then
		shared_state=unavailable
	elif size=$(git -C "$repo_root" cat-file -s "refs/remotes/origin/$base:$SHARED" 2>/dev/null); then
		if [ "$size" -gt "$MAX_BYTES" ]; then
			shared_state=refused
			echo "settings: ignored project file: larger than $MAX_BYTES bytes" >>"$work/notes"
		else
			git -C "$repo_root" show "refs/remotes/origin/$base:$SHARED" >"$work/project.raw"
			normalise "$work/project.raw" "$work/project" project
			shared_state=$freshness
		fi
	fi
fi

# The personal file, from the clone (this worktree first, then the main
# one), never from the pull request's worktree, never a symlink, and
# never a file the repository tracks.
: >"$work/local"
local_state=absent
if [ -n "$repo_root" ] && [ -d "$repo_root" ]; then
	main_root=$(git -C "$repo_root" worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')
	[ -n "$main_root" ] && [ "$main_root" != "$repo_root" ] || main_root=''
	for root in "$repo_root" $main_root; do
		path="$root/$LOCAL"
		[ -e "$path" ] || [ -L "$path" ] || continue
		if [ -L "$path" ]; then
			local_state=refused
			echo "settings: ignored local file: it is a symlink" >>"$work/notes"
		elif git -C "$root" ls-files --error-unmatch "$LOCAL" >/dev/null 2>&1; then
			local_state=refused
			echo "settings: ignored local file: the repository tracks it, so it is not yours alone" >>"$work/notes"
		elif [ "$(wc -c <"$path" | tr -d ' ')" -gt "$MAX_BYTES" ]; then
			local_state=refused
			echo "settings: ignored local file: larger than $MAX_BYTES bytes" >>"$work/notes"
		else
			normalise "$path" "$work/local" local
			local_state=present
		fi
		break
	done
fi

# Trust on first use for the shared file's commands.
exec_trusted=1
exec_hash=''
grep -E '^(check_command|contract_commands)( |$)' "$work/project" >"$work/exec" || true
if [ -s "$work/exec" ]; then
	exec_hash=$(git hash-object --stdin <"$work/exec")
	if ! { [ -f "$trusted" ] && grep -qx "$exec_hash" "$trusted"; }; then
		exec_trusted=0
		mkdir -p "$data_root/trust"
		printf '%s\n' "$exec_hash" >"$pending"
		sed "s/^/settings: trust pending $exec_hash /" "$work/exec" >>"$work/notes"
	fi
fi

awk -v spec="$work/spec" -v out="$work/settings" -v src="$work/sources" \
	-v exec_trusted="$exec_trusted" -v aliases="$ALIASES" '
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
	n = split(aliases, pairs, " ")
	for (i = 1; i <= n; i++) { split(pairs[i], p, ":"); alias[p[1]] = p[2] }
	split("auto_approve reviewer_model editor_model verifier_model model_routing strong_model keep_ledgers local_standards", nvk, " ")
	for (i in nvk) never[nvk[i]] = 1
	# Strength order for the settings a shared file may only raise.
	rank["double_review", "off"] = 0; rank["double_review", "risky"] = 1; rank["double_review", "always"] = 2
	rank["finding_filter", "false"] = 0; rank["finding_filter", "true"] = 1
	rank["cost_posture", "economy"] = 0; rank["cost_posture", "balanced"] = 1; rank["cost_posture", "quality"] = 2
	names[1] = "user"; names[2] = "project"; names[3] = "local"; names[4] = "run"
}
FNR == 1 { for (i = 1; i <= 4; i++) if (FILENAME == ARGV[i]) source = names[i] }
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
	if (source == "project") {
		if (k in never) { ignored[++ni] = "project " k ": only you can set this, in your own configuration or local file"; next }
		if ((k == "check_command" || k == "contract_commands") && exec_trusted != 1) next
		if ((k, nv) in rank && (k, val[k]) in rank && rank[k, nv] < rank[k, val[k]]) {
			ignored[++ni] = "project " k ": would lower " val[k] " to " nv "; a project may only raise it"; next
		}
		if (k == "review_samples" && nv + 0 < val[k] + 0) {
			ignored[++ni] = "project " k ": would lower " val[k] " to " nv "; a project may only raise it"; next
		}
		# A project adds sensitive paths; it never removes yours.
		if (k == "sensitive_paths" && val[k] != "") nv = (nv == "" ? val[k] : val[k] " " nv)
	}
	val[k] = nv; from[k] = source
}
END {
	for (i = 1; i <= nk; i++) {
		k = keys[i]
		printf "%s%s%s\n", k, (val[k] == "" ? "" : " "), val[k] > out
		print k " " from[k] > src
		count[from[k]]++
	}
	printf "settings: resolved %d default %d user %d project %d local %d run %d ignored %d\n", nk, count["default"] + 0, count["user"] + 0, count["project"] + 0, count["local"] + 0, count["run"] + 0, ni + 0
	# The facts the orchestrator branches on, never the commands themselves.
	printf "settings: for this run auto_approve %s\n", val["auto_approve"]
	for (i = 1; i <= nk; i++) {
		k = keys[i]
		if (from[k] != "default" && from[k] != "user") printf "settings: %s %s from %s\n", k, (val[k] == "" ? "(empty)" : val[k]), from[k]
	}
	for (i = 1; i <= ni; i++) print "settings: ignored " ignored[i]
}
' "$work/user" "$work/project" "$work/local" "$work/run" >"$work/report"
printf 'settings: project file %s, local file %s\n' "$shared_state" "$local_state" >>"$work/report"
cat "$work/notes" >>"$work/report"

# Publish atomically, read-only, and record its hash outside the state
# directory, where the executing scripts check it.
for f in settings sources; do
	[ -f "$dir/$f.txt" ] && chmod u+w "$dir/$f.txt"
	mv "$work/$f" "$dir/$f.txt"
	chmod 0444 "$dir/$f.txt"
done
mkdir -p "$data_root/trust/runs"
git hash-object "$dir/settings.txt" >"$data_root/trust/runs/$(basename "$dir").hash"
cat "$work/report"
