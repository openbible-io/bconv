tags: Tags = .{},
text: StringPool.Index = 0,
strong_n: u16 = 0,
strong_sense: u8 = 0,
grammar: Grammar = .{ .hebrew = .{} },

pub const Tags = packed struct(u32) {
    source: SourceSet = .{},
    variant: Variant = .none,
    type: Type = .root,
    lang: Lang = .unknown,
    _padding: u11 = 0,

    pub const Type = enum(u2) { root, prefix, suffix, punctuation };
    pub const Variant = enum(u2) {
        none,
        start,
        /// last morpheme, not last variant start
        end,
    };
};

pub const Lang = enum(u2) { unknown, hebrew, aramaic, greek };
pub const Grammar = packed union {
    hebrew: Hebrew,
    aramaic: Aramaic,
    greek: Aramaic,

    pub fn isNull(self: @This()) bool {
        const T = std.meta.Int(.unsigned, @bitSizeOf(@This()));
        return @as(T, @bitCast(self)) == 0;
    }
};

pub fn writeStrong(self: @This(), writer: anytype) !void {
    try writer.writeByte(switch (self.tags.lang) {
        .unknown => return,
        .hebrew, .aramaic => 'H',
        .greek => 'G',
    });
    try writer.print("{d:0>4}", .{self.strong_n});
    if (self.strong_sense != 0) try writer.writeByte(self.strong_sense);
}

pub fn writeGrammar(self: @This(), writer: anytype) !void {
    if (self.grammar.isNull()) return;
    switch (self.tags.lang) {
        .unknown => return,
        .hebrew => {
            try writer.writeByte('H');
            try self.grammar.hebrew.write(writer);
        },
        .aramaic => {
            try writer.writeByte('A');
            try self.grammar.aramaic.write(writer);
        },
        .greek => {
            try writer.writeByte('G');
            try self.grammar.greek.write(writer);
        },
    }
}

const std = @import("std");
const semitic = @import("./Morpheme/semitic.zig");
const StringPool = @import("./StringPool.zig");
pub const Hebrew = semitic.Hebrew;
pub const Aramaic = semitic.Aramaic;
pub const SourceSet = @import("./source_set.zig").SourceSet;

test {
    _ = semitic;
}
