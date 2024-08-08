/// A map allows an arbitrary number of books to be modified concurrently.
books: Books,

const Books = std.AutoArrayHashMap(Book.Name, []const u8);

pub fn init(allocator: std.mem.Allocator) @This() {
    return .{ .books = Books.init(allocator) };
}

pub fn deinit(self: *@This()) void {
    const allocator = self.books.allocator;
    for (self.books.values()) |v| allocator.free(v);
    self.books.deinit();
}

const std = @import("std");
const mod = @import("./Bible/mod.zig");
pub const Book = mod.Book;
pub const Element = Book.Element;
pub const TextElement = Book.TextElement;
pub const Word = mod.Word;
pub const Morpheme = mod.Morpheme;
pub const Builder = mod.Builder;
pub const SourceSet = mod.SourceSet;
pub const Tag = mod.Tag;
