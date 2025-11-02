// ZSnapshot/src/container.zig — binary container helpers
const std = @import("std");
const E = @import("errors").Error;

pub const MAGIC = "ZSN1";
pub const TAG_TBL1 = "TBL1";

pub const ColumnKind = enum { bool_, fixed_int, fixed_float, var_bytes };

pub const ColumnDesc = struct {
    name: []const u8,
    kind: ColumnKind,
    width_bits: u16, // 1 for bool, 8/16/32/64 for fixed; 0 for var_bytes
    signed: bool, // only for fixed_int
};

pub const WriteHeader = struct {
    col_count: u32,
    row_count: u64,
    // (future: flags, codec registry, footer flags)
};

pub fn writeU16(buf: []u8, off: usize, v: u16) void {
    std.mem.writeIntLittle(u16, buf[off..][0..2], v);
}
pub fn writeU32(buf: []u8, off: usize, v: u32) void {
    std.mem.writeIntLittle(u32, buf[off..][0..4], v);
}
pub fn writeU64(buf: []u8, off: usize, v: u64) void {
    std.mem.writeIntLittle(u64, buf[off..][0..8], v);
}
pub fn readU16(buf: []const u8, off: usize) E!u16 {
    if (off + 2 > buf.len) return error.InvalidFormat;
    return std.mem.readIntLittle(u16, buf[off..][0..2]);
}
pub fn readU32(buf: []const u8, off: usize) E!u32 {
    if (off + 4 > buf.len) return error.InvalidFormat;
    return std.mem.readIntLittle(u32, buf[off..][0..4]);
}
pub fn readU64(buf: []const u8, off: usize) E!u64 {
    if (off + 8 > buf.len) return error.InvalidFormat;
    return std.mem.readIntLittle(u64, buf[off..][0..8]);
}
