underlying: std.io.AnyWriter,
depth: usize = 0,
tab_str: []const u8 = "\t",
tags: std.BoundedArray([]const u8, max_depth) = .{},
variant_ending: bool = false,

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
    try self.tab();
    try self.underlying.print("{s}", .{ str });
}

fn close(self: *@This()) !void {
    self.depth -= 1;
    try self.tab();
    const tag = self.tags.pop();
    try self.underlying.print("</{s}>", .{ tag });
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
    try self.open("m");
    try self.anyAttribute("source",  m.source);
    try self.anyAttribute("type", m.flags.type);
    try self.anyAttribute("strong",  m.strong);
    if (!m.code.isNull()) try self.anyAttribute("code",  m.code);
    try self.endOpen();
    try self.text(book_.pool.get(m.text).?);
    try self.close();
}

fn option(self: *@This()) !void {
    try self.open("option");
    try self.endOpen();
}

pub fn book(self: *@This(), book_: Bible.Book) !void {
    var i: Bible.StringPool.Index = 0;
    try self.open("book");
    try self.attribute("id", @tagName(book_.name));
    try self.endOpen();

    while (i < book_.morphemes.len) : (i += 1) {
        const m = book_.morphemes[i];

        if (m.flags.starts_word and i != 0) try self.closeNonRoot();
        switch (m.flags.variant) {
            .none => {},
            .start => {
                try self.open("variant");
                try self.endOpen();
                try self.option();
            },
           .option_start => {
               try self.close(); // option
               try self.option();
           },
            .ended => {
                try self.closeNonRoot();
                try self.closeNonRoot();
            },
        }

        if (m.flags.starts_word) {
            try self.open("w");
            try self.endOpen();
        }

        try self.morpheme(book_, i);
    }

    for (0..self.tags.len) |_| try self.close();
    try self.tab();
}

const std = @import("std");
const Bible = @import("../Bible.zig");
const Morpheme = Bible.Morpheme;
