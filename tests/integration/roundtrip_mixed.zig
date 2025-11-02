const std = @import("std");
const z = @import("zsnapshot");

test "integration: roundtrip fixed+var with nulls" {
    const A = std.testing.allocator;

    // fixed_i32 as raw bytes + null flags
    var nulls_i32 = [_]u8{0b00000100}; // mark row 2 null (zero-based)
    var data_i32: [12]u8 = undefined; // 3 * 4 bytes
    std.mem.writeInt(i32, data_i32[0..4], 10, .little);
    std.mem.writeInt(i32, data_i32[4..8], 20, .little);
    std.mem.writeInt(i32, data_i32[8..12], 30, .little);

    // var_bytes: ["aa", null, "b"]
    var nulls_s = [_]u8{0b00000100}; // row 2 null
    const data_s = "aa" ++ "b";
    const offs = [_]u64{ 0, 2, 2, 3 };

    const descs = [_]z.api.ColumnDesc{
        .{ .name = "x", .kind = .fixed_int, .width_bits = 32, .signed = true },
        .{ .name = "s", .kind = .var_bytes, .width_bits = 0, .signed = false },
    };
    const cols = [_]z.api.ColumnView{
        .{ .fixed = .{ .width_bits = 32, .signed = true, .len = 3, .nulls = &nulls_i32, .data = &data_i32 } },
        .{ .var_bytes = .{ .len = 3, .nulls = &nulls_s, .offsets = &offs, .data = data_s } },
    };

    const bytes = try z.api.writeTable(&descs, &cols, A);
    defer A.free(bytes);

    var rb = try z.api.readTable(bytes, A);
    defer rb.deinit(A);

    try std.testing.expectEqual(@as(usize, 2), rb.cols.len);
}
