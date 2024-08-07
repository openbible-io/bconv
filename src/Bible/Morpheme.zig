type: Type = .root,
strong: Strong = .{},
// code: Code = 0,
text: []const u8,

pub const Type = enum(u8) {
    root,
    prefix,
    suffix,
};

/// TODO: manual tags to make size 4 instead of 6
pub const Code = union(enum) {
    hebrew: Hebrew,
    aramaic: Aramaic,

    pub fn parse(c: []const u8) !@This() {
        if (c.len < 2) return error.MorphCodeLen;

        return switch (c[0]) {
            'H' => .{ .hebrew = try Hebrew.parse(c[1..]) },
            'A' => .{ .aramaic = try Aramaic.parse(c[1..]) },
            else => error.MorphCodeLang,
        };
    }

    pub fn write(self: @This(), writer: anytype) !void {
        switch (self) {
            .hebrew => |h| {
                try writer.writeByte('H');
                try h.write(writer);
            },
            .aramaic => |a| {
                try writer.writeByte('A');
                try a.write(writer);
            },
        }
    }
};

pub const Strong = packed struct(u32) {
    n: u16 = 0,
    lang: Lang = .hebrew,
    sense: u8 = 0,

    pub const Lang = enum (u8) { hebrew, aramaic, greek };

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
};

const std = @import("std");
const semitic = @import("./Morpheme/semitic.zig");
pub const Hebrew = semitic.Hebrew;
pub const Aramaic = semitic.Aramaic;

test {
    _ = semitic;
}
