const std = @import("std");

test {
    _ = @import("e2e/file_roundtrip_tbl1.zig");
}

test {
    std.testing.refAllDecls(@This());
}
