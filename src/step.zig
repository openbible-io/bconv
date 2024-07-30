const std = @import("std");
const Bible = @import("./Bible.zig");
const BibleBuilder = @import("./BibleBuilder.zig");
const morphology = @import("./morphology/mod.zig");
const string_pools = @import("./StringPools.zig");
const StringPools = string_pools.StringPools;

const Allocator = std.mem.Allocator;
const Word = Bible.Element.Word;

pub fn parseTxt(allocator: Allocator, fname: []const u8, out: *Bible) !void {
    var file = try std.fs.cwd().openFile(fname, .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    const reader = buf_reader.reader();

    var line = try std.ArrayList(u8).initCapacity(allocator, 4096);
    defer line.deinit();

    var parser = Parser.init(allocator);
    defer parser.deinit();

    const writer = line.writer();
    while (reader.streamUntilDelimiter(writer, '\n', null)) {
        defer line.clearRetainingCapacity();
        try parser.parseLine(fname, line.items);
    } else |err| switch (err) {
        error.EndOfStream => { // end of file
            if (line.items.len > 0) {
                try parser.parseLine(fname, line.items);
            }
        },
        else => return err, // Propagate error
    }

    var parsed = try parser.builder.toOwned();
    defer parsed.books.deinit();
    var iter = parsed.books.iterator();
    while (iter.next()) |kv| try out.books.put(kv.key_ptr.*, kv.value_ptr.*);
}

const Parser = struct {
    allocator: Allocator,
    builder: BibleBuilder,
    ref: Reference = undefined,
    line_no: usize = 0,
    /// For resetting word_no
    verse_no: u8 = 0,
    /// Convenient reference
    word_no: u8 = 1,

    const Options = std.ArrayList(Bible.Element.Variant.Option);

    const Error = error{
OutOfMemory,
Overflow,
InvalidCharacter,
MorphInvalidLang,
MorphMissingMorph,
MorphMissingStrong,
MorphMissingGrammar,
EmptyEStrong,
InvalidLang,
MorphCodeMissingLang,
SmallSemiticCode,
MissingAdjectiveType,
MorphEnumMapping,
MissingAdjectiveGender,
MissingAdjectiveNumber,
MissingAdjectiveState,
NounMissingForm,
ProperNounMissingGender,
NounMissingType,
NounMissingGender,
PronounMissingType,
InvalidPrepositionSuffix,
SuffixMissingType,
MissingParticleType,
MissingVerbForm,
VerbMissingStem,
VerbMissingForm,
SemiticCode,
InvalidUtf8,
InvalidSource,
VariantMissingEqual,
VariantMissingLeftParen,
VariantMissingRightParen,
VariantMissingLeftParen2,
VariantMissingRightParen2,
VariantMissingStrongGrammarDelimiter,
CodepointTooLarge,
    };

    pub fn init(allocator: Allocator) @This() {
        return .{ .allocator = allocator, .builder = BibleBuilder.init(allocator) };
    }

    pub fn deinit(self: *@This()) void {
        self.builder.deinit();
    }

    fn findNext(it: *std.unicode.Utf8Iterator, cp: u21) ?usize {
        var last_i = it.i;
        while (it.nextCodepoint()) |cp2| : (last_i = it.i) if (cp == cp2) return last_i;
        return null;
    }

    fn parseVariant(self: *@This(), buf: []const u8, acc: *Options) !void {
        if (buf.len == 0) return;
        // cannot split on ¦ because it appears in hebrew unicode like צֵ
        // not sure if () can appear, so let's painfully iterate over utf8 codepoints
        const view = try std.unicode.Utf8View.init(buf);
        var iter = view.iterator();
        var start: usize = 0;
        while (iter.i < buf.len) {
            while (iter.nextCodepoint()) |c| switch (c) {
                ' ', '¦', ';' => {},
                else => {
                    start = iter.i - try std.unicode.utf8CodepointSequenceLength(c);
                    break;
                }
            };

            const source_set_end = findNext(&iter, '=') orelse return error.VariantMissingEqual;
            const source_set = try SourceSet.parse(buf[start..source_set_end]);
            _ = source_set;

            var paren_start = (findNext(&iter, '(') orelse return error.VariantMissingLeftParen) + 1;
            var paren_end = findNext(&iter, ')') orelse return error.VariantMissingRightParen;
            const text = buf[paren_start..paren_end];

            // strongs and grammar
            paren_start = (findNext(&iter, '(') orelse return error.VariantMissingLeftParen2) + 1;
            const equal = findNext(&iter, '=') orelse return error.VariantMissingStrongGrammarDelimiter;
            paren_end = findNext(&iter, ')') orelse return error.VariantMissingRightParen2;
            const strong = buf[paren_start..equal];
            const grammar = buf[equal + 1..paren_end];

            std.debug.print("{s} {s} {s} {s}\n", .{ buf[start..source_set_end], text, strong, grammar });
            // TODO: sourceset fn write
            const owned = try string_pools.global.getOrPutLang(buf[0..source_set_end], .english);
            const children = try self.parseFields(text, strong, grammar, "", "");

            try acc.append(.{ .value = owned, .children = children });
        }
    }

    fn parseVariants(self: *@This(), main: []const Bible.Element, meaning: []const u8, spelling: []const u8,) !?Bible.Element.Variant {
        const allocator = self.allocator;
        var options = Options.init(allocator);
        defer options.deinit();
        errdefer for (options.items) |o| o.deinit(allocator);
        // TODO: self.ref.sourceset fn write
        try options.append(Bible.Element.Variant.Option{ .value = "main", .children = main });

        try self.parseVariant(meaning, &options);
        try self.parseVariant(spelling, &options);

        return if (options.items.len > 1) .{ .options = try options.toOwnedSlice() } else null;
    }

    fn morphToElement(self: *@This(), morphemes: *std.ArrayList(Word.Morpheme)) !?Bible.Element {
        const ref = self.ref;
        const morphs = try morphemes.toOwnedSlice();
        // skip lines that are included only to show variants:
        // Isa.44.24#16=Q(K)		[ ]	[ ]			K= mi (מִי) "who [was]?" (H4310=HPi)	L= מֵי ¦ ;		H4310
        if (morphs.len == 0) return null;
        defer self.word_no +%= 1;
        return Bible.Element{ .word = Word{
            .ref = .{ .book = ref.book, .chapter = ref.chapter, .verse = ref.verse, .word = self.word_no },
            .morphemes = morphs,
        } };
    }

    fn parseMorphemes(
        self: *@This(),
        acc: *std.ArrayList(Bible.Element),
        texts: []const u8,
        strongs: []const u8,
        grammars: []const u8,
    ) !void {
        const allocator = self.allocator;
        const lang: ?std.meta.Tag(morphology.Code) = if (grammars.len < 1)
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

        var morphemes = std.ArrayList(Word.Morpheme).init(allocator);
        errdefer morphemes.deinit();

        var text_iter = std.mem.splitScalar(u8, texts, '/');
        var strong_iter = std.mem.splitScalar(u8, strongs, '/');
        var grammar_iter = std.mem.splitScalar(u8, grammars_trimmed, '/');

        var seen_root = false;
        while (true) {
            const next_morph = text_iter.next();
            const next_strong = strong_iter.next();
            const next_grammar = grammar_iter.next();

            if (next_morph == null and next_strong == null and next_grammar == null) break;

            const m = std.mem.trim(u8, next_morph orelse  return error.MorphMissingMorph, " ");
            const s = std.mem.trim(u8, next_strong orelse return error.MorphMissingStrong, " ");
            const g = std.mem.trim(u8, next_grammar orelse return error.MorphMissingGrammar, " ");

            // Because empty text is the word delimiter we cannot return []const Morpheme :(
            if (m.len == 0) {
                if (try self.morphToElement(&morphemes)) |e| try acc.append(e);
                seen_root = false;
                continue;
            }

            const is_root = s.len > 0 and s[0] == '{';
            defer seen_root = is_root;

            const strong_parsed: ?Word.Morpheme.Strong = if (s.len == 0)
                null
            else
                try Word.Morpheme.Strong.parse(s[if (is_root) 1 else 0..]);

            const code: ?morphology.Code = if (g.len == 0)
                null
            else if (lang == null)
                return error.MorphCodeMissingLang
            else
                switch (lang.?) {
                    .hebrew => .{ .hebrew = morphology.Hebrew.parse(g) catch |e| {
                        std.debug.print("bad morph {s}\n", .{ g });
                        return e;
                    }},
                    .aramaic => .{ .aramaic = try morphology.Aramaic.parse(g) },
                };
            const pool_lang: StringPools.Lang = if (lang) |l| switch (l) {
                .hebrew, .aramaic => .semitic,
            } else .unknown;
            const owned = try string_pools.global.getOrPutLang(m, pool_lang);

            try morphemes.append(Word.Morpheme{
                .type = if (is_root) .root else if (seen_root) .suffix else .prefix,
                .code = code,
                .strong = strong_parsed,
                .text = owned,
            });
        }

        if (try self.morphToElement(&morphemes)) |e| try acc.append(e);
    }

    /// Appends to self.line_elements
    fn parseFields(
        self: *@This(),
        texts: []const u8,
        strongs: []const u8,
        grammars: []const u8,
        meaning_variants: []const u8,
        spelling_variants: []const u8,
    ) Error![]const Bible.Element {
        _ = .{ meaning_variants, spelling_variants };
        const allocator = self.allocator;
        var res = std.ArrayList(Bible.Element).init(allocator);
        errdefer res.deinit();

        try self.parseMorphemes(&res, texts, strongs, grammars);
        const main = try res.toOwnedSlice();

        if (try self.parseVariants(main, meaning_variants, spelling_variants)) |v| {
             var list = try allocator.alloc(Bible.Element, 1);
             list[0] = .{ .variant = v };
             return list;
        }

        return main;
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

        const eles = try self.parseFields(text, strong, grammar, meaning_variant, spelling_variant);
        defer self.allocator.free(eles);
        for (eles) |e| try self.builder.appendElement(self.ref.book, e);
    }

    pub fn parseLine(self: *@This(), fname: []const u8, line: []const u8) !void {
        self.line_no += 1;
        self.parseLine2(line) catch |e| {
            std.debug.print("{s}:{d} {}:\n", .{ fname, self.line_no, e });
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

   // neste_aland: bool = false, // na27 spelled like na28
   // kjv: bool = false, // textus receptus 1894 with some corrections
   // other = variant

    pub fn parse(str: []const u8) !@This() {
        var res = @This(){ .is_significant = std.ascii.isUpper(str[0]) };
        for (str) |c| {
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
                ' ', '\t', '/', => {},
                else => {
                    std.debug.print("unknown source {c}\n", .{ c });
                    return error.InvalidSource;
                }
            }
        }

        return res;
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
        .variants = [_]Reference.SourceSet{
            .{ .bhs = true },
            .{ .punctuation = true },
        },
    }, try Reference.parse("Gen.1.2(2.3)#03=L(b; p)"));

    try std.testing.expectEqual(Reference{
        .book = .gen,
        .chapter = 10,
        .verse = 20,
        .word = 30,
        .primary = Reference.SourceSet{ .is_significant = true, .leningrad = true },
        .variants = [_]Reference.SourceSet{
            .{ .bhs = true },
            .{ .punctuation = true },
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
