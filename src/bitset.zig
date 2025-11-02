const std = @import("std");

pub fn ceilDiv(a: usize, b: usize) usize {
    return (a + b - 1) / b;
}

pub inline fn setBit(buf: []u8, idx: usize, value: bool) void {
    const byte = idx >> 3;
    const bit: u3 = @intCast(idx & 7);
    const mask: u8 = 1 << bit;
    if (value) buf[byte] |= mask else buf[byte] &= ~mask;
}

pub inline fn getBit(buf: []const u8, idx: usize) bool {
    const byte = idx >> 3;
    const bit: u3 = @intCast(idx & 7);
    return (buf[byte] >> bit) & 1 == 1;
}
