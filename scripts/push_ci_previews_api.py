#!/usr/bin/env python3
"""Puts one run's files on the ci-previews branch through the GitHub API, without cloning the branch.

Usage: push_ci_previews_api.py OWNER/REPO DEST_DIR "commit message" FILE...   (token in GITHUB_TOKEN)

Why: on 2026-10-25 even a tree-only clone of ci-previews (`--filter=blob:none`, in push_ci_previews.sh) took over
five minutes, and three runs in a row were stopped at the step's 12-minute limit before anything was pushed. Here
only this run's files are sent: each file becomes a blob, DEST_DIR is replaced by a new tree made of them, and the
rest of the branch is reused on the server (`base_tree`). The branch stays one commit with no parent, like
push_ci_previews.sh. Recordings (.mp4/.mov) never go here. Never fails the job (prints a warning instead).
"""
import base64
import concurrent.futures
import json
import os
import sys
import time
import urllib.error
import urllib.request

API = "https://api.github.com"
BRANCH = "ci-previews"


def call(method, path, body=None, token=None):
    data = json.dumps(body).encode() if body is not None else None
    for attempt in range(5):
        req = urllib.request.Request(API + path, data=data, method=method)
        req.add_header("Authorization", f"Bearer {token}")
        req.add_header("Accept", "application/vnd.github+json")
        req.add_header("X-GitHub-Api-Version", "2022-11-28")
        if data is not None:
            req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.loads(r.read() or b"null")
        except urllib.error.HTTPError as e:
            if e.code == 404 or e.code == 422 or attempt == 4:
                raise
        except (urllib.error.URLError, TimeoutError):
            if attempt == 4:
                raise
        time.sleep(2 * (attempt + 1))
    raise RuntimeError("unreachable")


def subtree_sha(tree_sha, name, repo, token):
    """The sha of the directory `name` directly inside the tree, or None."""
    t = call("GET", f"/repos/{repo}/git/trees/{tree_sha}", token=token)
    for e in t.get("tree", []):
        if e["path"] == name and e["type"] == "tree":
            return e["sha"]
    return None


def main():
    repo, dest, msg, *paths = sys.argv[1:]
    token = os.environ.get("GITHUB_TOKEN", "")
    files = [p for p in paths if os.path.isfile(p) and not p.lower().endswith((".mp4", ".mov"))]
    if not token or not files:
        print("ci-previews: nothing to put (no token or no files)")
        return

    def blob(path):
        with open(path, "rb") as f:
            content = base64.b64encode(f.read()).decode()
        sha = call("POST", f"/repos/{repo}/git/blobs", {"content": content, "encoding": "base64"}, token)["sha"]
        return {"path": os.path.basename(path), "mode": "100644", "type": "blob", "sha": sha}

    started = time.time()
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        entries = list(pool.map(blob, files))
    print(f"ci-previews: {len(entries)} blobs in {time.time() - started:.0f}s")
    leaf = call("POST", f"/repos/{repo}/git/trees", {"tree": entries}, token)["sha"]

    parts = [p for p in dest.strip("/").split("/") if p]
    for attempt in range(5):
        try:
            ref = call("GET", f"/repos/{repo}/git/ref/heads/{BRANCH}", token=token)
            old = ref["object"]["sha"]
            root = call("GET", f"/repos/{repo}/git/commits/{old}", token=token)["tree"]["sha"]
        except urllib.error.HTTPError as e:
            if e.code != 404:
                raise
            old, root = None, None
        # Walk down DEST_DIR's parents on the current branch, then rebuild them bottom-up around the new leaf.
        chain = [root]
        for name in parts[:-1]:
            chain.append(subtree_sha(chain[-1], name, repo, token) if chain[-1] else None)
        sha = leaf
        for depth in range(len(parts) - 1, -1, -1):
            body = {"tree": [{"path": parts[depth], "mode": "040000", "type": "tree", "sha": sha}]}
            if chain[depth]:
                body["base_tree"] = chain[depth]
            sha = call("POST", f"/repos/{repo}/git/trees", body, token)["sha"]
        commit = call("POST", f"/repos/{repo}/git/commits", {"message": msg, "tree": sha, "parents": []}, token)["sha"]
        # The branch is one commit with no parent, so the update is a forced one. Read the ref again just before:
        # another run that moved it meanwhile would lose its files, so rebuild on top of that run instead.
        now = call("GET", f"/repos/{repo}/git/ref/heads/{BRANCH}", token=token)["object"]["sha"] if old else None
        if now != old:
            print(f"ci-previews: moved by another run, attempt {attempt + 1}")
            continue
        if old:
            call("PATCH", f"/repos/{repo}/git/refs/heads/{BRANCH}", {"sha": commit, "force": True}, token)
        else:
            call("POST", f"/repos/{repo}/git/refs", {"ref": f"refs/heads/{BRANCH}", "sha": commit}, token)
        print(f"ci-previews: {dest} → {commit[:7]} in {time.time() - started:.0f}s")
        return
    print("::warning::ci-previews に置けませんでした（他の実行と重なり続けた）。結果は artifact にあります。")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # never fail the job over the previews
        print(f"::warning::ci-previews に置けませんでした: {e}")
