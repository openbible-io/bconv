books: Books,
text_elements: std.ArrayListUnmanaged(Bible.TextElement),

pub const Books = std.AutoArrayHashMap(Bible.BookName, Chapters);
pub const Chapters = std.ArrayListUnmanaged(Verses);
// pub const Chapters = std.AutoArrayHashMapUnmanaged(u8, *Verses);
// pub const Verses = std.AutoArrayHashMapUnmanaged(u8, *TextElements);

pub fn addText(self: *@This(), ref: Bible.VerseReference, text: Bible.TextElement) !void {
    var gop_chapters = self.books.get(ref.book);
    const allocator = self.allocator;

    const gop_verses = try gop_chapters.getOrPut(allocator, ref.chapter);
    if (!gop_verses.found_existing) {
        gop_verses.value_ptr.* = try allocator.create(Verses);
        gop_verses.value_ptr.*.* = .{};
        // std.debug.print("sad {s} {d}\n", .{ @tagName(ref.book), ref.chapter });
    } else {
        std.debug.print("YAY\n", .{});
    }

    const gop_text_elements = try gop_verses.value_ptr.*.getOrPut(allocator, ref.verse);
    if (!gop_text_elements.found_existing) {
        gop_text_elements.value_ptr.* = try allocator.create(TextElements);
        gop_text_elements.value_ptr.*.* = .{};
    }

    try gop_text_elements.value_ptr.*.append(allocator, text);
}

pub fn toOwned(self: *@This()) !Bible {
    std.debug.print("size {d} {d}\n", .{ @sizeOf(Books), @sizeOf(Bible) });
    const allocator = self.allocator;
    var res = Bible{};

    var iter = self.books.iterator();
    while (iter.next()) |kv| {
        var verses_res = std.ArrayList(Bible.Verses).init(allocator);
        defer verses_res.deinit();

        const chapters: Chapters = kv.value.*;
        const chapter_keys = try sortedKeys(allocator, chapters);
        defer chapter_keys.deinit();

        std.debug.print("{s} {d}\n", .{ @tagName(kv.key), chapter_keys.items.len });
        for (chapter_keys.items) |c_num| {
            var verse_res = std.ArrayList(Bible.TextElement).init(allocator);
            defer verse_res.deinit();

            const verses: Verses = chapters.get(c_num).?.*;
            const verses_keys = try sortedKeys(allocator, verses);
            defer verses_keys.deinit();

            for (verses_keys.items) |v_num| {
                var unowned: TextElements = verses.get(v_num).?.*;
                const text_elements: Bible.Verses = try unowned.toOwnedSlice(allocator);
                try verse_res.appendSlice(text_elements);
            }

            try verses_res.append(try verse_res.toOwnedSlice());
        }

        res.books.set(kv.key, try verses_res.toOwnedSlice());
    }
    return res;
}

pub fn deinit(self: *@This()) void {
    _ = self;
}

fn sortedKeys(allocator: Allocator, array_hash_unmanaged: anytype) !std.ArrayList(u8) {
    var res = std.ArrayList(u8).init(allocator);

    for (array_hash_unmanaged.keys()) |k| try res.append(k);
    std.mem.sort(u8, res.items, {}, comptime std.sort.asc(u8));

    return res;
}

const std = @import("std");
const Bible = @import("./Bible.zig");
const Allocator = std.mem.Allocator;
