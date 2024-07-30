pub const semitic = @import("./semitic.zig");
pub const Hebrew = semitic.Hebrew;
pub const Aramaic = semitic.Aramaic;

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

test {
    _ = semitic;
}
