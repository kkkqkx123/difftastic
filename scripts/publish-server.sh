#!/usr/bin/env zsh
# 将 feat 分支展开为 server 快照分支(默认 server)。
#
# 背景: feat 分支只保留最小差异(src/lib.rs + build.rs 的
# CARGO_BIN_NAME 设置), 使与上游 master 的合并几乎无冲突。server 构建
# 需要的机械性修改(pub(crate) -> pub、env!("CARGO_BIN_NAME") 替换)
# 由 scripts/expand-server.py 在快照层完成, 全部复杂度封闭在本仓库内,
# server 侧只消费展开后的结果。
#
# 用法:
#   scripts/publish-server.sh            # 从 feat 生成/更新 server 快照
#   scripts/publish-server.sh --dry-run  # 只构建快照树并报告, 不移动分支
#   scripts/publish-server.sh --push     # 生成后推送到 origin/server
#   scripts/publish-server.sh <branch>   # 从其他分支生成, 默认 feat
set -euo pipefail

PUSH=false
DRY_RUN=false
SRC=feat/lib
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

DST="server"
SRC_SUBJECT="$(git log -1 --format=%s "$SRC")"
PARENT="$(git rev-parse -q --verify "refs/heads/$DST" 2>/dev/null || true)"

SCRIPT_DIR="$REPO_ROOT/scripts"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 1. 把 SRC 的树导出到 WORK/tree(git archive 不含 .git, 与快照语义一致)。
mkdir -p "$WORK/tree"
git archive "$SRC" | tar -x -C "$WORK/tree"

# 2. 应用机械性修改, 结果写入 WORK/expanded。
python3 "$SCRIPT_DIR/expand-server.py" "$WORK/tree" "$WORK/expanded"

# 3. 用临时索引把展开后的目录写成树对象。
#    在 expanded 目录内以相对路径建索引, 保证写入的路径干净(不带临时前缀);
#    GIT_DIR 必须显式指定, 因为 cd 到临时目录后 git 找不到仓库。
(
  cd "$WORK/expanded"
  export GIT_INDEX_FILE="$WORK/index" GIT_DIR="$REPO_ROOT/.git" GIT_WORK_TREE="$WORK/expanded"
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
    echo "server is already up to date with $SRC (tree unchanged)."
    exit 0
  fi
  NEW="$(git commit-tree "$TREE" -p "$PARENT" -m "$SRC_SUBJECT")"
else
  NEW="$(git commit-tree "$TREE" -m "Snapshot of feat expanded for server builds

History trimmed: this branch starts from a tree snapshot of the feat
branch and carries no upstream difftastic history. Mechanical
transforms for library consumption (visibility promotion,
CARGO_BIN_NAME replacement) are applied by scripts/expand-server.py;
see the script header for details.")"
fi

git update-ref "refs/heads/$DST" "$NEW"
echo "server -> $(git rev-parse --short "$NEW")  $SRC_SUBJECT"

if $PUSH; then
  git push origin "$DST"
fi
