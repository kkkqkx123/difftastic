// Clippy errors in this file should not stop build errors being
// reported elsewhere.
// https://github.com/rust-lang/rust-clippy/issues/9534
#![warn(clippy::all)]
// Has false positives on else if chains that sometimes have the same
// body for readability.
#![allow(clippy::if_same_then_else)]

use std::path::PathBuf;
use std::process::Command;

use rayon::prelude::*;
use version_check as rustc;

struct TreeSitterParser {
    name: &'static str,
    src_dir: &'static str,
    extra_files: Vec<&'static str>,
    has_parser_c: bool,
}

impl TreeSitterParser {
    fn build(&self) {
        let dir = PathBuf::from(&self.src_dir);

        let mut c_files: Vec<&str> = Vec::new();
        if self.has_parser_c {
            c_files.push("src/parser.c");
        }
        c_files.extend_from_slice(&self.extra_files);

        if c_files.is_empty() {
            return;
        }

        let mut build = cc::Build::new();
        if cfg!(target_env = "msvc") {
            build.flag("/utf-8");
        }
        build.include(&dir).include(dir.join("src")).warnings(false); // ignore unused parameter warnings
        for file in &c_files {
            build.file(dir.join(file));
        }

        build.link_lib_modifier("+whole-archive");

        build.compile(self.name);
    }
}

fn main() {
    let parsers = vec![
        TreeSitterParser {
            name: "tree-sitter-elvish",
            src_dir: "vendored_parsers/tree-sitter-elvish",
            extra_files: vec![],
            has_parser_c: true,
        },
        TreeSitterParser {
            name: "tree-sitter-hare",
            src_dir: "vendored_parsers/tree-sitter-hare",
            extra_files: vec![],
            has_parser_c: true,
        },
        TreeSitterParser {
            name: "tree-sitter-janet-simple",
            src_dir: "vendored_parsers/tree-sitter-janet-simple",
            extra_files: vec!["src/scanner.c"],
            has_parser_c: true,
        },
        TreeSitterParser {
            name: "tree-sitter-kotlin",
            src_dir: "vendored_parsers/tree-sitter-kotlin",
            extra_files: vec!["src/scanner.c"],
            has_parser_c: true,
        },
        TreeSitterParser {
            name: "tree-sitter-latex",
            src_dir: "vendored_parsers/tree-sitter-latex",
            extra_files: vec!["src/scanner.c"],
            has_parser_c: true,
        },
        TreeSitterParser {
            name: "tree-sitter-smali",
            src_dir: "vendored_parsers/tree-sitter-smali",
            extra_files: vec!["src/scanner.c"],
            has_parser_c: true,
        },
        TreeSitterParser {
            name: "tree-sitter-scss",
            src_dir: "vendored_parsers/tree-sitter-scss",
            extra_files: vec!["src/scanner.c"],
            has_parser_c: true,
        },
    ];

    // Only rerun if relevant files in the vendored_parsers/ directory change.
    for parser in &parsers {
        println!("cargo:rerun-if-changed={}", parser.src_dir);
    }

    parsers.par_iter().for_each(|p| p.build());
    commit_info();

    if let Some((version, _, _)) = rustc::triple() {
        println!("cargo:rustc-env=DFT_RUSTC_VERSION={}", version);
    }
}

fn commit_info() {
    if !PathBuf::from(".git").exists() {
        return;
    }

    let output = match Command::new("git")
        .arg("log")
        .arg("-1")
        .arg("--date=short")
        .arg("--format=%H %h %cd")
        .output()
    {
        Ok(output) if output.status.success() => output,
        _ => return,
    };
    let stdout = String::from_utf8(output.stdout).unwrap();
    let mut parts = stdout.split_whitespace();
    let mut next = || parts.next().unwrap();
    let _commit_hash = next();
    println!("cargo:rustc-env=DFT_COMMIT_SHORT_HASH={}", next());
    println!("cargo:rustc-env=DFT_COMMIT_DATE={}", next())
}
