#!/usr/bin/env bash
# 同步 master 分支到上游 Wilfred/difftastic 的最新提交。
# 用法: scripts/sync-master.sh [--push]
#
# 策略: master 跟踪上游 master, 始终 fast-forward, 不产生本地提交。
set -euo pipefail

PUSH=false
[[ "${1:-}" == "--push" ]] && PUSH=true

UPSTREAM_URL="https://github.com/Wilfred/difftastic.git"
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

if ! git remote get-url upstream >/dev/null 2>&1; then
  git remote add upstream "$UPSTREAM_URL"
  echo "Added upstream remote: $UPSTREAM_URL"
fi

CURRENT_BRANCH="$(git branch --show-current)"

git checkout master
git fetch upstream main 2>/dev/null || git fetch upstream master
UPSTREAM_REF="$(git rev-parse --verify -q refs/remotes/upstream/main >/dev/null && echo upstream/main || echo upstream/master)"

BEHIND="$(git rev-list --count master.."$UPSTREAM_REF")"
if [[ "$BEHIND" -eq 0 ]]; then
  echo "master is already up to date with $UPSTREAM_REF."
else
  echo "master is $BEHIND commit(s) behind $UPSTREAM_REF, fast-forwarding..."
  git merge --ff-only "$UPSTREAM_REF"
  $PUSH && git push origin master
fi

if [[ "$CURRENT_BRANCH" != "master" ]]; then
  git checkout "$CURRENT_BRANCH"
fi
echo "Done."
