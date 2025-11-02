// zsnapshot/src/formats/tbl1.zig — TBL1 encode/decode (per-column CRC64)
const std = @import("std");
const mem = std.mem;

const E = @import("errors").Error;
const crc64 = @import("crc64");
const container = @import("container");
const ColumnKind = container.ColumnKind;
const ColumnDesc = container.ColumnDesc;

// Writer/Reader column views (agnostic of host types)
pub const ColumnView = union(enum) {
    fixed: struct { width_bits: u16, signed: bool, len: usize, nulls: []const u8, data: []const u8 },
    var_bytes: struct { len: usize, nulls: []const u8, offsets: []const u64, data: []const u8 },
};

pub const ColumnOwned = union(enum) {
    fixed: struct { width_bits: u16, signed: bool, len: usize, nulls: []u8, data: []u8 },
    var_bytes: struct { len: usize, nulls: []u8, offsets: []u64, data: []u8 },

    pub fn deinit(self: *ColumnOwned, a: mem.Allocator) void {
        switch (self.*) {
            .fixed => |*f| {
                a.free(f.nulls);
                a.free(f.data);
            },
            .var_bytes => |*v| {
                a.free(v.nulls);
                a.free(v.offsets);
                a.free(v.data);
            },
        }
        self.* = undefined;
    }
};

fn writeDesc(out: *std.ArrayListUnmanaged(u8), a: mem.Allocator, d: ColumnDesc) E!void {
    if (d.name.len > std.math.maxInt(u16)) return error.Unsupported;
    try out.appendSlice(a, &[_]u8{@intFromEnum(d.kind)});

    var tmp_u16: [2]u8 = undefined;
    container.writeU16(&tmp_u16, 0, d.width_bits);
    try out.appendSlice(a, &tmp_u16);

    try out.appendSlice(a, &[_]u8{if (d.signed) 1 else 0});

    var nl: [2]u8 = undefined;
    container.writeU16(&nl, 0, @intCast(d.name.len));
    try out.appendSlice(a, &nl);
    try out.appendSlice(a, d.name);
}

fn readDesc(bytes: []const u8, off: *usize, a: mem.Allocator) E!ColumnDesc {
    if (off.* + 1 + 2 + 1 + 2 > bytes.len) return error.InvalidFormat;

    const kind: ColumnKind = @enumFromInt(bytes[off.*]);
    off.* += 1;

    const width_bits = try container.readU16(bytes, off.*);
    off.* += 2;

    const signed = bytes[off.*] != 0;
    off.* += 1;

    const name_len = try container.readU16(bytes, off.*);
    off.* += 2;

    if (off.* + name_len > bytes.len) return error.InvalidFormat;
    const name = try a.alloc(u8, name_len);
    @memcpy(name, bytes[off.* .. off.* + name_len]);
    off.* += name_len;

    return .{ .name = name, .kind = kind, .width_bits = width_bits, .signed = signed };
}

fn appendU64(out: *std.ArrayListUnmanaged(u8), a: mem.Allocator, v: u64) !void {
    var tmp: [8]u8 = undefined;
    container.writeU64(&tmp, 0, v);
    try out.appendSlice(a, &tmp);
}
fn appendU32(out: *std.ArrayListUnmanaged(u8), a: mem.Allocator, v: u32) !void {
    var tmp: [4]u8 = undefined;
    container.writeU32(&tmp, 0, v);
    try out.appendSlice(a, &tmp);
}

// File layout (sequential; LE):
// [ "ZSN1"(4) | "TBL1"(4) |
//   col_count u32 | row_count u64 |
//   for each col: DESC(kind u8, width_bits u16, signed u8, name_len u16, name bytes)
//   for each col:
//     kind u8
//     if fixed: len u64, null_len u64, data_len u64, nulls, data
//     if var  : len u64, null_len u64, off_count u64, data_len u64, nulls, offsets[u64], data
//     crc64 u64 (over the entire column payload block immediately preceding it)
// ]
pub fn writeTable(
    descs: []const ColumnDesc,
    cols: []const ColumnView,
    allocator: mem.Allocator,
) E![]u8 {
    if (descs.len != cols.len) return error.InvalidFormat;
    if (descs.len > std.math.maxInt(u32)) return error.Unsupported;

    // Row count agreement
    var row_count: ?usize = null;
    for (cols) |c| {
        const n = switch (c) {
            .fixed => |f| f.len,
            .var_bytes => |v| v.len,
        };
        row_count = if (row_count == null) n else blk: {
            if (row_count.? != n) return error.InvalidFormat;
            break :blk row_count.?;
        };
    }
    const rows: usize = row_count orelse 0;

    var out = std.ArrayListUnmanaged(u8){};
    errdefer out.deinit(allocator);

    // Header
    try out.appendSlice(allocator, container.MAGIC);
    try out.appendSlice(allocator, container.TAG_TBL1);
    try appendU32(&out, allocator, @intCast(cols.len));
    try appendU64(&out, allocator, @intCast(rows));

    // Schema descriptors
    for (descs) |d| try writeDesc(&out, allocator, d);

    // Column payloads
    var i: usize = 0;
    while (i < cols.len) : (i += 1) {
        const d = descs[i];
        const c = cols[i];

        switch (c) {
            .fixed => |f| {
                if (d.kind != .fixed_int and d.kind != .fixed_float and d.kind != .bool_) return error.TypeMismatch;

                try out.append(allocator, @intFromEnum(d.kind));
                try appendU64(&out, allocator, @intCast(f.len));
                try appendU64(&out, allocator, @intCast(f.nulls.len));
                try appendU64(&out, allocator, @intCast(f.data.len));

                const start = out.items.len;
                try out.appendSlice(allocator, f.nulls);
                try out.appendSlice(allocator, f.data);

                const crc = crc64.crc64_ecma(out.items[start..]);
                try appendU64(&out, allocator, crc);
            },
            .var_bytes => |v| {
                if (d.kind != .var_bytes) return error.TypeMismatch;

                try out.append(allocator, @intFromEnum(d.kind));
                try appendU64(&out, allocator, @intCast(v.len));
                try appendU64(&out, allocator, @intCast(v.nulls.len));
                try appendU64(&out, allocator, @intCast(v.offsets.len)); // count
                try appendU64(&out, allocator, @intCast(v.data.len));

                const start = out.items.len;
                try out.appendSlice(allocator, v.nulls);

                // offsets are u64 LE
                var j: usize = 0;
                while (j < v.offsets.len) : (j += 1) {
                    var tmp: [8]u8 = undefined;
                    container.writeU64(&tmp, 0, v.offsets[j]);
                    try out.appendSlice(allocator, &tmp);
                }

                try out.appendSlice(allocator, v.data);

                const crc = crc64.crc64_ecma(out.items[start..]);
                try appendU64(&out, allocator, crc);
            },
        }
    }

    return out.toOwnedSlice(allocator);
}

pub const ReadBack = struct {
    const Self = @This();
    descs: []ColumnDesc, // names are owned
    cols: []ColumnOwned,

    pub fn deinit(self: *Self, a: mem.Allocator) void {
        for (self.descs) |d| a.free(d.name);
        a.free(self.descs);
        for (self.cols) |*c| c.deinit(a);
        a.free(self.cols);
        self.* = undefined;
    }
};

pub fn readTable(bytes: []const u8, a: mem.Allocator) E!ReadBack {
    if (bytes.len < 4 + 4 + 4 + 8) return error.InvalidFormat;
    if (!std.mem.eql(u8, bytes[0..4], container.MAGIC)) return error.InvalidFormat;
    if (!std.mem.eql(u8, bytes[4..8], container.TAG_TBL1)) return error.InvalidFormat;

    var off: usize = 8;

    const col_count = try container.readU32(bytes, off);
    off += 4;

    _ = try container.readU64(bytes, off); // row_count (validated via per-col)
    off += 8;

    // Descriptors
    var descs = try a.alloc(ColumnDesc, col_count);
    var i: usize = 0;
    while (i < col_count) : (i += 1) {
        descs[i] = try readDesc(bytes, &off, a);
    }

    var cols = try a.alloc(ColumnOwned, col_count);

    // Payloads
    i = 0;
    while (i < col_count) : (i += 1) {
        if (off >= bytes.len) return error.InvalidFormat;

        const kind: ColumnKind = @enumFromInt(bytes[off]);
        off += 1;

        const len = try container.readU64(bytes, off);
        off += 8;

        const null_len = try container.readU64(bytes, off);
        off += 8;

        switch (kind) {
            .fixed_int, .fixed_float, .bool_ => {
                const data_len = try container.readU64(bytes, off);
                off += 8;

                const payload_start = off;
                if (payload_start + null_len + data_len + 8 > bytes.len) return error.InvalidFormat;

                const nulls = try a.alloc(u8, @intCast(null_len));
                @memcpy(nulls, bytes[payload_start .. payload_start + null_len]);

                const data = try a.alloc(u8, @intCast(data_len));
                const data_off = payload_start + null_len;
                @memcpy(data, bytes[data_off .. data_off + data_len]);

                const crc_expected = try container.readU64(bytes, data_off + data_len);
                const crc_actual = crc64.crc64_ecma(bytes[payload_start .. data_off + data_len]);
                if (crc_expected != crc_actual) return error.CrcMismatch;

                off = data_off + data_len + 8;

                cols[i] = .{ .fixed = .{
                    .width_bits = descs[i].width_bits,
                    .signed = descs[i].signed,
                    .len = @intCast(len),
                    .nulls = nulls,
                    .data = data,
                } };
            },
            .var_bytes => {
                const off_count = try container.readU64(bytes, off);
                off += 8;

                const data_len = try container.readU64(bytes, off);
                off += 8;

                const payload_start = off;
                const offs_bytes = off_count * 8;
                if (payload_start + null_len + offs_bytes + data_len + 8 > bytes.len) return error.InvalidFormat;

                const nulls = try a.alloc(u8, @intCast(null_len));
                @memcpy(nulls, bytes[payload_start .. payload_start + null_len]);

                var offsets = try a.alloc(u64, @intCast(off_count));
                var j: usize = 0;
                var p = payload_start + null_len;
                while (j < off_count) : (j += 1) {
                    offsets[j] = try container.readU64(bytes, p);
                    p += 8;
                }

                const data = try a.alloc(u8, @intCast(data_len));
                @memcpy(data, bytes[p .. p + data_len]);

                const crc_expected = try container.readU64(bytes, p + data_len);
                const crc_actual = crc64.crc64_ecma(bytes[payload_start .. p + data_len]);
                if (crc_expected != crc_actual) return error.CrcMismatch;

                off = p + data_len + 8;

                cols[i] = .{ .var_bytes = .{
                    .len = @intCast(len),
                    .nulls = nulls,
                    .offsets = offsets,
                    .data = data,
                } };
            },
        }
    }

    return .{ .descs = descs, .cols = cols };
}
