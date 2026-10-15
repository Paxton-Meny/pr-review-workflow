#!/bin/sh
# Hold the plugin's own agents to the files and commands their definitions name.
# Usage: sh scripts/agent-scope.sh <hook-input.json
# A PreToolUse hook on Bash, Read, Grep, Glob, Edit, Write, MultiEdit,
# and NotebookEdit. It acts only on a call whose input names one of
# this plugin's agents in agent_type, which Claude Code sets for a
# subagent's calls; every other call, the user's own session included,
# passes untouched. It never allows anything: a call it does not deny
# goes through the user's permissions as before.
#
# An agent reads the pull request, and the pull request may address it.
# Its definition says what it may touch; this makes that binding:
# - Read, Grep, and Glob stay inside the plugin's data directory, the
#   plugin itself, and the session's folder, with no ".." and no
#   symlinked file, so a link planted in the change reads nothing
#   outside.
# - Edit and Write stay inside a review worktree.
# - Bash runs only "git -C <path in the data directory>" with the git
#   subcommands the agent's definition names, and "sh <plugin>/scripts/
#   <script>.sh <dir in the data directory> ..." for the scripts it
#   names, alone, after printf or echo and one pipe, or with a quoted
#   heredoc. No expansion, substitution, redirection, or other operator,
#   no git option that reads, writes, or runs something else, and no
#   status change the agent's role does not make.
# Without CLAUDE_PLUGIN_DATA nothing can be placed and every call passes.
set -u

input=$(cat)
case "$input" in
*'"agent_type":"pr-review-workflow:'* | *'"agent_type": "pr-review-workflow:'*) ;;
*) exit 0 ;;
esac
[ -n "${CLAUDE_PLUGIN_DATA:-}" ] && [ -d "$CLAUDE_PLUGIN_DATA" ] || exit 0
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=${CLAUDE_PLUGIN_ROOT:-$(CDPATH= cd -- "$here/.." && pwd)}

decide() {
	# decide <reason>: deny the call, saying why on one line
	reason=$(printf '%s' "$1" | tr '\n\t\r' '   ' | sed 's/\\/\\\\/g; s/"/\\"/g')
	printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$reason"
	exit 0
}

fields=$(mktemp -d) || exit 0
trap 'rm -rf "$fields"' EXIT

# Decode the string fields this hook reads, one file each: agent_type,
# tool_name, and cwd at the top level, and the tool's own fields one
# level down. A key inside a string value is never mistaken for one.
printf '%s' "$input" | awk -v out="$fields" '
function hex(h,    i, c, n) {
	n = 0
	for (i = 1; i <= 4; i++) {
		c = index("0123456789abcdef", tolower(substr(h, i, 1)))
		if (c == 0) return -1
		n = n * 16 + c - 1
	}
	return n
}
function emit(name, val,    f) {
	if (name in seen) return
	seen[name] = 1
	f = out "/" name
	printf "%s", val > f
	close(f)
}
BEGIN {
	top["agent_type"] = 1; top["tool_name"] = 1; top["cwd"] = 1
	inner["command"] = 1; inner["file_path"] = 1; inner["path"] = 1; inner["notebook_path"] = 1; inner["pattern"] = 1
}
{ s = s (NR > 1 ? "\n" : "") $0 }
END {
	n = length(s); i = 1; depth = 0; prev = ""; key = ""
	while (i <= n) {
		c = substr(s, i, 1)
		if (c == "\"") {
			v = ""; i++
			while (i <= n) {
				if (match(substr(s, i, 512), /^[^"\\]+/)) { v = v substr(s, i, RLENGTH); i += RLENGTH; continue }
				c = substr(s, i, 1)
				if (c == "\"") break
				e = substr(s, i + 1, 1)
				if (e == "n") v = v "\n"
				else if (e == "t") v = v "\t"
				else if (e == "r") v = v "\r"
				else if (e == "b") v = v "\b"
				else if (e == "f") v = v "\f"
				else if (e == "u") {
					cp = hex(substr(s, i + 2, 4))
					v = v ((cp > 0 && cp < 128) ? sprintf("%c", cp) : "\001")
					i += 4
				} else v = v e
				i += 2
			}
			i++
			j = i
			while (j <= n && substr(s, j, 1) ~ /[ \t\r\n]/) j++
			if (substr(s, j, 1) == ":") { key = v; kdepth = depth; prev = ":"; i = j + 1; continue }
			if (prev == ":") {
				if (kdepth == 1 && (key in top)) emit(key, v)
				if (kdepth == 2 && (key in inner)) emit("input_" key, v)
			}
			prev = "v"
			continue
		}
		if (c == "{" || c == "[") depth++
		else if (c == "}" || c == "]") depth--
		if (c !~ /[ \t\r\n]/) prev = c
		i++
	}
}' || exit 0

field() { [ -f "$fields/$1" ] && cat "$fields/$1"; }
tab=$(printf '\t')
agent=$(field agent_type)
agent=${agent#pr-review-workflow:}
tool=$(field tool_name)
cwd=$(field cwd)

real() {
	# real <dir>: the directory with every symlink resolved, or nothing
	CDPATH= cd -P -- "$1" 2>/dev/null && pwd -P
}
data=$(real "$CLAUDE_PLUGIN_DATA")
plugin=$(real "$root")
session=''
[ -n "$cwd" ] && session=$(real "$cwd")

resolve() {
	# resolve <path>: the absolute path with its existing directories
	# resolved; fails on a ".." component or a symlinked file
	p=$1
	case "$p" in
	/*) ;;
	'~'*) return 1 ;;
	*) p="$cwd/$p" ;;
	esac
	case "/$p/" in
	*/../*) return 1 ;;
	esac
	[ -L "$p" ] && [ ! -d "$p" ] && return 1
	if [ -d "$p" ]; then
		d=$p rest=''
	else
		d=${p%/*} rest=${p##*/}
		[ -n "$d" ] || d=/
	fi
	while [ ! -d "$d" ]; do
		rest="${d##*/}/$rest"
		d=${d%/*}
		[ -n "$d" ] || d=/
	done
	r=$(real "$d") || return 1
	printf '%s/%s\n' "${r%/}" "$rest"
}

under() {
	# under <resolved path> <root>...: inside one of the roots
	p=$1
	shift
	for r in "$@"; do
		[ -n "$r" ] || continue
		case "$p/" in
		"${r%/}"/*) return 0 ;;
		esac
	done
	return 1
}

in_worktree() {
	# in_worktree <resolved path>: inside a review worktree
	case "$1" in
	"$data"/wt/?*) return 0 ;;
	"$data"/state/*/worktree/*)
		rest=${1#"$data"/state/}
		case "${rest#*/}" in worktree/*) return 0 ;; esac
		;;
	esac
	return 1
}

# A session opened in the home directory, or above it, would make the
# whole home readable; the session's folder then counts for nothing.
home=''
[ -n "${HOME:-}" ] && home=$(real "$HOME")
[ -n "$home" ] && [ -n "$session" ] && under "$home" "$session" && session=''

who="pr-review-workflow:$agent"
case "$tool" in
Read | Grep | Glob)
	name=file_path
	[ "$tool" = Read ] || name=path
	if [ "$tool" = Glob ]; then
		# An absolute pattern searches where it names, whatever the path.
		pattern=$(field input_pattern)
		case "$pattern" in
		/* | '~'* | ../* | */../* | ..)
			fixed=${pattern%%[*?[{]*}
			case "$fixed" in
			*/*) fixed=${fixed%/*} ;;
			*) fixed=. ;;
			esac
			if [ "${pattern#/}" = "$pattern" ]; then
				base=$(field input_path) || base=''
				fixed="${base:-.}/$fixed"
			fi
			full=$(resolve "${fixed:-/}") && under "$full" "$data" "$plugin" "$session" ||
				decide "$who reads only the plugin's data directory (the state directory, its worktree and context), the plugin itself, and the session's folder."
			;;
		esac
	fi
	[ -f "$fields/input_$name" ] || exit 0
	path=$(field "input_$name")
	[ -n "$path" ] || exit 0
	full=$(resolve "$path") || decide "$who reads no symlinked file and no path through \"..\"; read the file the link names, inside the review."
	under "$full" "$data" "$plugin" "$session" ||
		decide "$who reads only the plugin's data directory (the state directory, its worktree and context), the plugin itself, and the session's folder."
	exit 0
	;;
Edit | Write | MultiEdit | NotebookEdit)
	name=file_path
	[ "$tool" = NotebookEdit ] && name=notebook_path
	path=$(field "input_$name")
	full=$(resolve "$path") && in_worktree "$full" ||
		decide "$who edits files only inside the review worktree, worktree/<path> in the state directory."
	exit 0
	;;
Bash) ;;
*) exit 0 ;;
esac

scripts='' subs='' statuses='' leases=0
case "$agent" in
editor)
	scripts='run-contract append-note reply-thread push-branch update-finding sync-branch'
	subs='add commit diff show log status rev-parse'
	statuses='addressed wont-fix'
	;;
verifier)
	scripts='run-contract update-finding resolve-thread append-note reply-thread'
	subs='show log diff status rev-parse'
	statuses='verified open'
	;;
filter)
	scripts='update-finding append-note'
	subs='show log diff status rev-parse'
	;;
cartographer)
	scripts='save-record'
	;;
esac
[ -n "$scripts$subs" ] || decide "$who runs no shell commands; it works through Read, Grep, and Glob."
allowed="sh $root/scripts/<name>.sh <state-dir> ... for: $scripts"
[ -z "$subs" ] || allowed="$allowed; git -C <path in the state directory> for: $subs"
field input_command >"$fields/command"

verdict=$(awk -v file="$fields/command" -v root="$root" -v scripts=" $scripts " -v subs=" $subs " \
	-v statuses=" $statuses " -v agent="$agent" '
function deny(r) { print "deny " r; failed = 1; exit }
function swap(s, lit, rep,    out, k) {
	out = ""
	while ((k = index(s, lit)) > 0) { out = out substr(s, 1, k - 1) rep; s = substr(s, k + length(lit)) }
	return out s
}
function endword() {
	if (!inword) return
	nw[nseg]++
	W[nseg, nw[nseg]] = w
	w = ""; inword = 0
}
function script(seg, stdin_ok,    p, name, k, a) {
	if (W[seg, 1] != "sh") deny("a command other than git or a plugin script")
	p = W[seg, 2]
	if (index(p, root "/scripts/") != 1) deny("a script outside the plugin")
	name = substr(p, length(root "/scripts/") + 1)
	if (name !~ /^[a-z-]+\.sh$/) deny("a script outside the plugin")
	sub(/\.sh$/, "", name)
	if (index(scripts, " " name " ") == 0) deny(name ".sh, which this agent does not run")
	if (stdin_ok && name != "append-note" && name != "reply-thread" && name != "save-record") deny("input piped into " name ".sh")
	if (nw[seg] < 3) deny(name ".sh without its directory")
	print "dir\t" W[seg, 3]
	for (k = 4; k <= nw[seg]; k++) {
		a = W[seg, k]
		if (name == "update-finding" && a ~ /^status=/ && index(statuses, " " substr(a, 8) " ") == 0)
			deny("a status change to " substr(a, 8) ", which is not this agent\047s to make")
		if (name == "push-branch" && a != "") deny("push-branch.sh with " a)
		if (name == "sync-branch" && a != "--continue") deny("sync-branch.sh with " a)
	}
}
function git(    k, v, sub_, a) {
	if (nw[1] < 4 || W[1, 2] != "-C") deny("git without -C <path in the state directory>")
	print "git\t" W[1, 3]
	k = 4
	while (W[1, k] == "-c") {
		v = W[1, k + 1]
		if (v !~ /^user\.(name|email)=/) deny("git -c " v)
		k += 2
	}
	sub_ = W[1, k]
	if (index(subs, " " sub_ " ") == 0) deny("git " sub_ ", which this agent does not run")
	for (k++; k <= nw[1]; k++) {
		a = W[1, k]
		if (a ~ /^--(output|no-index|ext-diff|exec|upload-pack|receive-pack|pathspec-from-file|config-env|git-dir|work-tree)/)
			deny("git " sub_ " " a)
		if (sub_ == "commit" && (a ~ /^-[A-Za-z]*[FtCc]/ || a ~ /^--(file|template|amend|reuse-message|reedit-message)/))
			deny("git commit " a)
	}
}
BEGIN {
	while ((getline line < file) > 0) s = s (nl++ ? "\n" : "") line
	s = swap(s, "${CLAUDE_PLUGIN_ROOT}", root)
	s = swap(s, "$CLAUDE_PLUGIN_ROOT/", root "/")
	L = length(s); i = 1; nseg = 1; nw[1] = 0; w = ""; inword = 0; q = ""; heredoc = 0
	while (i <= L) {
		c = substr(s, i, 1)
		if (c ~ /[\001-\010\013-\037]/) deny("a control character")
		if (q == "\047") { if (c == "\047") q = ""; else w = w c; i++; continue }
		if (q == "\"") {
			if (c == "\"") { q = ""; i++; continue }
			if (c == "$" || c == "`") deny("an expansion inside double quotes")
			if (c == "\\" && substr(s, i + 1, 1) ~ /[$`"\\]/) { w = w substr(s, i + 1, 1); i += 2; continue }
			w = w c; i++; continue
		}
		if (c == "\047" || c == "\"") { q = c; inword = 1; i++; continue }
		if (c == " " || c == "\t") { endword(); i++; continue }
		if (c == "|") {
			if (substr(s, i + 1, 1) == "|") deny("the operator ||")
			endword()
			if (nw[nseg] == 0 || nseg == 2 || heredoc) deny("a pipeline other than printf or echo into one script")
			nseg = 2; nw[2] = 0; i++; continue
		}
		if (c == "<" && substr(s, i + 1, 1) == "<" && !heredoc) {
			endword()
			i += 2
			while (substr(s, i, 1) == " ") i++
			dq = substr(s, i, 1)
			if (dq != "\047" && dq != "\"") deny("a heredoc whose delimiter is not quoted")
			rest = substr(s, i + 1)
			k = index(rest, dq)
			delim = substr(rest, 1, k - 1)
			if (k < 2 || delim !~ /^[A-Za-z0-9_]+$/) deny("a heredoc delimiter")
			i += k + 1
			nlpos = index(substr(s, i), "\n")
			if (nlpos == 0 || substr(s, i, nlpos - 1) !~ /^[ \t]*$/) deny("text after a heredoc on its line")
			body = substr(s, i + nlpos)
			# The heredoc ends at a line holding only the delimiter, and nothing follows it.
			found = 0
			while (body != "") {
				e = index(body, "\n")
				ln = (e ? substr(body, 1, e - 1) : body)
				body = (e ? substr(body, e + 1) : "")
				if (ln == delim) { found = 1; break }
			}
			if (!found || body !~ /^[ \t\n]*$/) deny("a heredoc that does not end the command")
			heredoc = 1
			break
		}
		if (c ~ /[;&<>()$`\\\n{}]/) deny("the shell operator " (c == "\n" ? "newline" : c))
		if (!inword && (c == "~" || c == "#")) deny("an unquoted " c)
		w = w c; inword = 1; i++
	}
	if (q != "") deny("an unclosed quote")
	endword()
	if (nseg == 2) {
		if (W[1, 1] != "printf" && W[1, 1] != "echo") deny("a pipeline other than printf or echo into one script")
		if (nw[2] == 0) deny("an empty pipeline")
		script(2, 1)
	} else if (W[1, 1] == "git") {
		if (heredoc) deny("a heredoc into git")
		git()
	} else if (W[1, 1] == "sh") {
		script(1, heredoc)
	} else deny("a command other than git or a plugin script")
	print "allow"
}')

reason=$(printf '%s\n' "$verdict" | sed -n 's/^deny //p' | head -n 1)
[ -z "$reason" ] || decide "$who may run only: $allowed. Refused: $reason."
printf '%s\n' "$verdict" | grep -qx allow || decide "$who may run only: $allowed. Refused: the command could not be read."
printf '%s\n' "$verdict" | sed -n -e "s/^dir$tab//p" -e "s/^git$tab//p" >"$fields/paths"
while IFS= read -r path; do
	full=$(resolve "$path") && under "$full" "$data" ||
		decide "$who may run only: $allowed. Refused: a path outside the plugin's data directory."
done <"$fields/paths"
exit 0
