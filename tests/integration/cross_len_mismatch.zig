const std = @import("std");
const z = @import("zsnapshot");
const E = z.errors.Error; // <-- error set lives here

// Columns with different row counts must be rejected.
test "integration: row-count mismatch → InvalidFormat" {
    const A = std.testing.allocator;

    const d0 = z.api.ColumnDesc{ .name = "a", .kind = .fixed_int, .width_bits = 8, .signed = false };
    const d1 = z.api.ColumnDesc{ .name = "b", .kind = .var_bytes, .width_bits = 0, .signed = false };
    const descs = [_]z.api.ColumnDesc{ d0, d1 };

    // col0: 3 rows
    const nulls0 = [_]u8{0};
    const data0 = [_]u8{ 11, 22, 33 };
    const c0 = z.api.ColumnView{ .fixed = .{ .width_bits = 8, .signed = false, .len = 3, .nulls = &nulls0, .data = &data0 } };

    // col1: 2 rows (mismatch)
    const nulls1 = [_]u8{0};
    const offs1 = [_]u64{ 0, 2, 4 };
    const data1 = [_]u8{ 'h', 'i', 'o', 'k' };
    const c1 = z.api.ColumnView{ .var_bytes = .{ .len = 2, .nulls = &nulls1, .offsets = &offs1, .data = &data1 } };

    try std.testing.expectError(E.InvalidFormat, z.api.writeTable(&descs, &.{ c0, c1 }, A));
}

// Descs/Cols length mismatch must be rejected too.
test "integration: descs.len != cols.len → InvalidFormat" {
    const A = std.testing.allocator;

    const descs = [_]z.api.ColumnDesc{
        .{ .name = "only-one", .kind = .fixed_int, .width_bits = 8, .signed = false },
    };

    const nulls = [_]u8{0};
    const data = [_]u8{7};
    const c0 = z.api.ColumnView{ .fixed = .{ .width_bits = 8, .signed = false, .len = 1, .nulls = &nulls, .data = &data } };
    const c1 = c0; // second col, but only one desc

    try std.testing.expectError(E.InvalidFormat, z.api.writeTable(&descs, &.{ c0, c1 }, A));
}
