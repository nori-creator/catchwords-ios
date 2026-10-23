#!/usr/bin/env bash
# Puts files on the ci-previews branch (where Claude reads CI results).
# Usage: push_ci_previews.sh REPO_URL DEST_DIR "commit message" FILE...
#   CI_PREVIEWS_REPLACE=1  empties DEST_DIR first (a run's own folder, so files from an older run do not linger).
#
# The branch is always ONE commit with no parent: the new files are written over the last tree and the branch is
# force-moved to it. Keeping every run in history grew the old repository past GitHub's size quota (about 100 GB
# of screenshots and recordings, 2026-10-23) and stopped every push. Recordings (.mp4/.mov) never go here; they
# stay in the run's artifact. Only the trees of the last commit are fetched (no images), so this takes seconds.
set -uo pipefail
url="$1"; dest="$2"; msg="$3"; shift 3
files=()
for f in "$@"; do
  case "$f" in *.mp4|*.mov|*.MP4|*.MOV) continue ;; esac
  [ -f "$f" ] && files+=("$(cd "$(dirname "$f")" && pwd)/$(basename "$f")")
done

for attempt in 1 2 3 4 5; do
  work="$(mktemp -d)"
  # Each step is checked by hand: `set -e` does not apply inside a ( … ) whose status is tested.
  (
    old=""
    if git clone --quiet --depth 1 --filter=blob:none --no-checkout --branch ci-previews "$url" "$work" 2>/dev/null; then
      cd "$work" || exit 1
      old="$(git rev-parse HEAD)" || exit 1
    else
      git init --quiet "$work" && cd "$work" && git remote add origin "$url" || exit 1
    fi
    export GIT_INDEX_FILE="$work/.git/ci-previews-index"
    if [ -n "$old" ]; then git read-tree "$old" || exit 1; else git read-tree --empty || exit 1; fi
    if [ "${CI_PREVIEWS_REPLACE:-0}" = "1" ]; then git rm -r -q --cached --ignore-unmatch -- "$dest" || exit 1; fi
    for f in ${files[@]+"${files[@]}"}; do
      blob="$(git hash-object -w -- "$f")" || exit 1
      git update-index --add --cacheinfo "100644,$blob,$dest/$(basename "$f")" || exit 1
    done
    tree="$(git write-tree)" || exit 1
    if [ -n "$old" ] && [ "$tree" = "$(git rev-parse "$old^{tree}")" ]; then exit 0; fi   # nothing changed
    commit="$(git -c user.name="ci-previews" -c user.email="ci-previews@users.noreply.github.com" commit-tree "$tree" -m "$msg")" || exit 1
    if [ -n "$old" ]; then
      git push --quiet --force-with-lease="refs/heads/ci-previews:$old" origin "$commit:refs/heads/ci-previews"
    else
      git push --quiet origin "$commit:refs/heads/ci-previews"
    fi
  ) && { rm -rf "$work"; exit 0; }
  rm -rf "$work"
  echo "ci-previews: attempt $attempt failed, retrying"
  sleep $(( attempt * 4 + RANDOM % 5 ))
done
echo "::warning::ci-previews に置けませんでした（他のワークフローと重なった可能性）。結果は実行の Summary と artifact にあります。"
exit 0
