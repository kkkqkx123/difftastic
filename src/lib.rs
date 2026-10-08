//! Difftastic core library - public API for difftastic functionality.
//!
//! This crate provides the core diff engine, parsing, and display
//! functionality from difftastic, exposed as a library.

#![allow(renamed_and_removed_lints)]
#![allow(clippy::type_complexity)]
#![allow(clippy::comparison_to_empty)]
#![allow(clippy::too_many_arguments)]
#![allow(clippy::if_same_then_else)]
#![allow(clippy::mutable_key_type)]
#![allow(unknown_lints)]
#![allow(clippy::manual_unwrap_or_default)]
#![allow(clippy::implicit_saturating_sub)]
#![allow(clippy::needless_as_bytes)]
#![warn(clippy::str_to_string)]
#![warn(clippy::string_to_string)]
#![warn(clippy::todo)]
#![warn(clippy::dbg_macro)]

#[macro_use]
extern crate log;

pub mod conflicts;
pub mod constants;
pub mod diff;
pub mod display;
pub mod exit_codes;
pub mod files;
pub mod gitattributes;
pub mod hash;
pub mod line_parser;
pub mod lines;
pub mod options;
pub mod parse;
pub mod summary;
pub mod version;
pub mod words;