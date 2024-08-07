/// A map allows an arbitrary number of books to be modified concurrently.
books: std.AutoArrayHashMap(Book.Name, Book),

const std = @import("std");
const mod = @import("./Bible/mod.zig");
pub const Book = mod.Book;
pub const Word = mod.Word;
pub const Builder = mod.Builder;
pub const SourceSet = mod.SourceSet;
