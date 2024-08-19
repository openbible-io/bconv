//! Goals:
//! - diffable and alignable
//! - memory efficient
//! - NO versification
//! - mutable
//! - fast to iterate over in order
//!
//! Non-goals:
//! - chapters/verses
name: Name,
pool: StringPool,
morphemes: []Morpheme,

pub fn deinit(self: *@This(), allocator: Allocator) void {
   allocator.free(self.morphemes);
   self.pool.deinit(allocator);
}

pub fn normalize(self: *@This()) !void {
    try self.normalizeVariants();
    // Take a guess based off length at which one is root.
    // var seen_root = false;
    // for (morphs) |*m| {
    //     const is_root = !seen_root and m.text.len == max_byte_len;
    //     seen_root = is_root;
    //     m.type = if (is_root) .root else if (seen_root) .suffix else .prefix;
    // }
}

fn normalizeVariants(self: *@This()) !void {
    _ = self;
    // v
    //  o w a w xyz
    //  o w b w xyz
    // e
    // v
    //  o w a
    //  o w b
    // e 0000
    // w xyz
}

pub const Builder = struct {
    name: Name,
    pool: StringPool.Builder,
    morphemes: std.ArrayList(Morpheme),

    pub fn init(allocator: Allocator, name: Name) !@This() {
        return .{
            .name = name,
            .pool = try StringPool.Builder.init(allocator),
            .morphemes = std.ArrayList(Morpheme).init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.morphemes.deinit();
        self.pool.deinit();
    }

    pub fn toOwned(self: *@This()) !Book {
        return .{
            .name = self.name,
            .pool = try self.pool.toOwned(),
            .morphemes = try self.morphemes.toOwnedSlice(),
        };
    }
};

const std = @import("std");
pub const Morpheme = @import("./Morpheme.zig");
pub const Name = @import("./Book/name.zig").Name;
pub const StringPool = @import("./StringPool.zig");
const Book = @This();
const Allocator = std.mem.Allocator;