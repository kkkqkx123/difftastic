#!/usr/bin/env zsh
# 将 feat 分支发布为 lean 快照分支(默认 lean)。
#
# 背景: feat 与上游 master 共享全部历史(仓库 pack ~1.6 GiB)。
# 使用者克隆 feat 会被迫下载完整上游 difftastic 历史。lean 分支是一条
# 孤儿根起点的线性快照链: 每个快照是当次 feat 树的单父提交, 不含上游
# 历史对象。将 lean 设为仓库默认分支后, 使用者克隆/拉取默认只下载
# lean 内容; git 对未变化的 blob/tree 去重, 后续增量拉取只传输有变化
# 的部分。
#
# 与 publish-server.sh 的区别: lean 是纯"精简历史"快照, 树与 feat 完全
# 一致(无任何展开/改写), 不引入新对象(全部去重命中)。server 快照的
# 展开变换(pub(crate) -> pub 等)不适用于 lean。
#
# 用法:
#   scripts/publish-lean.sh            # 从 feat 生成/更新 lean 快照
#   scripts/publish-lean.sh --dry-run  # 只构建快照树并报告, 不移动分支
#   scripts/publish-lean.sh --push     # 生成后推送到 origin/lean
#   scripts/publish-lean.sh <branch>   # 从其他分支生成, 默认 feat
set -euo pipefail

PUSH=false
DRY_RUN=false
SRC="feat"
for arg in "$@"; do
  case "$arg" in
    --push) PUSH=true ;;
    --dry-run) DRY_RUN=true ;;
    -*) echo "Unknown option: $arg" >&2; exit 2 ;;
    *) SRC="$arg" ;;
  esac
done

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

DST="lean"
SRC_SUBJECT="$(git log -1 --format=%s "$SRC")"
PARENT="$(git rev-parse -q --verify "refs/heads/$DST" 2>/dev/null || true)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 1. 把 SRC 的树导出到 WORK/tree(git archive 不含 .git, 与快照语义一致)。
#    lean 不做任何展开变换, 导出即快照内容。
mkdir -p "$WORK/tree"
git archive "$SRC" | tar -x -C "$WORK/tree"

# 2. 用临时索引把目录写成树对象。
#    在 tree 目录内以相对路径建索引, 保证写入的路径干净(不带临时前缀);
#    GIT_DIR 必须显式指定, 因为 cd 到临时目录后 git 找不到仓库。
(
  cd "$WORK/tree"
  export GIT_INDEX_FILE="$WORK/index" GIT_DIR="$REPO_ROOT/.git" GIT_WORK_TREE="$WORK/tree"
  git read-tree --empty
  # -f: the tree carries vendored parsers' own .gitignore files (they ignore
  # generated src/parser.c); the snapshot must keep every file we copied.
  git add -Af -- .
  git write-tree > "$WORK/tree-id"
)
TREE="$(cat "$WORK/tree-id")"

if $DRY_RUN; then
  echo "dry run: snapshot tree $TREE"
  echo "  files: $(git ls-tree -r "$TREE" | wc -l | tr -d ' ')"
  if [[ -n "$PARENT" ]]; then
    echo "  current $DST tree: $(git rev-parse "${DST}^{tree}")"
  fi
  exit 0
fi

if [[ -n "$PARENT" ]]; then
  if [[ "$TREE" == "$(git rev-parse "${DST}^{tree}")" ]]; then
    echo "lean is already up to date with $SRC (tree unchanged)."
    exit 0
  fi
  NEW="$(git commit-tree "$TREE" -p "$PARENT" -m "$SRC_SUBJECT")"
else
  NEW="$(git commit-tree "$TREE" -m "Snapshot of feat

History trimmed: this branch starts from a tree snapshot of the feat
branch and carries no upstream difftastic history, so cloning downloads
only the trimmed content. The tree is identical to feat (no transforms
applied); see scripts/publish-lean.sh.")"
fi

git update-ref "refs/heads/$DST" "$NEW"
echo "lean -> $(git rev-parse --short "$NEW")  $SRC_SUBJECT"

if $PUSH; then
  git push origin "$DST"
fi
