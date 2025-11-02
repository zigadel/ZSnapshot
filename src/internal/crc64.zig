// ZSnapshot/src/internal/crc64.zig — CRC-64/ECMA-182 (bitwise, debug-safe)
const std = @import("std");

/// Bitwise CRC-64/ECMA-182.
/// Start value = 0, no final xor (writer/reader both use the same).
pub fn crc64_ecma(input: []const u8) u64 {
    const POLY: u64 = 0x42F0E1EBA9EA3693;

    var acc: u64 = 0;

    for (input) |byte| {
        var b = byte;
        var j: u8 = 0; // <- wide enough to reach 8 without overflow
        while (j < 8) : (j += 1) {
            const mix: u64 = ((acc >> 63) ^ ((b >> 7) & 1));
            acc = (acc << 1); // shifting is fine; no overflow trap
            if (mix == 1) acc ^= POLY; // typed polynomial avoids comptime issues
            b <<= 1;
        }
    }
    return acc;
}

test "crc64-ecma smoke" {
    const a = "abc";
    const b = "abc";
    const c = "abd";
    try std.testing.expectEqual(crc64_ecma(a), crc64_ecma(b));
    try std.testing.expect(crc64_ecma(a) != crc64_ecma(c));
}
