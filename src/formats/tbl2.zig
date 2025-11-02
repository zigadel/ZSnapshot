// ZSnapshot/src/formats/tbl2.zig — TBL2 encode/decode (TOC + per-column CRC in TOC)
// Header:
//   "ZSN1"(4) | "TBL2"(4) | col_count u32 | row_count u64 | toc_off u64
// Then: descriptors (same as TBL1 writeDesc/readDesc)
// Then: column payloads (same layout as TBL1 for each kind)
// Then: TOC:
//   entry_count u32 (== col_count)
//   for i in 0..col_count-1:
//       off u64 | len u64 | crc64 u64
const std = @import("std");
const mem = std.mem;

const E = @import("errors").Error;
const bitset = @import("bitset");
const crc64 = @import("crc64");
const container = @import("container");
const ColumnKind = container.ColumnKind;
const ColumnDesc = container.ColumnDesc;

pub const ColumnView = @import("tbl1").ColumnView;
pub const ColumnOwned = @import("tbl1").ColumnOwned;
// Unify return type with TBL1 so registry returns a single shape
pub const ReadBack = @import("tbl1").ReadBack; // <- add this

/// write/read the same descriptor shape as TBL1 to keep parity
fn writeDesc(out: *std.ArrayListUnmanaged(u8), a: mem.Allocator, d: ColumnDesc) E!void {
    if (d.name.len > std.math.maxInt(u16)) return error.Unsupported;
    try out.appendSlice(a, &[_]u8{@intFromEnum(d.kind)});
    var tmp2: [2]u8 = undefined;
    container.writeU16(&tmp2, 0, d.width_bits);
    try out.appendSlice(a, &tmp2);
    try out.appendSlice(a, &[_]u8{if (d.signed) 1 else 0});
    container.writeU16(&tmp2, 0, @intCast(d.name.len));
    try out.appendSlice(a, &tmp2);
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

fn appendU32(out: *std.ArrayListUnmanaged(u8), a: mem.Allocator, v: u32) !void {
    var tmp: [4]u8 = undefined;
    container.writeU32(&tmp, 0, v);
    try out.appendSlice(a, &tmp);
}
fn appendU64(out: *std.ArrayListUnmanaged(u8), a: mem.Allocator, v: u64) !void {
    var tmp: [8]u8 = undefined;
    container.writeU64(&tmp, 0, v);
    try out.appendSlice(a, &tmp);
}

pub fn writeTable2(
    descs: []const ColumnDesc,
    cols: []const ColumnView,
    a: mem.Allocator,
) E![]u8 {
    if (descs.len != cols.len) return error.InvalidFormat;
    if (descs.len > std.math.maxInt(u32)) return error.Unsupported;

    // verify row-count coherence
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
    errdefer out.deinit(a);

    // Header
    try out.appendSlice(a, container.MAGIC); // "ZSN1"
    try out.appendSlice(a, container.TAG_TBL2); // tag
    try appendU32(&out, a, @intCast(cols.len)); // col_count
    try appendU64(&out, a, @intCast(rows)); // row_count
    const toc_off_pos = out.items.len; // reserve toc_off
    try appendU64(&out, a, 0);

    // Descriptors
    for (descs) |d| try writeDesc(&out, a, d);

    // Column payloads (same layout as TBL1), collect toc entries
    const Entry = struct { off: u64, len: u64, crc: u64 };
    var entries = try a.alloc(Entry, cols.len);
    defer a.free(entries);

    var i: usize = 0;
    while (i < cols.len) : (i += 1) {
        const d = descs[i];
        const c = cols[i];
        const start = out.items.len;

        // Write payload (no CRC inline; CRC will go in TOC)
        switch (c) {
            .fixed => |f| {
                if (d.kind != .fixed_int and d.kind != .fixed_float and d.kind != .bool_) return error.TypeMismatch;
                try out.append(a, @intFromEnum(d.kind));
                try appendU64(&out, a, @intCast(f.len));
                try appendU64(&out, a, @intCast(f.nulls.len));
                try appendU64(&out, a, @intCast(f.data.len));
                try out.appendSlice(a, f.nulls);
                try out.appendSlice(a, f.data);
            },
            .var_bytes => |v| {
                if (d.kind != .var_bytes) return error.TypeMismatch;
                try out.append(a, @intFromEnum(d.kind));
                try appendU64(&out, a, @intCast(v.len));
                try appendU64(&out, a, @intCast(v.nulls.len));
                try appendU64(&out, a, @intCast(v.offsets.len));
                try appendU64(&out, a, @intCast(v.data.len));
                try out.appendSlice(a, v.nulls);
                var j: usize = 0;
                while (j < v.offsets.len) : (j += 1) {
                    var tmp8: [8]u8 = undefined;
                    container.writeU64(&tmp8, 0, v.offsets[j]);
                    try out.appendSlice(a, &tmp8);
                }
                try out.appendSlice(a, v.data);
            },
        }

        const payload = out.items[start..];
        const crc = crc64.crc64_ecma(payload);
        entries[i] = .{ .off = @intCast(start), .len = @intCast(payload.len), .crc = crc };
    }

    // Write TOC
    const toc_off = out.items.len;
    try appendU32(&out, a, @intCast(entries.len));
    i = 0;
    while (i < entries.len) : (i += 1) {
        try appendU64(&out, a, entries[i].off);
        try appendU64(&out, a, entries[i].len);
        try appendU64(&out, a, entries[i].crc);
    }

    // Patch toc_off in header
    container.writeU64(out.items[toc_off_pos .. toc_off_pos + 8], 0, @intCast(toc_off));

    return out.toOwnedSlice(a);
}

pub fn readTable2(bytes: []const u8, A: mem.Allocator) E!ReadBack {
    if (bytes.len < 4 + 4 + 4 + 8 + 8) return error.InvalidFormat;
    if (!std.mem.eql(u8, bytes[0..4], container.MAGIC)) return error.InvalidFormat;
    if (!std.mem.eql(u8, bytes[4..8], "TBL2")) return error.InvalidFormat;
    var off: usize = 8;

    const col_count = try container.readU32(bytes, off);
    off += 4;
    _ = try container.readU64(bytes, off);
    off += 8; // row_count (optional check later)
    const toc_off = try container.readU64(bytes, off);
    off += 8;
    if (toc_off > bytes.len) return error.InvalidFormat;

    var descs = try A.alloc(ColumnDesc, col_count);
    var i: usize = 0;
    while (i < col_count) : (i += 1) descs[i] = try readDesc(bytes, &off, A);

    // Read TOC
    if (toc_off + 4 > bytes.len) return error.InvalidFormat;
    const entry_count = try container.readU32(bytes, toc_off);
    if (entry_count != col_count) return error.InvalidFormat;

    const toc_first = toc_off + 4;
    const need = toc_first + @as(usize, @intCast(col_count)) * (8 + 8 + 8);
    if (need > bytes.len) return error.InvalidFormat;

    const Entry = struct { off: u64, len: u64, crc: u64 };
    var entries = try A.alloc(Entry, col_count);
    defer A.free(entries);

    var t = toc_first;
    i = 0;
    while (i < col_count) : (i += 1) {
        const e_off = try container.readU64(bytes, t);
        t += 8;
        const e_len = try container.readU64(bytes, t);
        t += 8;
        const e_crc = try container.readU64(bytes, t);
        t += 8;
        if (e_off + e_len > bytes.len) return error.InvalidFormat;
        entries[i] = .{ .off = e_off, .len = e_len, .crc = e_crc };
    }

    // Decode payloads
    var cols = try A.alloc(ColumnOwned, col_count);
    i = 0;
    while (i < col_count) : (i += 1) {
        const e = entries[i];
        const payload = bytes[@intCast(e.off)..@intCast(e.off + e.len)];
        if (crc64.crc64_ecma(payload) != e.crc) return error.CrcMismatch;

        var p: usize = 0;
        if (p >= payload.len) return error.InvalidFormat;
        const kind: ColumnKind = @enumFromInt(payload[p]);
        p += 1;

        const len = try container.readU64(payload, p);
        p += 8;
        const null_len = try container.readU64(payload, p);
        p += 8;

        switch (kind) {
            .fixed_int, .fixed_float, .bool_ => {
                const data_len = try container.readU64(payload, p);
                p += 8;
                if (p + null_len + data_len > payload.len) return error.InvalidFormat;

                const nulls = try A.alloc(u8, @intCast(null_len));
                @memcpy(nulls, payload[p .. p + null_len]);
                p += null_len;

                const data = try A.alloc(u8, @intCast(data_len));
                @memcpy(data, payload[p .. p + data_len]);
                p += data_len;

                cols[i] = .{ .fixed = .{
                    .width_bits = descs[i].width_bits,
                    .signed = descs[i].signed,
                    .len = @intCast(len),
                    .nulls = nulls,
                    .data = data,
                } };
            },
            .var_bytes => {
                const off_count = try container.readU64(payload, p);
                p += 8;
                const data_len = try container.readU64(payload, p);
                p += 8;

                const offs_bytes = off_count * 8;
                if (p + null_len + offs_bytes + data_len > payload.len) return error.InvalidFormat;

                const nulls = try A.alloc(u8, @intCast(null_len));
                @memcpy(nulls, payload[p .. p + null_len]);
                p += null_len;

                var offsets = try A.alloc(u64, @intCast(off_count));
                var j: usize = 0;
                while (j < off_count) : (j += 1) {
                    offsets[j] = try container.readU64(payload, p);
                    p += 8;
                }

                const data = try A.alloc(u8, @intCast(data_len));
                @memcpy(data, payload[p .. p + data_len]);
                p += data_len;

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

// Uniform API so callers can use tbl2.writeTable / tbl2.readTable
pub const writeTable = writeTable2;
pub const readTable = readTable2;

// (Optional) tiny smoke test to ensure it links; doesn’t touch API.zig yet.
test "tbl2: simple encode/decode smoke" {
    const A = std.testing.allocator;

    const d = [_]ColumnDesc{
        .{ .name = "x", .kind = .fixed_int, .width_bits = 8, .signed = false },
    };
    const nulls = [_]u8{0};
    const data = [_]u8{ 5, 6, 7 };
    const c = [_]ColumnView{
        .{ .fixed = .{ .width_bits = 8, .signed = false, .len = 3, .nulls = &nulls, .data = &data } },
    };

    const bytes = try writeTable2(&d, &c, A);
    defer A.free(bytes);

    var rb = try readTable2(bytes, A);
    defer rb.deinit(A);

    try std.testing.expectEqual(@as(usize, 1), rb.cols.len);
}
