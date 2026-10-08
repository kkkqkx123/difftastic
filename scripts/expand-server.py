#!/usr/bin/env python3
"""Expand a difftastic `feat` tree into a self-contained server snapshot.

The `feat` branch keeps its diff against upstream `master` minimal (only
src/lib.rs and one build.rs block) so merges stay conflict-free. Downstream
(server) builds need a little more: `pub(crate)` promoted to `pub` and the
`env!("CARGO_BIN_NAME")` macro replaced with a literal.

Like zed's expand-workspace.py, all of that mechanical complexity is closed
inside this repository: this script copies the tree faithfully and then applies
the transforms, so the snapshot branch carries the expanded result while `feat`
keeps the original text.

Vendored parser layout needs no transform: upstream already ships
`vendored_parsers/<name>/src/` with `*-src` entries as symlinks to it, and
build.rs already points there.

Transforms applied to the copy (never to the source tree):

1. Promote `pub(crate) ` to `pub ` in src/**/*.rs (except lib.rs).
2. Replace `env!("CARGO_BIN_NAME")` with `"difft"` in src/**/*.rs
   (except lib.rs and main.rs, where the macro is valid).

Usage:
    scripts/expand-server.py <source-dir> <target-dir>
"""
from __future__ import annotations

import os
import re
import shutil
import sys
from pathlib import Path

# Directories never carried into the snapshot: build output and VCS metadata.
COPY_IGNORE = ("target", ".git", "node_modules")


def copy_tree(source: Path, target: Path) -> None:
    """Copy the source tree into `target`, preserving symlinks and layout.

    The snapshot is a faithful copy of the branch minus build output and VCS
    metadata; keeping the copy faithful means new upstream files show up in
    review instead of silently vanishing.
    """
    if target.exists():
        shutil.rmtree(target)
    target.mkdir(parents=True)

    ignore = shutil.ignore_patterns(*COPY_IGNORE)

    for entry in sorted(source.iterdir()):
        if entry.name in COPY_IGNORE:
            continue
        dst = target / entry.name
        if entry.is_symlink():
            os_symlink = getattr(__import__("os"), "symlink")
            os_symlink(__import__("os").readlink(entry), dst)
        elif entry.is_dir():
            shutil.copytree(entry, dst, ignore=ignore, symlinks=True)
        else:
            shutil.copy2(entry, dst)


def rewrite_src(src: Path) -> tuple[int, int]:
    """Apply visibility promotion and the CARGO_BIN_NAME replacement.

    Returns (files touched, replacements made).
    """
    touched = 0
    replaced = 0
    for path in sorted(src.rglob("*.rs")):
        if path.name == "lib.rs":
            continue
        text = path.read_text()
        updated = text.replace("pub(crate) ", "pub ")
        # The macro is only unavailable in library targets; main.rs is a bin
        # and keeps it.
        if path.name != "main.rs":
            updated = updated.replace('env!("CARGO_BIN_NAME")', '"difft"')
        if updated != text:
            path.write_text(updated)
            touched += 1
            replaced += text.count("pub(crate) ") + text.count('env!("CARGO_BIN_NAME")')
    return touched, replaced


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2

    source, target = Path(argv[1]).resolve(), Path(argv[2]).resolve()
    if not (source / "Cargo.toml").is_file():
        print(f"error: {source} has no Cargo.toml", file=sys.stderr)
        return 1

    copy_tree(source, target)
    touched, replaced = rewrite_src(target / "src")

    print(f"expanded {source} into {target}")
    print(f"  src files touched: {touched} (visibility/macro replacements: {replaced})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
