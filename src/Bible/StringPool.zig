buf: []const u8,
n_unique: Index = 0,

pub fn deinit(self: @This(), allocator: Allocator) void {
    allocator.free(self.buf);
}

pub fn get(self: @This(), index: Index) []const u8 {
    const len = self.buf[index];
    return self.buf[index + 1 ..][0..len];
}

pub const Builder = struct {
    buf: std.ArrayList(u8),
    map: std.StringArrayHashMapUnmanaged(Index) = .{},
    mutex: std.Thread.Mutex = .{},

    pub fn init(allocator: std.mem.Allocator) !@This() {
        var buf = std.ArrayList(u8).init(allocator);
        try buf.append(0); // reserve 0 to mean null
        return .{ .buf = buf };
    }

    pub fn deinit(self: *@This()) void {
        const allocator = self.buf.allocator;
        self.map.deinit(allocator);
        self.buf.deinit();
    }

    pub fn getOrPut(self: *@This(), str: []const u8) !Index {
        const allocator = self.buf.allocator;
        self.mutex.lock();
        const gop = try self.map.getOrPut(allocator, str);
        if (!gop.found_existing) {
            const res: Index = @intCast(self.buf.items.len);
            try self.buf.append(@intCast(str.len));
            try self.buf.appendSlice(str);
            gop.value_ptr.* = res;
        }
        self.mutex.unlock();

        return gop.value_ptr.*;
    }

    pub fn get(self: @This(), index: Index) []const u8 {
        const tmp = StringPool{ .buf = self.buf.items };
        return tmp.get(index);
    }

    pub fn toOwned(self: *@This()) !StringPool {
        return .{ .buf = try self.buf.toOwnedSlice(), .n_unique = @intCast(self.map.entries.len) };
    }
};

const std = @import("std");
pub const Index = u32;
const Allocator = std.mem.Allocator;
const StringPool = @This();
