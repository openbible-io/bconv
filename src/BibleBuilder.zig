books: Books,
books_mutex: std.Thread.Mutex = .{},

pub const Books = std.AutoArrayHashMap(Bible.BookName, Elements);
pub const Elements = std.ArrayListUnmanaged(Bible.Element);

pub fn appendElement(self: *@This(), book: Bible.BookName, text: Bible.Element) !void {
    const allocator = self.books.allocator;

    self.books_mutex.lock();
    const gop_book = try self.books.getOrPut(book);
    if (!gop_book.found_existing) gop_book.value_ptr.* = Elements{};
    self.books_mutex.unlock();

    try gop_book.value_ptr.append(allocator, text);
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
    return .{ .books = Books.init(allocator) };
}

pub fn deinit(self: *@This()) void {
    const allocator = self.books.allocator;
    var iter = self.books.iterator();
    while (iter.next()) |kv| kv.value_ptr.deinit(allocator);
    self.books.deinit();
}

const std = @import("std");
const Bible = @import("./Bible.zig");
const morph = @import("./morphology/mod.zig");
const Allocator = std.mem.Allocator;
