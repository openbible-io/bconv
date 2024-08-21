books: std.AutoArrayHashMap(Book.Name, Book.Builder),
books_mutex: std.Thread.Mutex = .{},

pub fn init(allocator: Allocator) @This() {
    return .{ .books = std.meta.FieldType(@This(), .books).init(allocator) };
}

pub fn deinit(self: *@This()) void {
    var iter = self.books.iterator();
    while (iter.next()) |kv| kv.value_ptr.deinit();
    self.books.deinit();
}

pub fn getBook(self: *@This(), book: Book.Name, source: Bible.SourceSet) !*Book.Builder {
    const allocator = self.books.allocator;
    self.books_mutex.lock();
    const gop_book = try self.books.getOrPut(book);
    if (!gop_book.found_existing) gop_book.value_ptr.* = try Book.Builder.init(allocator, book, source);
    self.books_mutex.unlock();

    return gop_book.value_ptr;
}

pub fn toOwned(self: *@This()) !Bible {
    const allocator = self.books.allocator;
    var res = Bible.init(allocator);
    var iter = self.books.iterator();
    while (iter.next()) |kv| {
        const owned = try kv.value_ptr.toOwned();
        try res.books.put(kv.key_ptr.*, owned);
    }
    return res;
}

const std = @import("std");
const Bible = @import("../Bible.zig");
const Book = @import("./Book.zig");
const StringPool = @import("./StringPool.zig");
const Allocator = std.mem.Allocator;
