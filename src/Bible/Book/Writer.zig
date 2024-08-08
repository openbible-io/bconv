//! A tag + value structure with delimiter tags for variants.
//!
//!  tag  ref
//!    w gen1:1#1
//!       tag type code strg  str
//!         m  pre   HR 9003   בְּ
//!  tag
//!    v
//!       tag  tag  ...
//!         o    w  ...
//!       tag  tag  ...
//!         o    w  ...
//!  tag
//!  end
//!  tag  val
//!    p    :
underlying: std.io.AnyWriter,

pub fn appendTag(self: @This(), tag: Tag) !void {
    try self.underlying.writeByte(@intFromEnum(tag));
}

pub fn appendInt(self: @This(), comptime T: type, value: T) !void {
    try self.underlying.writeInt(T, value, .little);
}

pub fn appendEnum(self: @This(), comptime T: type, value: T) !void {
    try self.appendInt(@typeInfo(T).Enum.tag_type, @intFromEnum(value));
}

pub fn appendString(self: @This(), string: []const u8) !void {
    try self.underlying.writeByte(@intCast(string.len));
    try self.underlying.writeAll(string);
}

pub fn append(self: @This(), comptime T: type, value: T) !void {
    switch (@typeInfo(T)) {
        .Struct => |s| {
            if (s.backing_integer) |Int| return try self.appendInt(Int, @bitCast(value));
            try self.appendTag(Tag.fromType(T));
            inline for (s.fields) |f| try append(self, f.type, @field(value, f.name));
        },
        .Int => try self.appendInt(T, value),
        .Enum => try self.appendEnum(T, value),
        .Pointer => |p| {
            if (p.size != .Slice) @compileError("can only serialize slices");
            if (p.child == u8 and p.is_const) return try self.appendString(value);

            for (value) |v| try self.append(p.child, v);
        },
        else => {
            if (!std.meta.hasUniqueRepresentation(T))
                @compileError(@typeName(T) ++ " must have a unique representation");

            @compileError("TODO: serialize " ++ @typeName(T));
        },
    }
}

const std = @import("std");
const mod = @import("../mod.zig");
const Builder = @This();
const Word = mod.Word;
const Morpheme = mod.Morpheme;
const Tag = mod.Tag;
