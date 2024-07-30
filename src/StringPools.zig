pub var global: StringPools = undefined;

pub const StringPools = struct {
    pools: Pools,

    const Pools = std.EnumArray(Lang, StringPool);

    pub fn init(allocator: Allocator) @This() {
        return .{ .pools = Pools.initFill(StringPool.init(allocator)) };
    }

    pub fn deinit(self: *@This()) void {
        for (&self.pools.values) |*p| p.deinit();
    }

    pub fn getOrPutLang(self: *@This(), str: []const u8, lang: Lang) ![]const u8 {
        var pool = @call(std.builtin.CallModifier.always_inline, Pools.getPtr, .{ &self.pools, lang });
        return try pool.getOrPut(str);
    }

    pub const Lang = enum {
        unknown,
        semitic,
        greek,
        english,
    };
};

/// TODO: store semitic roots and cantilation/vowels separately for more deduping
pub const StringPool = struct {
    arena: std.heap.ArenaAllocator,
    items: std.StringHashMapUnmanaged([]const u8) = .{},
    mutex: std.Thread.Mutex = .{},

    pub fn init(allocator: Allocator) @This() {
        return .{ .arena = std.heap.ArenaAllocator.init(allocator) };
    }

    pub fn deinit(self: *@This()) void {
        self.items.deinit(self.arena.child_allocator);
        self.arena.deinit();
    }

    pub fn getOrPut(self: *@This(), str: []const u8) ![]const u8 {
        self.mutex.lock();
        const gop = try self.items.getOrPut(self.arena.child_allocator, str);
        if (!gop.found_existing) {
            gop.value_ptr.* = try self.arena.allocator().dupe(u8, str);
            gop.key_ptr.* = gop.value_ptr.*; // needs to be address stable
        }
        self.mutex.unlock();

        return gop.value_ptr.*;
    }
};

const std = @import("std");
const Allocator = std.mem.Allocator;

test StringPool {
    const allocator = std.testing.allocator;
    const lang = StringPools.Lang.unknown;

    var pool = StringPools.init(allocator);
    defer pool.deinit();

    const strings = [_][]const u8{
        "בְּ",
        "רֵאשִׁ֖ית",
        "בָּרָ֣א",
        "אֱלֹהִ֑ים",
        "אֵ֥ת",
        "הַ",
        "שָּׁמַ֖יִם",
        "וְ",
        "אֵ֥ת",
        "הָ",
        "אָֽרֶץ\\׃",
        "וְ",
        "הָ",
        "אָ֗רֶץ",
    };

    for (strings) |s| _ = try pool.getOrPutLang(s, lang);

    for (strings) |s| try std.testing.expectEqualStrings(s, try pool.getOrPutLang(s, lang));
}
