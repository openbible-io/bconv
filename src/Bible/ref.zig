const book = @import("./book.zig");

/// Book, chapter, verse
pub const Bcv = struct {
    verse: u8,
    chapter: u8,
    book: book.Name,

    pub fn lessThan(self: @This(), other: @This()) bool {
        const self_book = @intFromEnum(self.book);
        const other_book = @intFromEnum(self.book);
        return self_book < other_book or self.chapter < other.chapter or self.verse < other.verse;
    }

    pub fn toCv(self: @This()) Cv {
        return .{ .chapter = self.chapter, .verse = self.verse };
    }
};

/// Chapter, verse
pub const Cv = packed struct(u16) {
    verse: u8,
    chapter: u8,

    pub fn lessThan(self: @This(), other: @This()) bool {
        return self.chapter < other.chapter or self.verse < other.verse;
    }
};

/// Chapter, verse, word number
pub const Cvw = packed struct(u24) {
    word: u8,
    verse: u8,
    chapter: u8,

    pub fn lessThan(self: @This(), other: @This()) bool {
        return self.chapter < other.chapter or self.verse < other.verse or self.word < other.word;
    }
};
