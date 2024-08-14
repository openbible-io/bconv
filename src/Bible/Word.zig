language: Language,
morphemes: []Morpheme,

// pub const Reference = packed struct(u32) {
//     book: Book.Name,
//     chapter: u8,
//     verse: u8,
//     word: u8,
//
//     pub fn write(self: @This(), writer: anytype) !void {
//         try writer.print("{s}{d}:{d}#{d}", .{ @tagName(self.book), self.chapter, self.verse, self.word },);
//     }
// };

pub const Packed = packed struct(u64) {
    language: Language = .unknown,
    n_morphemes: u8,

    pub fn unpack(self: *@This()) Word {
        var morphemes: []Morpheme = undefined;
        morphemes.len = self.n_morphemes;
        morphemes.ptr = @ptrCast(@alignCast(self + @sizeOf(@This())));
        return .{ .language = self.language, .morphemes = morphemes };
    }
};

const std = @import("std");
const Language = @import("./language.zig").Language;
const Morpheme = @import("./Morpheme.zig");
const Book = @import("./Book.zig");
const Word = @This();
