const std = @import("std");
const Bible = @import("./Bible.zig");
const BibleBuilder = @import("./BibleBuilder.zig");

const Allocator = std.mem.Allocator;

pub const Reference = struct {
    book: Bible.BookName,
    chapter: u8,
    verse: u8,
    word: u8,
    primary: SourceSet,
    variants: [4]SourceSet,

    pub const SourceSet = packed struct {
        is_significant: bool = false,
        leningrad: bool = false,
        restored: bool = false, // from Leningrad parallels
        lxx: bool = false,
        qere: bool = false, // spoken: scribal sidenotes/footnotes
        ketiv: bool = false, // written tradition

        pub fn parse(str: []const u8) !@This() {
            var res = @This(){ .is_significant = std.ascii.isUpper(str[0]) };
            for (str) |c| {
                if (std.ascii.isUpper(c) != res.is_significant) {
                    std.debug.print("invalid source set {s}\n", .{ str });
                    return error.SignficantMismatch;
                }
                switch (std.ascii.toLower(c)) {
                    'l' => res.leningrad = true,
                    'r' => res.restored = true,
                    'x' => res.lxx = true,
                    'q' => res.qere = true,
                    'k' => res.ketiv = true,
                    else => return error.InvalidSource,
                }
            }

            return res;
        }
    };

    pub fn parse(ref: []const u8) !@This() {
        if (ref.len < "Deu.34.12#01=L".len) return error.SmallRef;
        if (ref[3] != '.' or ref[6] != '.') return error.InvalidRef;

        const book_str = ref[0..3];
        const book = try Bible.BookName.fromEnglish(book_str);
        var i: usize = 3;
        if (ref[i] == '(') {
            while (ref[i] != ')') : (i += 1) {}
        }
        i += 1;

        const chapter = try std.fmt.parseInt(u8, ref[i..i+2], 10);
        i += 3;
        const verse = try std.fmt.parseInt(u8, ref[i..i+2], 10);
        i += 3;
        const word = try std.fmt.parseInt(u8, ref[i..i+2], 10);
        i += 3;

        const primary_sourceset_start = i;
        for (ref[i..]) |c| {
            if (c == '(') break;
            i += 1;
        }
        const primary =  try SourceSet.parse(ref[primary_sourceset_start..i]);

        var variants = [_]SourceSet{.{}} ** 4;
        if (i < ref.len and ref[i] == '(') {
            i += 1;
            var split = std.mem.splitScalar(u8, ref[i..ref.len - 1], ';');
            var j: usize = 0;
            while (split.next()) |s| : (j += 1) {
                if (j > variants.len) return error.TooManyVariants;
                variants[j] = try SourceSet.parse(s);
            }
        }

        const v0: u6 = @bitCast(variants[0]);
        std.debug.assert(v0 != 0 or std.mem.indexOfScalar(u8, ref, '(') == null);

        return .{
            .book = book,
            .chapter = chapter,
            .verse = verse,
            .word = word,
            .primary = primary,
            .variants = variants,
        };
    }
};

fn parseMorphemes(
    allocator: Allocator,
    text: []const u8,
    strong: []const u8,
    grammar: []const u8,
) ![]const Bible.Word.Morpheme {
    var morphemes = std.ArrayList(Bible.Word.Morpheme).init(allocator);
    defer morphemes.deinit();

    var text_iter = std.mem.splitScalar(u8, text, '/');
    var strong_iter = std.mem.splitScalar(u8, strong, '/');
    var grammar_iter = std.mem.splitScalar(u8, grammar, '/');

    var seen_root = false;
    while (true) {
        const next_morph = text_iter.next();
        const next_strong = strong_iter.next();
        const next_grammar = grammar_iter.next();

        if (next_morph == null and next_strong == null and next_grammar == null) break;
        const m = std.mem.trim(u8, next_morph orelse return error.MissingMorph, " ");
        const s = std.mem.trim(u8, next_strong orelse return error.MissingStrong, " ");
        const g = std.mem.trim(u8, next_grammar orelse return error.MissingGrammar, " ");

        const is_root = s[0] == '{';
        defer seen_root = is_root;

        const strong_parsed = try Bible.Word.Morpheme.Strong.parse(s[if (is_root) 1 else 0..]);
        // TODO: string pool
        const code = try allocator.dupe(u8, g);
        const owned = try allocator.dupe(u8, m);

        try morphemes.append(.{
            .type = if (is_root) .root else if (seen_root) .suffix else .prefix,
            .code = code,
            .strong = strong_parsed,
            .text = owned,
        });
    }

    return try morphemes.toOwnedSlice();
}

fn parseLine2(allocator: Allocator, line: []const u8, out: *BibleBuilder) !void {
    _ = .{ out };

    var fields = std.mem.splitScalar(u8, line, '\t');
    // NRSV(Heb) Ref & type
    const ref_type = fields.first();
    const ref = Reference.parse(ref_type) catch return;

    const hebrew = fields.next() orelse return error.MissingField;
    _ = fields.next() orelse return error.MissingField; // transliteration
    _ = fields.next() orelse return error.MissingField; // translation
    const strong = fields.next() orelse return error.MissingField;
    const grammar = fields.next() orelse return error.MissingField;
    _ = fields.next() orelse return error.MissingField; // meaning variant
    _ = fields.next() orelse return error.MissingField; // spelling variant
    _ = fields.next() orelse return error.MissingField; // Root dStrong+Instance
    _ = fields.next() orelse return error.MissingField; // alt Strongs+Instance
    _ = fields.next() orelse return error.MissingField; // conjoin word
    _ = fields.next() orelse return error.MissingField; // expanded Strong tags

    var hebrew_split = std.mem.splitSequence(u8, hebrew, "//");
    var strong_split = std.mem.splitSequence(u8, strong, "//");
    var grammar_split = std.mem.splitSequence(u8, grammar, "//");
    var i: u8 = 0;
    while (true) : (i += 1) {
        const next_hebrew = hebrew_split.next();
        const next_strong = strong_split.next();
        const next_grammar = grammar_split.next();

        if (next_hebrew == null and next_strong == null and next_grammar == null) break;

        const morphemes = try parseMorphemes(
            allocator,
            next_hebrew orelse return error.MissingMorph,
            next_strong orelse return error.MissingStrong,
            next_grammar orelse return error.MissingGrammar,
        );
        const word = Bible.Word{
            .id = .{ .book = ref.book, .chapter = ref.chapter, .verse = ref.verse, .word = i + 1 },
            .morphemes = morphemes,
        };
        try out.addText(
            .{ .book = ref.book, .chapter = ref.chapter, .verse = ref.verse },
            .{ .w = word },
        );
    }
}

fn parseLine(allocator: Allocator, line: []const u8, line_no: usize, out: *BibleBuilder) !void {
    parseLine2(allocator, line, out) catch |e| {
        std.debug.print("{} on line {d}\n", .{ e, line_no });
        std.debug.print("{s}\n", .{ line });
    };
}

pub fn parseTxt(allocator: Allocator, fname: []const u8, out: *Bible) !void {
    var file = try std.fs.cwd().openFile(fname, .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    const reader = buf_reader.reader();

    var line = try std.ArrayList(u8).initCapacity(allocator, 4096);
    defer line.deinit();

    var builder = BibleBuilder{ .allocator = allocator };
    defer builder.deinit();

    const writer = line.writer();
    var line_no: usize = 0;
    while (reader.streamUntilDelimiter(writer, '\n', null)) {
        defer line.clearRetainingCapacity();
        line_no += 1;

        try parseLine(allocator, line.items, line_no, &builder);
    } else |err| switch (err) {
        error.EndOfStream => { // end of file
            if (line.items.len > 0) {
                line_no += 1;
                try parseLine(allocator, line.items, line_no, &builder);
            }
        },
        else => return err, // Propagate error
    }

    out.* = try builder.toOwned();
}
