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
            const tag = @tagName(Tag.fromType(T));
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
    if (@hasDecl(T, "write")) {
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

pub fn book(self: *@This(), reader: *Bible.Book.Reader) !void {
    var next = try reader.next();
    while (next != null) : (next = try reader.next()) switch (next.?) {
        .word => |*w| {
            try self.open("w");
            try self.anyAttribute("ref", Bible.Word.Reference, w.ref);
            try self.endOpen();
            while (try w.next()) |m| {
                try self.open("m");
                try self.attribute("type", @tagName(m.type));
                try self.anyAttribute("strong", Bible.Morpheme.Strong, m.strong);
                try self.anyAttribute("code", Bible.Morpheme.Code, m.code);
                try self.endOpen();
                try self.text(m.text);
                try self.end("m");
            }
            try self.end("w");
        },
    };
}

const std = @import("std");
const Bible = @import("../Bible.zig");
const Tag = Bible.Tag;
