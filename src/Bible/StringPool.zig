arena: std.heap.ArenaAllocator,
items: std.StringArrayHashMapUnmanaged([]const u8) = .{},
mutex: std.Thread.Mutex = .{},

pub fn init(allocator: std.mem.Allocator) @This() {
    return .{ .arena = std.heap.ArenaAllocator.init(allocator) };
}

pub fn deinit(self: *@This()) void {
    self.items.deinit(self.arena.child_allocator);
    self.arena.deinit();
}

pub fn getOrPut(self: *@This(), str: []const u8) !Index {
    self.mutex.lock();
    const gop = try self.items.getOrPut(self.arena.child_allocator, str);
    if (!gop.found_existing) {
        gop.value_ptr.* = try self.arena.allocator().dupe(u8, str);
    }
    self.mutex.unlock();

    return @intCast(gop.index);
}

pub var global = init(std.heap.page_allocator);
pub const Index = u32;

const std = @import("std");
