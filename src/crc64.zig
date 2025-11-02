// CRC64-ECMA (poly 0x42F0E1EBA9EA3693), init=0, xorout=0, ref=false.
const std = @import("std");

pub fn crc64_ecma(bytes: []const u8) u64 {
    var crc: u64 = 0;
    var i: usize = 0;
    while (i < bytes.len) : (i += 1) {
        const b: u8 = bytes[i];
        var j: u3 = 0;
        var acc = crc ^ (@as(u64, b) << 56);
        while (j < 8) : (j += 1) {
            const msb = @as(u1, @intCast((acc >> 63) & 1));
            acc = (acc << 1) ^ (if (msb == 1) 0x42F0E1EBA9EA3693 else 0);
        }
        crc = acc;
    }
    return crc;
}
