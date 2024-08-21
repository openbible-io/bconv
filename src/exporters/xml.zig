underlying: std.io.AnyWriter,
depth: usize = 0,
tab_str: []const u8 = "\t",
tags: std.BoundedArray([]const u8, max_depth) = .{},
in_variant: bool = false,
prev_type: Morpheme.Tags.Type = .root,

pub const ext = "xml";
const max_depth = 8;

pub fn header(self: *@This()) !void {
    try self.underlying.writeAll(
        \\<?xml version="1.0" encoding="utf-8"?>
    );
}

fn open(self: *@This(), tag: []const u8) !void {
    try self.tab();
    self.depth += 1;
    try self.underlying.print("<{s}", .{ tag });
    try self.tags.append(tag);
}

fn tab(self: @This()) !void {
    try self.underlying.writeByte('\n');
    try self.underlying.writeBytesNTimes(self.tab_str, self.depth);
}

fn endOpen(self: *@This()) !void {
    try self.underlying.writeByte('>');
}

fn text(self: *@This(), str: []const u8) !void {
    if (str.len == 0) return;
    try self.tab();
    try self.underlying.print("{s}", .{ str });
}

fn close(self: *@This()) !void {
    self.depth -= 1;
    try self.tab();
    const tag = self.tags.pop();
    try self.underlying.print("</{s}>", .{ tag });
}

fn assertClose(self: *@This(), tag: []const u8) !void {
    const actual = self.tags.get(self.tags.len - 1);
    if (!std.mem.eql(u8, actual, tag)) {
        std.debug.print("expected {s} got {s}\n", .{ tag, actual });
        std.debug.assert(false);
    }
    try self.close();
}

fn closeNonRoot(self: *@This()) !void {
    if (self.tags.len > 1) try self.close();
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
            try self.close();
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

fn anyAttribute(self: *@This(), key: []const u8, val: anytype) !void {
    const T = @TypeOf(val);
    if (std.meta.hasFn(T, "write")) {
        try self.underlying.print(" {s}=\"", .{ key });
        try val.write(self.underlying);
        try self.underlying.writeByte('"');
    } else switch (@typeInfo(T)) {
        inline .Int, .Float => try self.underlying.print(" {s}=\"{d}\"", .{ key, val }),
        .Optional => {
            if (val) |v| try self.anyAttribute(key, v);
        },
        .Bool => try self.attribute(key,  if (val) "true" else "false"),
        .Enum => try self.attribute(key,  @tagName(val)),
        else => {},
    }
}

fn morpheme(self: *@This(), book_: Bible.Book, i: Bible.StringPool.Index) !void {
    const m = book_.morphemes[i];
    const str = book_.pool.get(m.text);

    try self.open("m");
    if (!m.tags.source.eql(book_.source)) try self.anyAttribute("source",  m.tags.source);
    if (str.len > 0) try self.anyAttribute("type", m.tags.type);
    if (m.strong_n != 0 and m.tags.lang != .unknown) {
        try self.underlying.print(" {s}=\"", .{ "strong" });
        try m.writeStrong(self.underlying);
        try self.underlying.writeByte('"');
    }
    if (!m.grammar.isNull()) {
        try self.underlying.print(" {s}=\"", .{ "grammar" });
        try m.writeGrammar(self.underlying);
        try self.underlying.writeByte('"');
    }
    try self.endOpen();
    try self.text(str);
    try self.close();
}

fn option(self: *@This()) !void {
    try self.open("option");
    try self.endOpen();
}

pub fn book(self: *@This(), book_: Bible.Book) !void {
    try self.open("book");
    try self.attribute("id", @tagName(book_.name));
    try self.anyAttribute("source", book_.source);
    try self.endOpen();

    var i: Bible.StringPool.Index = 0;
    while (i < book_.morphemes.len) : (i += 1) {
        const m = book_.morphemes[i];
        const new_source = i > 0 and !book_.morphemes[i - 1].tags.source.eql(m.tags.source);

        defer self.prev_type = m.tags.type;
        const starts_word = switch (m.tags.type) {
            .root => switch (self.prev_type) {
                .prefix => false,
                else => true,
            },
           .prefix => switch (self.prev_type) {
               .prefix => false,
               else => true,
           },
           .suffix => false,
           .punctuation => false,
        };

        if (starts_word and i != 0) try self.close();
        if (m.tags.variant == .start) {
            if (self.in_variant) {
               try self.close();
               try self.close();
            }
            self.in_variant = true;
            try self.open("variant");
            try self.endOpen();
            try self.option();
        } else if (new_source and self.in_variant) {
            try self.close();
            try self.option();
        }
        if (starts_word) {
            try self.open("w");
            try self.endOpen();
        }

        try self.morpheme(book_, i);

        if (m.tags.variant == .end) {
            try self.close();
            try self.close();
            self.in_variant = false;
        }
    }

    for (0..self.tags.len) |_| try self.close();
    try self.tab();
}

const std = @import("std");
const Bible = @import("../Bible.zig");
const Morpheme = Bible.Morpheme;
