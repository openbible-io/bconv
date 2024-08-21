underlying: std.io.AnyWriter,

const field_sep = ',';
const row_sep = '\n';
pub const ext = "csv";

const fields = [_][]const u8{
    "source",
    "variant",
    "type",
    "text",
    "strong",
    "grammar",
};

pub fn header(self: *@This()) !void {
    for (fields, 0..) |f, i| {
        try self.underlying.writeAll(f);
        if (i != fields.len - 1) try self.underlying.writeByte(field_sep);
    }
    try self.rowSep();
}

// https://www.rfc-editor.org/rfc/rfc4180
fn text(self: *@This(), str: []const u8) !void {
    if (std.mem.indexOfAny(u8, str, &[_]u8{field_sep, row_sep}) != null) {
        try self.underlying.writeByte('"');
        for (str) |c| {
            if (c == '"') {
                try self.underlying.writeAll("\"\"");
            } else {
                try self.underlying.writeByte(c);
            }
        }
        try self.underlying.writeByte('"');
    } else {
        try self.underlying.print("{s}", .{ str });
    }
}

fn any(self: *@This(), val: anytype) !void {
    const T = @TypeOf(val);
    if (std.meta.hasFn(T, "write")) {
        try val.write(self.underlying);
    } else switch (@typeInfo(T)) {
        inline .Int, .Float => try self.underlying.print("{d}", .{ val }),
        .Optional => {
            if (val) |v| try self.any(v);
        },
        .Bool => try self.underlying.writeAll(if (val) "true" else "false"),
        .Enum => try self.underlying.writeAll(@tagName(val)),
        else => {},
    }
}

fn fieldSep(self: *@This()) !void {
    try self.underlying.writeByte(field_sep);
}

fn rowSep(self: *@This()) !void {
    try self.underlying.writeByte(row_sep);
}

pub fn book(self: *@This(), book_: Bible.Book) !void {
    for (book_.morphemes, 0..) |m, i| {
        try self.any(m.tags.source);
        try self.fieldSep();
        if (m.tags.variant != .none) try self.any(m.tags.variant);
        try self.fieldSep();
        try self.any(m.tags.type);
        try self.fieldSep();
        try self.text(book_.pool.get(m.text));
        try self.fieldSep();
        try m.writeStrong(self.underlying);
        try self.fieldSep();
        try m.writeGrammar(self.underlying);
        if (i != book_.morphemes.len - 1) try self.rowSep();
    }
}

const std = @import("std");
const Bible = @import("../Bible.zig");
const Morpheme = Bible.Morpheme;
