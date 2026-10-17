#!/bin/sh
# local-diff: when the API refuses the diff, fetch-pr builds it from the clone.
set -eu

mkdir -p "$SCRATCH/Paxton-Meny"
remote="$SCRATCH/Paxton-Meny/widgets.git"
git init --quiet --bare "$remote"
clone="$SCRATCH/clone"
git clone --quiet "$remote" "$clone" 2>/dev/null
git -C "$clone" config user.name tester
git -C "$clone" config user.email tester@example.invalid
printf 'one\ntwo\nthree\nfour\nfive\nsix\nseven\neight\nnine\nten\n' >"$clone/file.txt"
printf 'keep me\n' >"$clone/old-name.txt"
git -C "$clone" add file.txt old-name.txt
git -C "$clone" commit --quiet -m "Root"
git -C "$clone" push --quiet origin HEAD:main
git -C "$clone" checkout --quiet -b feat-thing
sed -i 's/^five$/FIVE/' "$clone/file.txt"
git -C "$clone" mv old-name.txt new-name.txt
printf 'fresh\n' >"$clone/added.txt"
printf '\000\001\002' >"$clone/blob.bin"
printf 'accent\n' >"$clone/café.txt"
git -C "$clone" add -A
git -C "$clone" commit --quiet -m "Change"
git -C "$clone" push --quiet origin feat-thing
sha=$(git -C "$clone" rev-parse HEAD)
git -C "$clone" checkout --quiet main
# Hostile user configuration the diff must ignore.
git -C "$clone" config diff.noprefix true
git -C "$clone" config diff.context 1
git -C "$clone" config core.quotePath true

stub="$SCRATCH/stub"
mkdir -p "$stub"
export GH_STUB_DIR="$stub"
export PATH="$REPO_ROOT/tests/stubs:$PATH"
printf '1\n' >"$stub/pr-diff.exit"
printf 'HTTP 500: very large pull requests cannot be fetched through the API\n' >"$stub/pr-diff.err"
printf 'title Huge\nadditions 5\ndeletions 1\nchanged_files 5\nlabels \n' >"$stub/pr-view.1"
printf 'The body.\n' >"$stub/pr-view.2"

dir="$SCRATCH/data/state/Paxton-Meny__widgets__7"
mkdir -p "$dir"
printf 'owner Paxton-Meny\nrepo widgets\npr 7\nhead_branch feat-thing\nbase_branch main\nhead_sha %s\ncross_repo false\nrepo_root %s\n' "$sha" "$clone" >"$dir/meta.txt"

out=$(sh "$REPO_ROOT/scripts/fetch-pr.sh" "$dir" 2>"$SCRATCH/err")
grep -q "the API refused the diff" "$SCRATCH/err"
grep -q "fetch-pr: HTTP 500: very large" "$SCRATCH/err"
printf '%s\n' "$out" | grep -q '^local-diff: 5 files from the clone, main fresh at '
printf '%s\n' "$out" | grep -qx 'split-diff: 3 files, 10 commentable lines, 0 excluded'
printf '%s\n' "$out" | grep -qx 'fetch-pr: 5 files, 5 additions, 1 deletions, diff from the clone'
grep -qx 'diff_source clone' "$dir/pr-context/meta-full.txt"
grep -qx 'The body.' "$dir/pr-context/body.txt"
# The file list comes from the diff, not a third API call.
[ "$(grep -c '^pr view' "$stub/calls.log")" -eq 2 ]
grep -qx 'file.txt	1	1' "$dir/pr-context/files.txt"
grep -qx 'added.txt	1	0' "$dir/pr-context/files.txt"
grep -qx 'blob.bin	0	0' "$dir/pr-context/files.txt"
grep -qx 'café.txt	1	0' "$dir/pr-context/files.txt"
grep -qx 'new-name.txt	0	0' "$dir/pr-context/files.txt"
! grep -qF 'old-name' "$dir/pr-context/files.txt"
# GitHub's diff shape: a/ b/ prefixes, three context lines, unquoted paths, renames.
grep -qx '+++ b/file.txt' "$dir/pr-context/diff.patch"
grep -q '^@@ -2,7 +2,7 @@' "$dir/pr-context/diff.patch"
grep -qx '+++ b/café.txt' "$dir/pr-context/diff.patch"
grep -qx 'rename from old-name.txt' "$dir/pr-context/diff.patch"
grep -q 'Binary files /dev/null and b/blob.bin differ' "$dir/pr-context/diff.patch"
# A pure rename and a binary file have no hunks, so split-diff indexes three.
grep -qx '003	file.txt' "$dir/pr-context/diff-index.txt"

# A head the clone lacks arrives through refs/pull/<n>/head, as on GitHub
# after the fork is deleted.
work="$SCRATCH/work"
git clone --quiet "$remote" "$work" 2>/dev/null
git -C "$work" config user.name author
git -C "$work" config user.email author@example.invalid
git -C "$work" checkout --quiet -b feat-pull origin/main
printf 'eleven\n' >>"$work/file.txt"
git -C "$work" commit --quiet -am "Pull change"
git -C "$work" push --quiet origin HEAD:refs/pull/8/head
pull_sha=$(git -C "$work" rev-parse HEAD)
rm -rf "$work"
pdir="$SCRATCH/data/state/Paxton-Meny__widgets__8"
mkdir -p "$pdir"
printf 'owner Paxton-Meny\nrepo widgets\npr 8\nhead_branch feat-pull\nbase_branch main\nhead_sha %s\ncross_repo true\nhead_repo_url \nrepo_root %s\n' "$pull_sha" "$clone" >"$pdir/meta.txt"
out=$(sh "$REPO_ROOT/scripts/local-diff.sh" "$pdir")
printf '%s\n' "$out" | grep -q '^local-diff: 1 files from the clone'
grep -qx 'file.txt	1	0' "$pdir/pr-context/files.txt"
grep -qx '+eleven' "$pdir/pr-context/diff.patch"

# A rename that drops or adds a directory segment lists the plain new path.
work="$SCRATCH/work2"
git clone --quiet "$remote" "$work" 2>/dev/null
git -C "$work" config user.name author
git -C "$work" config user.email author@example.invalid
git -C "$work" checkout --quiet -b base2 origin/main
mkdir -p "$work/a/b" "$work/sub"
printf 'x\n' >"$work/a/b/x.txt"
printf 'deep\n' >"$work/sub/deep.txt"
printf 'moved\n' >"$work/up.txt"
git -C "$work" add -A
git -C "$work" commit --quiet -m "Base two"
git -C "$work" push --quiet origin base2
git -C "$work" checkout --quiet -b feat-rename
git -C "$work" mv a/b/x.txt a/x.txt
git -C "$work" mv sub/deep.txt deep.txt
mkdir -p "$work/newdir"
git -C "$work" mv up.txt newdir/up.txt
git -C "$work" commit --quiet -m "Move files"
git -C "$work" push --quiet origin HEAD:refs/pull/10/head
rename_sha=$(git -C "$work" rev-parse HEAD)
rm -rf "$work"
printf 'owner Paxton-Meny\nrepo widgets\npr 10\nhead_branch feat-rename\nbase_branch base2\nhead_sha %s\ncross_repo true\nhead_repo_url \nrepo_root %s\n' "$rename_sha" "$clone" >"$pdir/meta.txt"
sh "$REPO_ROOT/scripts/local-diff.sh" "$pdir" >/dev/null
grep -qx 'a/x.txt	0	0' "$pdir/pr-context/files.txt"
grep -qx 'deep.txt	0	0' "$pdir/pr-context/files.txt"
grep -qx 'newdir/up.txt	0	0' "$pdir/pr-context/files.txt"
! grep -q '//' "$pdir/pr-context/files.txt"

# A gone fork with no pull request ref is exit 2.
printf 'owner Paxton-Meny\nrepo widgets\npr 9\nhead_branch feat-gone\nbase_branch main\nhead_sha 0123456789012345678901234567890123456789\ncross_repo true\nhead_repo_url \nrepo_root %s\n' "$clone" >"$pdir/meta.txt"
rc=0
sh "$REPO_ROOT/scripts/local-diff.sh" "$pdir" 2>"$SCRATCH/err" || rc=$?
[ "$rc" -eq 2 ]
grep -q "fork this pull request comes from is gone" "$SCRATCH/err"

# A head nobody serves is exit 1.
printf 'owner Paxton-Meny\nrepo widgets\npr 9\nhead_branch feat-gone\nbase_branch main\nhead_sha 0123456789012345678901234567890123456789\ncross_repo false\nrepo_root %s\n' "$clone" >"$pdir/meta.txt"
rc=0
sh "$REPO_ROOT/scripts/local-diff.sh" "$pdir" 2>"$SCRATCH/err" || rc=$?
[ "$rc" -eq 1 ]
grep -q "could not be fetched" "$SCRATCH/err"

# A base branch the remote lacks is exit 1.
printf 'owner Paxton-Meny\nrepo widgets\npr 7\nhead_branch feat-thing\nbase_branch nope\nhead_sha %s\ncross_repo false\nrepo_root %s\n' "$sha" "$clone" >"$pdir/meta.txt"
rc=0
sh "$REPO_ROOT/scripts/local-diff.sh" "$pdir" 2>"$SCRATCH/err" || rc=$?
[ "$rc" -eq 1 ]
grep -q "base branch nope" "$SCRATCH/err"

# A clone of some other repository is refused.
git -C "$clone" remote set-url origin "$SCRATCH/Paxton-Meny/widgets-evil.git"
printf 'owner Paxton-Meny\nrepo widgets\npr 7\nhead_branch feat-thing\nbase_branch main\nhead_sha %s\ncross_repo false\nrepo_root %s\n' "$sha" "$clone" >"$pdir/meta.txt"
rc=0
sh "$REPO_ROOT/scripts/local-diff.sh" "$pdir" 2>"$SCRATCH/err" || rc=$?
[ "$rc" -eq 1 ]
grep -q "not Paxton-Meny/widgets" "$SCRATCH/err"

# The whole fetch fails loudly when the clone cannot help either.
rm -rf "$dir/pr-context"
printf '1\n' >"$stub/pr-diff.exit"
printf 'title Huge\nadditions 5\ndeletions 1\nchanged_files 5\nlabels \n' >"$stub/pr-view.1"
cp "$pdir/meta.txt" "$dir/meta.txt"
if sh "$REPO_ROOT/scripts/fetch-pr.sh" "$dir" 2>"$SCRATCH/err"; then
	echo "expected failure when neither the API nor the clone has the diff" >&2
	exit 1
fi
grep -q "the clone could not supply it" "$SCRATCH/err"
[ ! -f "$dir/pr-context/diff.patch" ]

# A head branch shaped like an option stays a branch name.
printf '#!/bin/sh\n: >"%s"\nexec git-upload-pack "$@"\n' "$SCRATCH/pwned" >"$SCRATCH/evil.sh"
chmod +x "$SCRATCH/evil.sh"
rm -rf "$SCRATCH/clone2"
git clone --quiet "$remote" "$SCRATCH/clone2" 2>/dev/null
git -C "$clone" checkout --quiet feat-thing
printf 'later\n' >>"$clone/file.txt"
git -C "$clone" commit --quiet -am "Later"
later=$(git -C "$clone" rev-parse HEAD)
git -C "$clone" checkout --quiet main
git -C "$SCRATCH/clone2" cat-file -e "$later^{commit}" 2>/dev/null && exit 1
printf 'owner Paxton-Meny\nrepo widgets\npr 8\nhead_branch --upload-pack=%s\nbase_branch main\nhead_sha %s\ncross_repo false\nrepo_root %s\n' \
	"$SCRATCH/evil.sh" "$later" "$SCRATCH/clone2" >"$dir/meta.txt"
sh "$REPO_ROOT/scripts/local-diff.sh" "$dir" >/dev/null 2>&1 || true
[ ! -e "$SCRATCH/pwned" ]

# The same holds when the head branch is fetched from another repository.
printf '#!/bin/sh\n: >"%s"\nexec git-upload-pack "$@"\n' "$SCRATCH/pwned2" >"$SCRATCH/evil2.sh"
chmod +x "$SCRATCH/evil2.sh"
rm -rf "$SCRATCH/clone3"
git clone --quiet "$remote" "$SCRATCH/clone3" 2>/dev/null
git -C "$SCRATCH/clone3" cat-file -e "$later^{commit}" 2>/dev/null && exit 1
printf 'owner Paxton-Meny\nrepo widgets\npr 8\nhead_branch --upload-pack=%s\nbase_branch main\nhead_sha %s\ncross_repo true\nhead_repo_url %s\nrepo_root %s\n' \
	"$SCRATCH/evil2.sh" "$later" "$remote" "$SCRATCH/clone3" >"$dir/meta.txt"
sh "$REPO_ROOT/scripts/local-diff.sh" "$dir" >/dev/null 2>&1 || true
[ ! -e "$SCRATCH/pwned2" ]
