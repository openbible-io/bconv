source_set: SourceSet = .{},
flags: Flags = .{},
text: StringPool.Index = 0,
strong: Strong = .{},
code: Code = .{},

pub const Flags = packed struct(u8) {
    is_variant: bool = false,
    /// prevents requiring lookbehind on `type` for word iteration
    /// also prevents highjacking another field when parsing STEP amalgamated
    starts_word: bool = false,
    type: Type = .root,
    _padding: u4 = 0,
};
pub const Type = enum(u2) { root, prefix, suffix, punctuation };
pub const Lang = enum(u8) { hebrew, aramaic, greek };

pub const Code = packed struct(u32) {
    tag: Lang = .hebrew,
    value: packed union { hebrew: Hebrew, aramaic: Aramaic, greek: Aramaic } = undefined,
    _padding: u2 = 0,

    pub fn parse(c: []const u8) !@This() {
        if (c.len < 2) return error.MorphCodeLen;

        return switch (c[0]) {
            'H' => .{ .tag = .hebrew, .value = try Hebrew.parse(c[1..]) },
            'A' => .{ .tag = .aramaic, .value = try Aramaic.parse(c[1..]) },
            'G' => .{ .tag = .greek, .value = undefined },
            else => error.MorphCodeLang,
        };
    }

    pub fn write(self: @This(), writer: anytype) !void {
        switch (self.tag) {
            .hebrew => {
                try writer.writeByte('H');
                try self.value.hebrew.write(writer);
            },
            .aramaic => {
                try writer.writeByte('A');
                try self.value.aramaic.write(writer);
            },
            .greek => {
                try writer.writeByte('G');
                try self.value.greek.write(writer);
            },
        }
    }

    pub fn isNull(self: @This()) bool {
        return @as(u32, @bitCast(self)) == 0;
    }
};

pub const Strong = packed struct(u32) {
    n: u16 = 0,
    lang: Lang = .hebrew,
    sense: u8 = 0,

    pub fn parse(in: []const u8) !@This() {
        if (in.len == 0) return error.StrongEmpty;
        const lang: Lang = switch (std.ascii.toLower(in[0])) {
            'h' => .hebrew,
            'a' => .aramaic,
            'g' => .greek,
            else => return error.StrongInvalidLang,
        };
        var i: usize = 1;
        while (i < in.len and std.ascii.isDigit(in[i])) : (i += 1) {}
        const n = try std.fmt.parseInt(u16, in[1..i], 10);
        const sense = if (in.len == i + 1 and std.ascii.isAlphabetic(in[i])) in[i] else 0;

        return .{  .n = n, .lang = lang, .sense = sense };
    }

    pub fn write(self: @This(), writer: anytype) !void {
        try writer.writeByte(switch (self.lang) {
            .hebrew => 'H',
            .aramaic => 'A',
            .greek => 'G',
            });
        try writer.print("{d:0>4}", .{ self.n });
        if (self.sense != 0) try writer.writeByte(self.sense);
    }

    pub fn isNull(self: @This()) bool {
        return @as(u32, @bitCast(self)) == 0;
    }
};

const std = @import("std");
const semitic = @import("./Morpheme/semitic.zig");
const StringPool = @import("./StringPool.zig");
pub const Hebrew = semitic.Hebrew;
pub const Aramaic = semitic.Aramaic;
pub const SourceSet = @import("./source_set.zig").SourceSet;

test {
    _ = semitic;
}
