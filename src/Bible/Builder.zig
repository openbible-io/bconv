books: std.AutoArrayHashMap(Book.Name, BookBuilder),
books_mutex: std.Thread.Mutex = .{},

pub const BookBuilder = struct {
    buf: std.ArrayList(u8),

    pub fn init(allocator: Allocator) BookBuilder {
        return .{ .buf = std.ArrayList(u8).init(allocator) };
    }

    pub fn deinit(self: *@This()) void {
        self.buf.deinit();
    }

    pub fn writer(self: *@This()) Book.Writer {
        return Book.Writer{ .underlying = self.buf.writer().any() };
    }
};

pub fn init(allocator: Allocator) @This() {
    return .{ .books = std.meta.FieldType(@This(), .books).init(allocator) };
}

pub fn deinit(self: *@This()) void {
    var iter = self.books.iterator();
    while (iter.next()) |kv| kv.value_ptr.deinit();
    self.books.deinit();
}

pub fn getBook(self: *@This(), book: Book.Name) !*BookBuilder {
    const allocator = self.books.allocator;
    self.books_mutex.lock();
    const gop_book = try self.books.getOrPut(book);
    if (!gop_book.found_existing) gop_book.value_ptr.* = BookBuilder.init(allocator);
    self.books_mutex.unlock();

    return gop_book.value_ptr;
}

pub fn toOwned(self: *@This()) !Bible {
    const allocator = self.books.allocator;
    var res = Bible.init(allocator);
    var iter = self.books.iterator();
    while (iter.next()) |kv| {
        const owned = try kv.value_ptr.*.buf.toOwnedSlice();
        try res.books.put(kv.key_ptr.*, owned);
    }
    return res;
}

const std = @import("std");
const Bible = @import("../Bible.zig");
const Book = @import("./Book.zig");
const Allocator = std.mem.Allocator;
