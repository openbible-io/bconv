pub const Morpheme = packed struct(u64) {
    starts_word: bool = false,
    starts_variant: bool = false,
    text: u16 = 0,

    type: Type = .unknown,
    // TODO: make smaller
    // strong: Strong = .{},
    // code: Code = .{},
};

pub const Type = enum(u2) { unknown, root, prefix, suffix };

pub const Strong = packed struct(u22) {
    n: N = 0,
    sense: u8 = 0,

    const N = std.math.IntFittingRange(0, 10000); // u14

    pub fn parse(in: []const u8) !@This() {
        if (in.len == 0) return error.StrongEmpty;
        var i: usize = 0;
        while (i < in.len and std.ascii.isDigit(in[i])) : (i += 1) {}
        const n = try std.fmt.parseInt(N, in[0..i], 10);
        const sense = if (in.len == i + 1 and std.ascii.isAlphabetic(in[i])) in[i] else 0;

        return .{  .n = n, .sense = sense };
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

pub const Code = packed union {
    hebrew: Hebrew,
    aramaic: Aramaic,

    pub fn write(self: @This(), writer: anytype) !void {
        switch (writer.lang) {
            .unknown => {
                try writer.writeByte('U');
            },
            .hebrew => {
                try writer.writeByte('H');
                try self.hebrew.write(writer);
            },
            .aramaic => {
                try writer.writeByte('A');
                try self.aramaic.write(writer);
            },
        }
    }
};

const std = @import("std");
const semitic = @import("./Morpheme/semitic.zig");
const String = @import("./string.zig").String;
pub const Hebrew = semitic.Hebrew;
pub const Aramaic = semitic.Aramaic;

test {
    _ = semitic;
}
