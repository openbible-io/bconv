books: std.AutoArrayHashMap(Book.Name, Book.Writer),
books_mutex: std.Thread.Mutex = .{},

pub fn getBook(self: *@This(), book: Book.Name) !*Book.Writer {
    self.books_mutex.lock();
    const gop_book = try self.books.getOrPut(book);
    if (!gop_book.found_existing) gop_book.value_ptr.* = Book.Writer{};
    self.books_mutex.unlock();

    return gop_book.value_ptr;
}

pub fn toOwned(self: *@This()) !Bible {
    const allocator = self.books.allocator;
    var res = Bible.init(allocator);

    var iter = self.books.iterator();
    while (iter.next()) |kv| {
        std.debug.print("{s} {d}\n", .{ @tagName(kv.key_ptr.*), kv.value_ptr.*.items.len });

        const elements = try kv.value_ptr.toOwnedSlice(allocator);
        try res.books.putNoClobber(kv.key_ptr.*, .{ .elements = elements });
    }
    self.books.clearAndFree();
    return res;
}

pub fn init(allocator: Allocator) @This() {
    return .{ .books = std.meta.FieldType(@This(), .books).init(allocator) };
}

pub fn deinit(self: *@This()) void {
    const allocator = self.books.allocator;
    var iter = self.books.iterator();
    while (iter.next()) |kv| kv.value_ptr.deinit(allocator);
    self.books.deinit();
}

const std = @import("std");
const Book = @import("./Book.zig");
const Bible = @import("../Bible.zig");
const Allocator = std.mem.Allocator;
