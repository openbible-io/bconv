/// Parser for TAHOT and TAGNT.
///
/// This is a weird TSV file with no consistent comment markers and duplicate header rows
/// before every verse. Variants are not always consistent and require some alignment with
/// the main variant.
///
/// Original source files: https://github.com/STEPBible/STEPBible-Data
/// My fork: https://github.com/openbible-io/step
///
/// The original source is a downstream goodwill fork of what's served on
/// https://www.stepbible.org
/// Currently it's maintained by a single Tyndale employee.
const std = @import("std");
const Bible = @import("../../Bible.zig");

const log = std.log.scoped(.step);
const Allocator = std.mem.Allocator;
const Book = Bible.Book;
const Word = Bible.Word;
const Morpheme = Word.Morpheme;
const SourceSet = Bible.SourceSet;

pub fn parse(allocator: Allocator, fname: []const u8, out: *Bible) !void {
    var file = try std.fs.cwd().openFile(fname, .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    const reader = buf_reader.reader();

    var line = try std.ArrayList(u8).initCapacity(allocator, 4096);
    defer line.deinit();

    var parser = Parser.init(allocator, fname);
    defer parser.deinit();

    const writer = line.writer();
    while (reader.streamUntilDelimiter(writer, '\n', null)) {
        defer line.clearRetainingCapacity();
        try parser.parseLine(line.items);
    } else |err| switch (err) {
        error.EndOfStream => {
            if (line.items.len > 0) try parser.parseLine(line.items);
        },
        else => return err,
    }

    var parsed = try parser.builder.toOwned();
    defer parsed.books.deinit();
    var iter = parsed.books.iterator();
    while (iter.next()) |kv| try out.books.put(kv.key_ptr.*, kv.value_ptr.*);
}

const Parser = struct {
    allocator: Allocator,
    builder: Bible.Builder,
    ref: Reference = undefined,
    line_no: usize = 0,
    /// For resetting word_no
    verse_no: u8 = 0,
    /// For convenient reference when debugging
    word_no: u8 = 1,
    /// logging
    fname: []const u8 = "",

    const Error = error{
    };

    pub fn init(allocator: Allocator, fname: []const u8) @This() {
        return .{ .allocator = allocator, .builder = Bible.Builder.init(allocator), .fname = fname };
    }

    pub fn deinit(self: *@This()) void {
        self.builder.deinit();
    }

    fn parseVariant(self: *@This(), buf: []const u8, is_spelling: bool) !void {
        // spelling buf: B= עֲבָדִֽ֑ים\׃ ¦ P= עֲבָדִ֑ים\׃
        // meaning buf:  K= ha/me.for.va.tzim (הַ/מְפֹרוָצִים) "<the>/ [had been] broken down" (H9009/H6555=HTd/Pp3mp) ¦ B= he/m.fe.ru.tzim (הֵ֣/מפְּרוּצִ֔ים) "<the>/ [had been] broken down" (H9009/H6555=HTd/Pp3mp)
        if (buf.len == 0) return;
        // cannot simply split on ¦ because 0xA6 is after the 0x7F unicode cutooff.
        // hebrew letters like צֵ contain 0xA6.
        var iter = try Utf8Iter.init(buf);
        var start: usize = 0;
        while (iter.it.i < buf.len) {
            iter.consumeAny(&[_]u21{ ' ', '¦', ';' });
            start = iter.it.i;
    
            const source_set_end = iter.findNextScalar('=') orelse return error.VariantMissingEqual;
            var source_set = try SourceSet.parse(buf[start..source_set_end]);
            source_set.is_significant = !is_spelling;
            // consume =
            iter.it.i += 1;
    
            try self.builder.startOption(self.ref.book, source_set);
            if (is_spelling) {
                const text_end = iter.findNextAny(&[_]u21{ '¦' }) orelse buf.len;
                const text = std.mem.trim(u8, buf[source_set_end + 1..text_end], " ");
                if (text.len == 0) break;
                iter.consumeAny(&[_]u21{ ' ', '¦', ';' });

                try self.parseText(text);
            } else {
                var paren_start = (iter.findNextScalar('(') orelse return error.VariantMissingLeftParen) + 1;
                var paren_end = iter.findNextScalar(')') orelse return error.VariantMissingRightParen;
                const text = buf[paren_start..paren_end];
    
                // strongs and grammar
                paren_start = (iter.findNextScalar('(') orelse return error.VariantMissingLeftParen2) + 1;
                const equal = iter.findNextScalar('=') orelse return error.VariantMissingStrongGrammarDelimiter;
                paren_end = iter.findNextScalar(')') orelse return error.VariantMissingRightParen2;
                const strong = buf[paren_start..equal];
                const grammar = buf[equal + 1..paren_end];

                try self.parseFields(text, strong, grammar, "", "");
            }
        }
    }

    fn parseVariants(
        self: *@This(),
        main: []Bible.Element,
        meaning: []const u8,
        spelling: []const u8,
    ) !void {
        try self.builder.startOption(self.ref.book, self.ref.primary);

        const meaning_trimmed = std.mem.trim(u8, meaning, &std.ascii.whitespace);
        const spelling_trimmed = std.mem.trim(u8, spelling, &std.ascii.whitespace);

        if (meaning_trimmed.len > 0 or spelling_trimmed.len > 0) {
            try self.builder.startVariant(self.ref.book);
        }

        self.parseVariant(meaning, false) catch |e| {
            self.warn("{} for meaning {s}", .{ e, meaning });
        };
        self.parseVariant(spelling, true) catch |e| {
            self.warn("{} for spelling {s}", .{ e, spelling });
        };
        try self.builder.endVariant(self.ref.book);

        _ = main;
        // try alignVariants(&options);

        return null;
    }

    // move me
    fn addWord(
        self: *@This(),
        morphemes: *std.ArrayList(Word.Morpheme),
        max_byte_len: usize,
    ) !void {
        const morphs = try morphemes.toOwnedSlice();
        // skip lines that are included only to show variants:
        // Isa.44.24#16=Q(K)		[ ]	[ ]			K= mi (מִי) "who [was]?" (H4310=HPi)	L= מֵי ¦ ;		H4310
        if (morphs.len == 0) return;
        // Take a guess based off length at which one is root.
        var seen_root = false;
        for (morphs) |*m| {
            const is_root = !seen_root and m.text.len == max_byte_len;
            seen_root = is_root;
            m.type = if (is_root) .root else if (seen_root) .suffix else .prefix;
        }

        defer self.word_no +%= 1;
        try self.builder.addWord(self.ref.book, Word{
            .morphemes = morphs,
        });
    }

    /// Text -> [](Word | Punctuation)
    fn parseText(self: *@This(), text: []const u8) !Book.Element.Iterator {
        var res = Book.Element.Iterator{ .start = self.builder.buf.len };

        const ref = self.ref;
        try self.builder.startWord(.{ .book = ref.book, .chapter = ref.chapter, .verse = ref.verse, .word = self.word_no, },);

        var max_byte_len: usize = 0;
        var morph_iter = std.mem.splitAny(u8, text, "/\\");
        while (morph_iter.peek()) |token| : (_ = morph_iter.next()) {
            const i = morph_iter.index.?;
            const tok = std.mem.trim(u8, token, &std.ascii.whitespace);
            // \ indicates punctuation, expect for ~10 places where
            // a/־/c is written instead of a/\־/c
            const is_punctuation = i >= 1 and text[i - 1] == '\\' or std.mem.eql(u8, tok, "־");

            if (tok.len == 0 or is_punctuation) {
                // use max_byte_len;
                try self.builder.finishWord();
                max_byte_len = 0;
                // Punctuation marks are delimiters.
                if (is_punctuation and tok.len > 0) try self.builder.addPunctuation(tok);
                continue;
            }
            if (tok.len > max_byte_len) max_byte_len = tok.len;

            try self.builder.addMorpheme(Morpheme{ .type =  undefined, .text = tok });
        }

        // use max_byte_len;
        try self.builder.finishWord();

        res.buf = self.builder.items;
        res.end = self.builder.buf.len;
        return res;
    }

    fn warn(self: @This(), comptime format: []const u8, args: anytype) void {
        log.warn(format ++ " at {s}:{d}", args ++ .{ self.fname, self.line_no });
    }

    fn err(self: @This(), comptime format: []const u8, args: anytype) void {
        log.err(format ++ " at {s}:{d}", args ++ .{ self.fname, self.line_no });
    }

    fn parseMorphemes(
        self: *@This(),
        texts: []const u8,
        strongs: []const u8,
        grammars: []const u8,
    ) !void {
        var word_iter = try self.parseText(texts);

        // Enrich words
        const lang: ?std.meta.Tag(Morpheme.Code) = if (grammars.len < 1)
           null
        else
            switch (grammars[0]) {
                'H' => .hebrew,
                'A' => .aramaic,
                else => |c| {
                    std.debug.print("unknown morph language {c}\n", .{ c });
                    return error.MorphInvalidLang;
                }
            };
        const grammars_trimmed = if (lang == null) grammars else grammars[1..];
        var strong_iter = std.mem.splitAny(u8, strongs, "/\\");
        var grammar_iter = std.mem.splitAny(u8, grammars_trimmed, "/\\");

        while (word_iter.next()) |ele| switch (ele) {
            .word => |*w| {
                for (w.morphemes) |*m| {
                    var seen_root = false;
                    while (strong_iter.next()) |strong| {
                        const trimmed = std.mem.trim(u8, strong, " "); 
                        if (trimmed.len == 0) continue; // probably a `//` word boundary

                        const left_brace = trimmed[0] == '{'; 
                        const is_root = left_brace or w.morphemes.len == 1;
                        seen_root = is_root;
                        m.type = if (is_root) .root else if (seen_root) .suffix else .prefix;
                        m.strong = try Word.Morpheme.Strong.parse(trimmed[if (left_brace) 1 else 0..]);
                        break;
                    }
                    if (m.strong == null) {
                        self.warn("{s} ({s}) missing strong", .{ m.text, @tagName(m.type) });
                    }

                    while (grammar_iter.next()) |grammar| {
                        const trimmed = std.mem.trim(u8, grammar, " "); 
                        if (trimmed.len == 0) continue; // probably a `//` word boundary
                        if (lang == null) return error.MorphCodeMissingLang;

                        m.code = switch (lang.?) {
                            .hebrew => .{ .hebrew = try Morpheme.Hebrew.parse(trimmed) },
                            .aramaic => .{ .aramaic = try Morpheme.Aramaic.parse(trimmed) },
                        };
                        break;
                    }
                    if (m.code == null) {
                        self.warn("{s} ({s}) missing grammar", .{ m.text, @tagName(m.type) });
                    }
                }
            },
            .punctuation => |_| {
                _ = strong_iter.next();
            },
            else => unreachable,
        };
    }

    /// Appends to self.line_elements
    fn parseFields(
        self: *@This(),
        texts: []const u8,
        strongs: []const u8,
        grammars: []const u8,
        meaning_variants: []const u8,
        spelling_variants: []const u8,
    ) Error!void {
        try self.parseMorphemes(texts, strongs, grammars);
        try self.parseVariants(meaning_variants, spelling_variants);
    }

    fn parseLine2(self: *@This(), line: []const u8) !void {
        if (line.len == 0 or line[0] == '#') return;
        var fields = std.mem.splitScalar(u8, line, '\t');
        // NRSV(Heb) Ref & type
        const ref_type = fields.first();

        self.ref = Reference.parse(ref_type) catch return;
        if (self.ref.verse != self.verse_no) {
            self.verse_no = self.ref.verse;
            self.word_no = 1;
        }

        const text = fields.next() orelse return error.MissingFieldText;
        _ = fields.next() orelse return error.MissingFieldTransliteration;
        _ = fields.next() orelse return error.MissingFieldTranslation;
        const strong = fields.next() orelse return error.MissingFieldStrong;
        const grammar = fields.next() orelse return error.MissingFieldGrammar;
        const meaning_variant = fields.next() orelse return error.MissingFieldMeaningVariant;
        const spelling_variant = fields.next() orelse return error.MissingFieldSpellingVariant;
        // _ = fields.next() orelse return error.MissingFieldRootStrong; // Root dStrong+Instance
        // _ = fields.next() orelse return error.MissingFieldAltStrong; // alt Strongs+Instance
        // _ = fields.next() orelse return error.MissingFieldConjoin; // conjoin word
        // _ = fields.next() orelse return error.MissingFieldExpanded; // expanded Strong tags

        try self.parseFields(text, strong, grammar, meaning_variant, spelling_variant);
    }

    pub fn parseLine(self: *@This(), line: []const u8) !void {
        self.line_no += 1;
        self.parseLine2(line) catch |e| {
            self.err("{}", .{ e });
            // TODO: print exact character
        };
    }
};

// diacritical marks are U+300 to U+36F
// hebrew is U+591 to U+5F4
//  - diacritics U+591 to U+5C7
//      - exceptions: punctuation U+5BE, U+5C0, U+5C3, and U+5C6
//  - alphabet U+5D0 to U+05EA
//  - punctuation until U+5F4
const Utf8Iter = struct {
    it: std.unicode.Utf8Iterator,

    pub fn init(s: []const u8) !@This() {
        const view = try std.unicode.Utf8View.init(s);
        return .{ .it = view.iterator() };
    }

    fn next(self: *@This()) ?u21 {
        return self.it.nextCodepoint();
    }

    fn findNextScalar(self: *@This(), cp: u21) ?usize {
        var last_i = self.it.i;
        while (self.it.nextCodepoint()) |cp2| : (last_i = self.it.i) if (cp == cp2) return last_i;
        return null;
    }

    fn findNextAny(self: *@This(), cps: []const u21) ?usize {
        var last_i = self.it.i;
        while (self.it.nextCodepoint()) |cp2| : (last_i = self.it.i) {
            for (cps) |cp| if (cp == cp2) return last_i;
        }
        return null;
    }

     fn consumeAny(self: *@This(), cps: []const u21) void {
            while (self.it.nextCodepoint()) |cp2| {
                var has_match = false;
                for (cps) |cp| {
                    if (cp == cp2) {
                        has_match = true;
                        break;
                    }
                }
                if (!has_match) {
                    self.it.i -= std.unicode.utf8CodepointSequenceLength(cp2) catch unreachable;
                    break;
                }
            }
     }
};

pub const Reference = struct {
    book: Bible.BookName,
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
};

test Reference {
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
