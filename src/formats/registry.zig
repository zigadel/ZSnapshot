// ZSnapshot/src/formats/registry.zig
// Tiny dispatch layer for format codecs. Sniffs header and routes to tbl1/tbl2.
// Header: [ MAGIC(4) | TAG(4) | ... ]
const std = @import("std");
const mem = std.mem;

const E = @import("errors").Error;
const container = @import("container");
const tbl1 = @import("tbl1");
const tbl2 = @import("tbl2");

// Shared public types (keep API uniform)
const ColumnDesc = container.ColumnDesc;
// ColumnView is defined in tbl1 and re-used by tbl2
const ColumnView = tbl1.ColumnView;
// Both tbl1/tbl2 expose identical ReadBack layout; alias to tbl1’s.
pub const ReadBack = tbl1.ReadBack;

pub const Codec = enum { tbl1, tbl2 };

pub fn tagOf(c: Codec) []const u8 {
    return switch (c) {
        .tbl1 => container.TAG_TBL1,
        .tbl2 => container.TAG_TBL2,
    };
}

pub fn nameOf(c: Codec) []const u8 {
    return switch (c) {
        .tbl1 => "TBL1",
        .tbl2 => "TBL2",
    };
}

/// Detect codec from bytes. Errors on bad magic or unknown tag.
pub fn detect(bytes: []const u8) E!Codec {
    if (bytes.len < 8) return error.InvalidFormat;
    if (!std.mem.eql(u8, bytes[0..4], container.MAGIC)) return error.InvalidFormat;
    const tag = bytes[4..8];
    if (std.mem.eql(u8, tag, container.TAG_TBL1)) return .tbl1;
    if (std.mem.eql(u8, tag, container.TAG_TBL2)) return .tbl2;
    return error.Unsupported;
}

/// Write using an explicit codec.
pub fn write(c: Codec, descs: []const ColumnDesc, cols: []const ColumnView, a: mem.Allocator) E![]u8 {
    return switch (c) {
        .tbl1 => tbl1.writeTable(descs, cols, a),
        .tbl2 => tbl2.writeTable(descs, cols, a), // uses alias above
    };
}

pub fn read(bytes: []const u8, a: mem.Allocator) E!ReadBack {
    const c = try detect(bytes);
    return switch (c) {
        .tbl1 => tbl1.readTable(bytes, a),
        .tbl2 => tbl2.readTable(bytes, a), // uses alias above; returns tbl1.ReadBack shape
    };
}

// ─────────────────────────────── Tests ───────────────────────────────

test "registry: detect + roundtrip (tbl1 & tbl2)" {
    const A = std.testing.allocator;

    // 1-row fixed u8 column with no nulls
    var nulls = [_]u8{0};
    const data = [_]u8{42};
    const desc = ColumnDesc{ .name = "one", .kind = .fixed_int, .width_bits = 8, .signed = false };
    const col = ColumnView{ .fixed = .{ .width_bits = 8, .signed = false, .len = 1, .nulls = &nulls, .data = &data } };

    // TBL1 write → detect → read
    const b1 = try write(.tbl1, &.{desc}, &.{col}, A);
    defer A.free(b1);
    try std.testing.expectEqual(Codec.tbl1, try detect(b1));
    var r1 = try read(b1, A);
    defer r1.deinit(A);
    try std.testing.expectEqual(@as(usize, 1), r1.cols.len);

    // TBL2 write → detect → read
    const b2 = try write(.tbl2, &.{desc}, &.{col}, A);
    defer A.free(b2);
    try std.testing.expectEqual(Codec.tbl2, try detect(b2));
    var r2 = try read(b2, A);
    defer r2.deinit(A);
    try std.testing.expectEqual(@as(usize, 1), r2.cols.len);
}
