const std = @import("std");
const Bible = @import("./Bible.zig");
const BibleBuilder = @import("./BibleBuilder.zig");

const Allocator = std.mem.Allocator;
const Word = Bible.Element.Word;

pub fn parseTxt(allocator: Allocator, fname: []const u8, out: *Bible) !void {
    var file = try std.fs.cwd().openFile(fname, .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    const reader = buf_reader.reader();

    var line = try std.ArrayList(u8).initCapacity(allocator, 4096);
    defer line.deinit();

    var builder = BibleBuilder.init(allocator);
    defer builder.deinit();

    var parser = Parser{ .allocator = allocator, .builder = &builder };

    const writer = line.writer();
    while (reader.streamUntilDelimiter(writer, '\n', null)) {
        defer line.clearRetainingCapacity();
        try parser.parseLine(line.items);
    } else |err| switch (err) {
        error.EndOfStream => { // end of file
            if (line.items.len > 0) {
                try parser.parseLine(line.items);
            }
        },
        else => return err, // Propagate error
    }

    out.* = try builder.toOwned();
}

const Parser = struct {
    allocator: Allocator,
    builder: *BibleBuilder,
    line_no: usize = 0,
    word_no: u8 = 0,

    fn parseMorphemes(
        self: @This(),
        text: []const u8,
        strong: []const u8,
        grammar: []const u8,
    ) ![]const Word.Morpheme {
        const allocator = self.allocator;
        var morphemes = std.ArrayList(Word.Morpheme).init(allocator);
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

            const strong_parsed = try Word.Morpheme.Strong.parse(s[if (is_root) 1 else 0..]);
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

    fn parseLine2(self: *@This(), line: []const u8) !void {
        if (line.len == 0 or line[0] == '#') return;
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
        while (true) : (self.word_no +%= 1) {
            const next_hebrew = hebrew_split.next();
            const next_strong = strong_split.next();
            const next_grammar = grammar_split.next();
            if (next_hebrew == null and next_strong == null and next_grammar == null) break;

            const morphemes = try self.parseMorphemes(
                next_hebrew orelse return error.MissingMorph,
                next_strong orelse return error.MissingStrong,
                next_grammar orelse return error.MissingGrammar,
            );
            const word = Word{
                .ref = .{ .book = ref.book, .chapter = ref.chapter, .verse = ref.verse, .word = self.word_no },
                .morphemes = morphemes,
            };
            const cvw = Bible.Cvw{ .chapter = ref.chapter, .verse = ref.verse, .word = self.word_no };
            const order: u24 = @bitCast(cvw);
            try self.builder.addText(ref.book, order, .{ .w = word });
        }
    }

    pub fn parseLine(self: *@This(), line: []const u8) !void {
        self.line_no += 1;
        self.parseLine2(line) catch |e| {
            std.debug.print("{} on line {d}\n", .{ e, self.line_no });
            std.debug.print("{s}\n", .{ line });
        };
    }
};

pub const Reference = struct {
    book: Bible.BookName,
    chapter: u8,
    verse: u8,
    word: u8,
    primary: SourceSet,
    variants: [4]SourceSet = [_]SourceSet{.{}} ** 4,

    pub const SourceSet = packed struct {
        is_significant: bool = false,
        leningrad: bool = false,
        restored: bool = false, // from Leningrad parallels
        lxx: bool = false,
        qere: bool = false, // spoken: scribal sidenotes/footnotes
        ketiv: bool = false, // written tradition

        allepo: bool = false,
        bhs: bool = false,
        cairensis: bool = false,
        dead_sea_scrolls: bool = false,
        emendation: bool = false,
        formatting: bool = false,
        ben_chaim: bool = false,
        punctuation: bool = false,
        scribal: bool = false,
        variant: bool = false, // in some manuscripts

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

                    'a' => res.allepo = true,
                    'b' => res.bhs = true,
                    'c' => res.cairensis = true,
                    'd' => res.dead_sea_scrolls = true,
                    'e' => res.emendation = true,
                    'f' => res.formatting = true,
                    'h' => res.ben_chaim = true,
                    'p' => res.punctuation = true,
                    's' => res.scribal = true,
                    'v' => res.variant = true,
                    ' ', '\t' => {},
                    else => {
                        std.debug.print("unknown source {c}\n", .{ c });
                        return error.InvalidSource;
                    }
                }
            }

            return res;
        }
    };

    pub fn parse(ref: []const u8) !@This() {
        const first_dot = std.mem.indexOfScalar(u8, ref, '.') orelse return error.MissingFirstDot;
        const second_dot = std.mem.indexOfScalarPos(u8, ref, first_dot + 1, '.') orelse return error.MissingSecondDot;

        const book_str = ref[0..first_dot];
        const book = try Bible.BookName.fromEnglish(book_str);

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

        var variants = [_]SourceSet{.{}} ** 4;
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
};

test Reference {
    try std.testing.expectEqual(Reference{
        .book = .gen,
        .chapter = 1,
        .verse = 2,
        .word = 3,
        .primary = Reference.SourceSet{ .is_significant = true, .leningrad = true },
    }, try Reference.parse("Gen.1.2#03=L"));

    try std.testing.expectEqual(Reference{
        .book = .gen,
        .chapter = 1,
        .verse = 2,
        .word = 3,
        .primary = Reference.SourceSet{ .is_significant = true, .leningrad = true },
        .variants = [4]Reference.SourceSet{
            .{ .bhs = true },
            .{ .punctuation = true },
            .{},
            .{},
        },
    }, try Reference.parse("Gen.1.2(2.3)#03=L(b; p)"));

    try std.testing.expectEqual(Reference{
        .book = .gen,
        .chapter = 10,
        .verse = 20,
        .word = 30,
        .primary = Reference.SourceSet{ .is_significant = true, .leningrad = true },
        .variants = [4]Reference.SourceSet{
            .{ .bhs = true },
            .{ .punctuation = true },
            .{},
            .{},
        },
    }, try Reference.parse("Gen.10.20(2.3)#30=L(b; p)"));

    try std.testing.expectEqual(Reference{
        .book = .gen,
        .chapter = 31,
        .verse = 55,
        .word = 12,
        .primary = Reference.SourceSet{ .is_significant = true, .leningrad = true },
    }, try Reference.parse("Gen.31.55(32.1)#12=L"));
}
