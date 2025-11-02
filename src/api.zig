const std = @import("std");

pub const errors = @import("errors");
const container = @import("container");
const tbl1 = @import("tbl1");

pub const ColumnKind = container.ColumnKind;
pub const ColumnDesc = container.ColumnDesc;
pub const ColumnView = tbl1.ColumnView;
pub const ColumnOwned = tbl1.ColumnOwned;
pub const ReadBack = tbl1.ReadBack;

pub fn writeTable(descs: []const ColumnDesc, cols: []const ColumnView, a: std.mem.Allocator) errors.Error![]u8 {
    return tbl1.writeTable(descs, cols, a);
}

pub fn readTable(bytes: []const u8, a: std.mem.Allocator) errors.Error!ReadBack {
    return tbl1.readTable(bytes, a);
}

test {
    std.testing.refAllDecls(@This());
}
