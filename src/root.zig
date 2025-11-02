// Keep logic out; re-export modules. Comment TODOs as a living roadmap.

const std = @import("std");
pub const build = @import("build_options");

// Core public modules
pub const errors = @import("errors");

// Internals (exposed for low-level consumers; stable enough for Z* libs)
pub const bitset = @import("bitset");
pub const container = @import("container");

// Formats (only TBL1 shipped today)
pub const tbl1 = @import("tbl1");
pub const tbl2 = @import("tbl2"); // footer/TOC variant
pub const registry = @import("registry"); // TAG → codec registry

// Stable API surface (format-agnostic helpers)
pub const api = @import("api");

test {
    std.testing.refAllDecls(@This());
}
