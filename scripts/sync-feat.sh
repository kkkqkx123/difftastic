#!/usr/bin/env zsh
# 将 master 的变更合并进 feat/lib 分支。
#
# feat/lib 相对 master 只保留一个最小差异: 新增 src/lib.rs 与 build.rs 中的
# 一段 CARGO_BIN_NAME 环境变量设置。合并冲突面极小; 出现冲突时停下来
# 手动处理, 解决后 `git rebase --continue` / `git merge --continue`。
#
# 用法:
#   scripts/sync-feat.sh            # rebase master 之上的唯一 feat/lib 提交
#   scripts/sync-feat.sh --merge    # 用 merge 代替 rebase
#   scripts/sync-feat.sh --push      # 同步后推送到 origin/feat/lib
set -euo pipefail

PUSH=false
MODE="rebase"
for arg in "$@"; do
  case "$arg" in
    --push)  PUSH=true ;;
    --merge) MODE="merge" ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

git checkout feat/lib

BEHIND="$(git rev-list --count feat/lib..master)"
if [[ "$BEHIND" -eq 0 ]]; then
  echo "feat/lib is already up to date with master."
else
  echo "feat/lib is $BEHIND commit(s) behind master, syncing via $MODE..."
  if [[ "$MODE" == "rebase" ]]; then
    git rebase master
  else
    git merge master --no-edit
  fi
  $PUSH && git push origin feat/lib
fi
echo "Done."
