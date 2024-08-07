ref: Reference,
morphemes: []Morpheme,

pub const Reference = packed struct(u32) {
    book: Book.Name,
    chapter: u8,
    verse: u8,
    word: u8,

    pub fn write(self: @This(), writer: anytype) !void {
        try writer.print("{s}{d}:{d}#{d}", .{ @tagName(self.book), self.chapter, self.verse, self.word },);
    }
};

const Morpheme = @import("./Morpheme.zig");
const Book = @import("./Book.zig");
const std = @import("std");
