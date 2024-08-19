underlying: std.io.AnyWriter,
depth: usize = 0,
tab: []const u8 = "\t",

pub fn header(self: *@This()) !void {
    try self.underlying.writeAll("<?xml version=\"1.0\" encoding=\"utf-8\"?>");
}

fn open(self: *@This(), tag: []const u8) !void {
    try self.underlying.writeByte('\n');
    try self.underlying.writeBytesNTimes(self.tab, self.depth);
    try self.underlying.print("<{s}", .{ tag });
}

fn endOpen(self: *@This()) !void {
    try self.underlying.writeByte('>');
    self.depth += 1;
}

fn text(self: *@This(), str: []const u8) !void {
    try self.underlying.writeByte('\n');
    try self.underlying.writeBytesNTimes(self.tab, self.depth);
    try self.underlying.print("{s}", .{ str });
}

fn end(self: *@This(), tag: []const u8) !void {
    try self.underlying.writeByte('\n');
    self.depth -= 1;
    try self.underlying.writeBytesNTimes(self.tab, self.depth);
    try self.underlying.print("</{s}>", .{ tag });
}

fn element(self: *@This(), comptime T: type, value: T) !void {
    switch (@typeInfo(T)) {
        .Struct => |s| {
            const tag = @typeName(T);
            try self.open(tag);
            inline for (s.fields) |f| {
                try self.anyAttribute(f.name, f.type, @field(value, f.name));
            }
            try self.endOpen();
            const last_field = s.fields[s.fields.len - 1];
            try self.children(last_field.type, @field(value, last_field.name));
            try self.end(tag);
        },
        .Union => {
            switch (value) {
                inline else => |v| try self.element(@TypeOf(v), v),
            }
        },
        else => @compileError("cannot serialize " ++ @typeName(T)),
    }
}

fn children(self: *@This(), comptime T: type, value: T) !void {
    switch (@typeInfo(T)) {
       inline .Pointer, .Array => |info| {
            if (info.child == u8) {
                try self.text(value);
            } else {
                for (value) |v| try self.element(info.child, v);
            }
        },
        else => {},
    }
}

fn attribute(self: *@This(), key: []const u8, val: []const u8) !void {
    try self.underlying.print(" {s}=\"{s}\"", .{ key,  val });
}

fn anyAttribute(self: *@This(), key: []const u8, comptime T: type, val: T) !void {
    if (std.meta.hasFn(T, "write")) {
        try self.underlying.print(" {s}=\"", .{ key });
        try val.write(self.underlying);
        try self.underlying.writeByte('"');
    } else switch (@typeInfo(T)) {
        inline .Int, .Float => try self.underlying.print(" {s}=\"{d}\"", .{ key, val }),
        .Optional => |o| {
            if (val) |v| try self.anyAttribute(key, o.child, v);
        },
        .Bool => try self.attribute(key,  if (val) "true" else "false"),
        .Enum => try self.attribute(key,  @tagName(val)),
        else => {},
    }
}

fn morpheme(self: *@This(), book_: Bible.Book, i: Bible.StringPool.Index) !void {
    const m = book_.morphemes[i];
    try self.open("m");
    try self.attribute("type", @tagName(m.flags.type));
    try self.anyAttribute("strong", Morpheme.Strong, m.strong);
    if (!m.code.isNull()) try self.anyAttribute("code", Morpheme.Code, m.code);
    try self.endOpen();
    try self.underlying.print("{s}</m>", .{ book_.pool.get(m.text).? });
    self.depth -= 1;
}

pub fn book(self: *@This(), book_: Bible.Book) !void {
    var i: Bible.StringPool.Index = 0;
    try self.open("book");
    try self.attribute("id", @tagName(book_.name));
    try self.endOpen();
    while (i < book_.morphemes.len) {
        const w = book_.morphemes[i];
        std.debug.assert(w.flags.starts_word);
        try self.open("w");
        // try self.anyAttribute("ref", Bible.Word.Reference, w.ref);
        try self.endOpen();

        try self.morpheme(book_, i);
        i += 1;
        while (i < book_.morphemes.len and !book_.morphemes[i].flags.starts_word) : (i += 1) {
            try self.morpheme(book_, i);
        }

        try self.end("w");
    }
    try self.end("book");
}

const std = @import("std");
const Bible = @import("../Bible.zig");
const Morpheme = Bible.Morpheme;
