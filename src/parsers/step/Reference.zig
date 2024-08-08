book: Bible.Book.Name,
chapter: u8,
verse: u8,
word: u8,
primary: SourceSet,
variants: [max_variants]SourceSet = [_]SourceSet{.{}} ** max_variants,

/// 6 =L(b; p)
/// 1 =Q(K; B)
pub const max_variants = 2;

pub fn parse(ref: []const u8) !@This() {
    const first_dot = std.mem.indexOfScalar(u8, ref, '.') orelse return error.MissingFirstDot;
    const second_dot = std.mem.indexOfScalarPos(u8, ref, first_dot + 1, '.') orelse return error.MissingSecondDot;

    const book_str = ref[0..first_dot];
    const book = try Bible.Book.Name.fromEnglish(book_str);

    const chapter_str = ref[first_dot + 1..second_dot];
    const chapter = try std.fmt.parseInt(u8, chapter_str, 10);

    const verse_end = std.mem.indexOfAnyPos(u8, ref, second_dot + 1, "(#") orelse return error.MissingVerseEnd;
    const verse_str = ref[second_dot + 1..verse_end];
    const verse = try std.fmt.parseInt(u8, verse_str, 10);

    const word_start = std.mem.indexOfScalarPos(u8, ref, verse_end, '#') orelse return error.MissingWordStart;
    const source_start = std.mem.lastIndexOfScalar(u8, ref, '=') orelse return error.MissingSourceStart;

    const word_str = ref[word_start + 1..source_start];
    const word = try std.fmt.parseInt(u8, word_str, 10);

    const source_end = std.mem.indexOfScalarPos(u8, ref, source_start, '(') orelse ref.len;
    const source_str = ref[source_start + 1..source_end];
    const primary =  try SourceSet.parse(source_str);

    var variants = [_]SourceSet{.{}} ** max_variants;
    if (source_end != ref.len) {
        const variant_end = std.mem.lastIndexOfScalar(u8, ref, ')') orelse return error.MissingVariantEnd;
        var split = std.mem.splitScalar(u8, ref[source_end + 1..variant_end], ';');
        var j: usize = 0;
        while (split.next()) |s| : (j += 1) {
            if (j > variants.len) return error.TooManyVariants;
            variants[j] = try SourceSet.parse(s);
        }
    }
    return .{
        .book = book,
        .chapter = chapter,
        .verse = verse,
        .word = word,
        .primary = primary,
        .variants = variants,
    };
}

test {
    try std.testing.expectEqual(Reference{
        .book = .gen,
        .chapter = 1,
        .verse = 2,
        .word = 3,
        .primary = SourceSet{ .is_significant = true, .leningrad = true },
    }, try Reference.parse("Gen.1.2#03=L"));

    try std.testing.expectEqual(Reference{
        .book = .gen,
        .chapter = 1,
        .verse = 2,
        .word = 3,
        .primary = SourceSet{ .is_significant = true, .leningrad = true },
        .variants = [_]SourceSet{
            .{ .bhs = true },
            .{ .punctuation = true },
        },
    }, try Reference.parse("Gen.1.2(2.3)#03=L(b; p)"));

    try std.testing.expectEqual(Reference{
        .book = .gen,
        .chapter = 10,
        .verse = 20,
        .word = 30,
        .primary = SourceSet{ .is_significant = true, .leningrad = true },
        .variants = [_]SourceSet{
            .{ .bhs = true },
            .{ .punctuation = true },
        },
    }, try Reference.parse("Gen.10.20(2.3)#30=L(b; p)"));

    try std.testing.expectEqual(Reference{
        .book = .gen,
        .chapter = 31,
        .verse = 55,
        .word = 12,
        .primary = SourceSet{ .is_significant = true, .leningrad = true },
    }, try Reference.parse("Gen.31.55(32.1)#12=L"));
}

const std = @import("std");
const Bible = @import("../../Bible.zig");
const SourceSet = Bible.SourceSet;
const Reference = @This();
