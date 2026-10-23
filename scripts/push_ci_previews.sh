#!/usr/bin/env bash
# Puts files on the ci-previews branch (where Claude reads CI results) — as ONE commit with no history.
#
# 2026-10-23: the branch had kept every run's pictures and videos since 10/16 in its history, and the repository went
# over GitHub's size quota (pushes refused: "Repository is above its size quota"). Now each publish builds a fresh
# commit with no parent (git commit-tree) holding the branch's current files plus this run's, and force-pushes it: the
# branch is always a single commit, and what a run replaced becomes unreachable, so GitHub's cleanup can drop it.
# `--force-with-lease` keeps a run that pushed in between from being overwritten: the push fails and we retry from a
# fresh clone. The clone takes no file contents (--filter=blob:none, sparse checkout of DEST_DIR only), so it is fast
# however many runs the branch holds.
#
# Usage: push_ci_previews.sh REPO_URL DEST_DIR "commit message" FILE_OR_DIR...
#   DEST_DIR is replaced (its old files go away); a directory argument is copied by its contents.
set -uo pipefail
url="$1"; dest="$2"; msg="$3"; shift 3
export GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-ci-previews}" GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-ci-previews@users.noreply.github.com}"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME" GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
for attempt in 1 2 3 4 5; do
  work="$(mktemp -d)"
  lease=""
  if git clone --quiet --depth 1 --filter=blob:none --no-checkout --branch ci-previews "$url" "$work" 2>/dev/null; then
    ( cd "$work" && git sparse-checkout set --no-cone "/$dest/" && git checkout --quiet ci-previews ) || { rm -rf "$work"; sleep 3; continue; }
    lease="$(git -C "$work" rev-parse HEAD)"
  else
    # No branch yet (or it was deleted): start it from nothing.
    git init --quiet "$work" && git -C "$work" remote add origin "$url"
  fi
  rm -rf "$work/$dest" && mkdir -p "$work/$dest"
  for src in "$@"; do
    if [ -d "$src" ]; then cp -R "$src"/. "$work/$dest/"; elif [ -f "$src" ]; then cp "$src" "$work/$dest/"; fi
  done
  cd "$work"
  git add -A
  if [ -n "$lease" ] && git diff --quiet --cached HEAD -- 2>/dev/null; then
    cd - >/dev/null; rm -rf "$work"; exit 0   # nothing changed
  fi
  tree="$(git write-tree)"
  commit="$(git commit-tree "$tree" -m "$msg")"
  if [ -n "$lease" ]; then
    git push --quiet --force-with-lease="refs/heads/ci-previews:$lease" origin "$commit:refs/heads/ci-previews" && { cd - >/dev/null; rm -rf "$work"; exit 0; }
  else
    git push --quiet origin "$commit:refs/heads/ci-previews" && { cd - >/dev/null; rm -rf "$work"; exit 0; }
  fi
  cd - >/dev/null
  rm -rf "$work"
  echo "ci-previews: attempt $attempt failed, retrying"
  sleep $(( attempt * 4 + RANDOM % 5 ))
done
echo "::warning::ci-previews に置けませんでした（他のワークフローと重なった可能性）。結果は実行の Summary にあります。"
exit 0
