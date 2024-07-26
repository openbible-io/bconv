books: Books,
books_mutex: std.Thread.Mutex = .{},

pub const Books = std.AutoArrayHashMap(Bible.BookName, Elements);
pub const Elements = std.AutoArrayHashMapUnmanaged(u32, Bible.Element);

pub fn addText(self: *@This(), book: Bible.BookName, order: u32, text: Bible.Element) !void {
    const allocator = self.books.allocator;

    self.books_mutex.lock();
    const gop_book = try self.books.getOrPut(book);
    if (!gop_book.found_existing) gop_book.value_ptr.* = Elements{};
    self.books_mutex.unlock();

    try gop_book.value_ptr.putNoClobber(allocator, order, text);
}

pub fn toOwned(self: *@This()) !Bible {
    std.debug.print("size {d} {d}\n", .{ @sizeOf(Books), @sizeOf(Bible) });
    const allocator = self.books.allocator;
    var res = Bible.init(allocator);

    var iter = self.books.iterator();
    while (iter.next()) |kv| {
        std.debug.print("{s} {d}\n", .{ @tagName(kv.key_ptr.*), kv.value_ptr.*.entries.len });

        const SortCtx = struct {
            refs: []u32,

            pub fn lessThan(ctx: @This(), a_index: usize, b_index: usize) bool {
                return ctx.refs[a_index] < ctx.refs[b_index];
            }
        };
        kv.value_ptr.sortUnstable(SortCtx{.refs = kv.value_ptr.keys() });

        // TODO: lil ugly can't move one field of MultiArrayList
        const elements = try allocator.dupe(Bible.Element, kv.value_ptr.*.entries.items(.value));
        defer kv.value_ptr.clearAndFree(allocator);

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
const Allocator = std.mem.Allocator;
