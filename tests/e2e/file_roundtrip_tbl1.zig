const std = @import("std");
const z = @import("zsnapshot");

test "e2e: write file → read file" {
    const A = std.testing.allocator;

    var nulls = [_]u8{0};
    const data = [_]u8{42};

    const desc = z.api.ColumnDesc{
        .name = "one",
        .kind = .fixed_int,
        .width_bits = 8,
        .signed = false,
    };
    const col = z.api.ColumnView{
        .fixed = .{ .width_bits = 8, .signed = false, .len = 1, .nulls = &nulls, .data = &data },
    };

    const bytes = try z.api.writeTable(&.{desc}, &.{col}, A);
    defer A.free(bytes);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "snap.tbl1", .data = bytes });

    const on_disk = try tmp.dir.readFileAlloc(
        "snap.tbl1",
        A,
        @as(std.Io.Limit, @enumFromInt(1 << 20)),
    );
    defer A.free(on_disk);

    var rb = try z.api.readTable(on_disk, A);
    defer rb.deinit(A);

    try std.testing.expectEqual(@as(usize, 1), rb.cols.len);
}
