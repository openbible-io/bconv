//! Goals:
//! - only store unambiguous parsings
//! - NO versification
//! - mutable
//! - no allocation
//! - fast to iterate over in order
//! - memory efficient
//! - diffable and alignable
//!
//! Non-goals:
//! - aligned for SSE
//! - chapters/verses
name: Name,
elements: []Element,

pub const Element = union(enum) {
    word: Word,
    punctuation: []const u8,
    quote: []TextElement,
    variant: []Option,
};

pub const TextElement = union(enum) {
    word: Word,
    punctuation: []const u8,
};

pub const Option = struct {
    source_set: SourceSet,
    children: []TextElement,
};

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

const std = @import("std");
pub const Tag = @import("./Tag.zig").Tag;
pub const Word = @import("./Word.zig");
pub const Morpheme = @import("./Morpheme.zig");
pub const SourceSet = @import("./source_set.zig").SourceSet;
pub const Reader = @import("./Book/Reader.zig");
pub const Writer = @import("./Book/Writer.zig");
pub const Name = @import("./Book/name.zig").Name;
pub const Stream = @import("./Book/Stream.zig");
const Book = @This();

test "Write + Read" {
    const allocator = std.testing.allocator;
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    var b = Writer{ .underlying = buffer.writer().any() };

    const word = Word{
        .ref = .{ .book = .gen, .chapter = 1, .verse = 1, .word = 1 },
        .morphemes = @constCast(&[_]Morpheme{
            .{
                .type = .prefix,
                .strong = .{ .n = 1, .lang = .greek, .sense = 'a' },
                .text = "pre",
            },
        }),
    };
    const book = Book{ .elements = [_]Element{ .{ .word = word } } };
    try b.append(Book, book);

    var expected = [_]u8{
        0x00, // word
        0x00, 0x01, 0x01, 0x01, // gen1:1#1
        0x01, // morph
        0x01, // prefix
        0x01, 0x00, 0x02, 0x61, // strong
        0x03, // "pre".len
        0x70, 0x72, 0x65, // "pre"
    };
    try std.testing.expectEqualSlices(u8, &expected, b.buf.items);

    var stream = std.io.fixedBufferStream(&expected);
    var reader = Reader{ .underlying = stream.reader().any() };

    var word_iter = (try reader.next()).?.word;
    try std.testing.expectEqual(word.ref, word_iter.ref);

    for (word.morphemes) |morph| {
        try std.testing.expectEqualDeep(morph, try word_iter.next());
    }
    try std.testing.expectEqual(null, try word_iter.next());
    try std.testing.expectEqual(null, try reader.next());
}
