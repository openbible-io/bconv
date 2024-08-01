const std = @import("std");
const Bible = @import("./Bible.zig");
const BibleBuilder = @import("./BibleBuilder.zig");
const morphology = @import("./morphology/mod.zig");
const string_pools = @import("./StringPools.zig");
const xml = @import("./xml.zig"); // for testing

const log = std.log.scoped(.step);
const StringPools = string_pools.StringPools;
const Allocator = std.mem.Allocator;
const Word = Bible.Element.Word;
const Morpheme = Word.Morpheme;
const Variant = Bible.Element.Variant;
const SourceSet = Variant.Option.SourceSet;

pub fn parseTxt(allocator: Allocator, fname: []const u8, out: *Bible) !void {
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
    builder: BibleBuilder,
    ref: Reference = undefined,
    line_no: usize = 0,
    /// For resetting word_no
    verse_no: u8 = 0,
    /// For convenient reference when debugging
    word_no: u8 = 1,
    /// logging
    fname: []const u8 = "",
    lang: StringPools.Lang = .unknown,

    const Options = std.ArrayList(Variant.Option);

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

    pub fn init(allocator: Allocator, fname: []const u8) @This() {
        return .{ .allocator = allocator, .builder = BibleBuilder.init(allocator), .fname = fname };
    }

    pub fn deinit(self: *@This()) void {
        self.builder.deinit();
    }

    fn putText(self: @This(), text: []const u8) ![]const u8 {
        return try string_pools.global.getOrPutLang(text, self.lang);
    }

    // fn parseVariant(self: *@This(), buf: []const u8, main: []const Bible.Element, acc: *Options) !void {
    //     const is_spelling = main.len > 0;
    //     const allocator = self.allocator;
    //     if (buf.len == 0) return;
    //     // cannot split on ¦ because 0xA6 appears in hebrew unicode like צֵ
    //     // not sure if () can appear, so let's painfully iterate over utf8 codepoints
    //     const view = try std.unicode.Utf8View.init(buf);
    //     var iter = view.iterator();
    //     var start: usize = 0;
    //     while (iter.i < buf.len) {
    //         consumeAny(&iter, &[_]u21{ ' ', '¦', ';' });
    //         start = iter.i;
    //
    //         const source_set_end = findNextScalar(&iter, '=') orelse return error.VariantMissingEqual;
    //         var source_set = try SourceSet.parse(buf[start..source_set_end]);
    //         source_set.is_significant = !is_spelling;
    //
    //         if (is_spelling) {
    //             iter.i += 1; // =
    //             // B= עֲבָדִֽ֑ים\׃ ¦ P= עֲבָדִ֑ים\׃
    //             // L= בְּעִירֹ֔/ה ¦ ;K= בְּעִירֹ/ה
    //             // P= יִשְׂרָאֵֽל\ \פ
    //             const text_end = findNextAny(&iter, &[_]u21{ '¦' }) orelse buf.len;
    //             const text = std.mem.trim(u8, buf[source_set_end + 1..text_end], " ");
    //             if (text.len == 0) break;
    //             consumeAny(&iter, &[_]u21{ ' ', '¦', ';' });
    //
    //             // If each word has the same number of morphemes then we assume
    //             // this spelling variant matches the main one and copy its strong + grammar.
    //             var text_iter = std.mem.splitScalar(u8, text, '/');
    //             var match = true;
    //             var word_i: usize = 0;
    //             var morph_i: usize = 0;
    //             while (text_iter.next()) |next_morph| : (morph_i += 1) {
    //                 const m = std.mem.trim(u8, next_morph, " ");
    //                 if (m.len == 0) {
    //                     word_i += 1;
    //                     if (word_i >= main.len or main[word_i].word.morphemes.len != morph_i) {
    //                         match = false;
    //                         break;
    //                     }
    //                     morph_i = 0;
    //                 }
    //             }
    //             if (word_i >= main.len or main[word_i].word.morphemes.len != morph_i) {
    //                 match = false;
    //             }
    //
    //             var words = std.ArrayList(Bible.Element).init(allocator);
    //             errdefer words.deinit();
    //
    //             var morphemes = std.ArrayList(Word.Morpheme).init(allocator);
    //             errdefer morphemes.deinit();
    //
    //             text_iter.reset();
    //             word_i = 0;
    //             morph_i = 0;
    //             while (text_iter.next()) |next_morph| : (morph_i += 1) {
    //                 const m = std.mem.trim(u8, next_morph, " ");
    //                 if (m.len == 0) {
    //                     word_i += 1;
    //                     morph_i = 0;
    //                     if (try self.morphsToElement(&morphemes)) |e| try words.append(e);
    //                     continue;
    //                 }
    //
    //                 const pool_lang: StringPools.Lang = switch (main[0].word.morphemes[0].strong.?.lang) {
    //                     .hebrew, .aramaic => .semitic,
    //                     .greek => .greek,
    //                 };
    //                 const owned = try self.putText(m);
    //                 var morph = Word.Morpheme{ .text = owned };
    //
    //                 if (match) {
    //                     const matched = main[word_i].word.morphemes[morph_i];
    //                     morph.strong = matched.strong;
    //                     morph.code = matched.code;
    //                 }
    //
    //                 try morphemes.append(morph);
    //             }
    //
    //             if (try self.morphsToElement(&morphemes)) |e| try words.append(e);
    //
    //             if (!match) {
    //                 std.debug.print("spelling strong+grammar misalignment {s}.{d}.{d}#{d:0<2}\n", .{ @tagName(self.ref.book), self.ref.chapter, self.ref.verse, self.ref.word });
    //             }
    //
    //             const children = try words.toOwnedSlice();
    //             try acc.append(.{ .source_set = source_set, .children = children });
    //         } else {
    //             // K= ha/me.for.va.tzim (הַ/מְפֹרוָצִים) "<the>/ [had been] broken down" (H9009/H6555=HTd/Pp3mp) ¦ B= he/m.fe.ru.tzim (הֵ֣/מפְּרוּצִ֔ים) "<the>/ [had been] broken down" (H9009/H6555=HTd/Pp3mp)
    //             var paren_start = (findNextScalar(&iter, '(') orelse return error.VariantMissingLeftParen) + 1;
    //             var paren_end = findNextScalar(&iter, ')') orelse return error.VariantMissingRightParen;
    //             const text = buf[paren_start..paren_end];
    //
    //             // strongs and grammar
    //             paren_start = (findNextScalar(&iter, '(') orelse return error.VariantMissingLeftParen2) + 1;
    //             const equal = findNextScalar(&iter, '=') orelse return error.VariantMissingStrongGrammarDelimiter;
    //             paren_end = findNextScalar(&iter, ')') orelse return error.VariantMissingRightParen2;
    //             const strong = buf[paren_start..equal];
    //             const grammar = buf[equal + 1..paren_end];
    //
    //             const children = try self.parseFields(text, strong, grammar, "", "");
    //             try acc.append(.{ .source_set = source_set, .children = children });
    //         }
    //     }
    // }

    // fn parseVariants(self: *@This(), main: []const Bible.Element, meaning: []const u8, spelling: []const u8,) !?Variant {
    //     const allocator = self.allocator;
    //     var options = Options.init(allocator);
    //     defer options.deinit();
    //     errdefer for (options.items) |o| o.deinit(allocator);
    //     try options.append(Variant.Option{ .source_set = self.ref.primary, .children = main });
    //
    //     try self.parseVariant(meaning, &[_]Bible.Element{}, &options);
    //     try self.parseVariant(spelling, main, &options);
    //
    //     return if (options.items.len > 1) .{ .options = try options.toOwnedSlice() } else null;
    // }

    fn morphsToElement(self: *@This(), morphemes: *std.ArrayList(Word.Morpheme), max_byte_len: usize,) !?Bible.Element {
        const ref = self.ref;
        const morphs = try morphemes.toOwnedSlice();
        // skip lines that are included only to show variants:
        // Isa.44.24#16=Q(K)		[ ]	[ ]			K= mi (מִי) "who [was]?" (H4310=HPi)	L= מֵי ¦ ;		H4310
        if (morphs.len == 0) return null;
        // Take a guess based off length at which one is root.
        var seen_root = false;
        for (morphs) |*m| {
            const is_root = m.text.len == max_byte_len;
            seen_root = is_root;
            m.type = if (is_root)
                .root
            else if (seen_root)
                .suffix
            else
                .prefix;
        }

        defer self.word_no +%= 1;
        return Bible.Element{ .word = Word{
            .ref = .{ .book = ref.book, .chapter = ref.chapter, .verse = ref.verse, .word = self.word_no },
            .morphemes = morphs,
        } };
    }

    /// Text -> [](Word | Punctuation)
    fn parseText(self: *@This(), text: []const u8) ![]Bible.Element {
        const allocator = self.allocator;
        var res = std.ArrayList(Bible.Element).init(allocator);
        defer res.deinit();

        var morphemes = std.ArrayList(Word.Morpheme).init(allocator);
        defer morphemes.deinit();

        var max_byte_len: usize = 0;
        var morph_iter = std.mem.splitAny(u8, text, "/\\");
        while (morph_iter.peek()) |token| : (_ = morph_iter.next()) {
            const tok = std.mem.trim(u8, token, " ");
            const i = morph_iter.index.?;
            // \ indicates punctuation, expect for ~10 places where
            // a/־/c is written instead of a/\־/c
            const is_punctuation = i >= 1 and text[i - 1] == '\\' or std.mem.eql(u8, tok, "־");

            if (tok.len == 0 or is_punctuation) {
                if (try self.morphsToElement(&morphemes, max_byte_len)) |w| try res.append(w);
                // Punctuation marks are delimiters.
                if (is_punctuation) {
                    try res.append(Bible.Element{ .punctuation = Bible.Element.Punctuation{
                        .text = try self.putText(tok),
                    } });
                }
                continue;
            }
            if (tok.len > max_byte_len) max_byte_len = tok.len;

            const morph = Morpheme{
                .type =  undefined, // will be set in morphsToElement
                .text = try self.putText(tok),
            };

            try morphemes.append(morph);
        }

        if (try self.morphsToElement(&morphemes, max_byte_len)) |w| try res.append(w);

        return try res.toOwnedSlice();
    }

    fn warn(self: @This(), comptime format: []const u8, args: anytype) void {
        log.warn(format ++ " at {s}:{d}", args ++ .{ self.fname, self.line_no });
    }

    fn parseMorphemes(
        self: *@This(),
        texts: []const u8,
        strongs: []const u8,
        grammars: []const u8,
    ) ![]Bible.Element {
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
        self.lang = if (lang) |l| switch (l) {
            .hebrew, .aramaic => .semitic,
        } else .unknown;
        const grammars_trimmed = if (lang == null) grammars else grammars[1..];

        const res = try self.parseText(texts);
        var strong_iter = std.mem.splitAny(u8, strongs, "/\\");
        var grammar_iter = std.mem.splitAny(u8, grammars_trimmed, "/\\");

        for (res) |ele| switch (ele) {
            .word => |*w| {
                for (w.morphemes) |*m| {
                    var seen_root = false;
                    while (strong_iter.next()) |strong| {
                        const trimmed = std.mem.trim(u8, strong, " "); 
                        if (trimmed.len == 0) continue; // probably a `//` word boundary

                        const is_root = trimmed.len > 0 and trimmed[0] == '{';
                        seen_root = is_root;
                        m.type = if (is_root)
                            .root
                        else if (seen_root)
                            .suffix
                        else
                            .prefix;
                        m.strong = try Word.Morpheme.Strong.parse(trimmed[if (is_root) 1 else 0..]);
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
                            .hebrew => .{ .hebrew = try morphology.Hebrew.parse(trimmed) },
                            .aramaic => .{ .aramaic = try morphology.Aramaic.parse(trimmed) },
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
            else => {},
        };

        return res;
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
        // const allocator = self.allocator;

        const res = try self.parseMorphemes(texts, strongs, grammars);

        _ = .{ meaning_variants, spelling_variants };
        // if (try self.parseVariants(main, meaning_variants, spelling_variants)) |v| {
        //      var list = try allocator.alloc(Bible.Element, 1);
        //      list[0] = .{ .variant = v };
        //      return list;
        // }

        return res;
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

    pub fn parseLine(self: *@This(), line: []const u8) !void {
        self.line_no += 1;
        self.parseLine2(line) catch |e| {
            std.debug.print("{s}:{d} {}:\n", .{ self.fname, self.line_no, e });
            std.debug.print("{s}\n", .{ line });
        };
    }
};

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

// fn testVariants(ref: []const u8, comptime expected: []const u8, str: []const u8) !void {
//     const allocator = std.testing.allocator;
// 
//     var parser = Parser.init(allocator);
//     defer parser.deinit();
//     parser.ref = try Reference.parse(ref);
// 
//     var variant = (try parser.parseVariants(&[_]Bible.Element{}, str, "")).?;
//     defer variant.deinit(allocator);
// 
//     var buf = std.ArrayList(u8).init(allocator);
//     defer buf.deinit();
// 
//     var writer: xml.Writer(std.ArrayList(u8).Writer) = .{ .w = buf.writer() };
//     try variant.writeXml(&writer);
// 
//     try std.testing.expectEqualStrings(
//         \\
//        \\<variant reason="">
//        \\	<option is_significant="true" source_set="qere">
//        \\	</option>
//        \\
//         ++ expected ++
//         \\
//         \\</variant>
//         ,
//         buf.items,
//     );
// }
// 
// test "Parser.parseVariants" {
//     string_pools.global = string_pools.StringPools.init(std.testing.allocator);
//     defer string_pools.global.deinit();
// 
//     try testVariants(
//         "Neh.2.13#17=Q(K; B)",
//         \\	<option is_significant="true" source_set="ketiv">
//         \\		<w id="neh2:13#1">
//         \\			<m type="prefix" code="HPd" strong="H9009">
//         \\				הַ
//         \\			</m>
//         \\			<m type="prefix" code="HPp3mp" strong="H6555">
//         \\				מְפֹרוָצִים
//         \\			</m>
//         \\		</w>
//         \\	</option>
//         \\	<option is_significant="true" source_set="bhs">
//         \\		<w id="neh2:13#2">
//         \\			<m type="prefix" code="HPd" strong="H9009">
//         \\				הֵ֣
//         \\			</m>
//         \\			<m type="prefix" code="HPp3mp" strong="H6555">
//         \\				מפְּרוּצִ֔ים
//         \\			</m>
//         \\		</w>
//         \\	</option>
//         ,
//         \\K= ha/me.for.va.tzim (הַ/מְפֹרוָצִים) "<the>/ [had been] broken down" (H9009/H6555=HTd/Pp3mp) ¦ B= he/m.fe.ru.tzim (הֵ֣/מפְּרוּצִ֔ים) "<the>/ [had been] broken down" (H9009/H6555=HTd/Pp3mp)
//     );
//     try testVariants(
//         "Gen.27.3#11=Q(K)",
//         \\	<option is_significant="true" source_set="ketiv">
//         \\		<w id="gen27:3#1">
//         \\			<m type="prefix" code="HNcbsa" strong="H6720">
//         \\				צֵידָה\׃
//         \\			</m>
//         \\		</w>
//         \\	</option>
//         ,
//         \\K= tzei.dah (צֵידָה\׃) "food" (H6720\H9016=HNcbsa)
//     );
//     try testVariants(
//         "Deu.5.18#01=L(p)",
//         \\	<option is_significant="true" source_set="punctuation">
//         \\		<w id="deu5.18#1">
//         \\			<m type="prefix" code="" strong="H3808">
//         \\				וְ/לֹ֣א
//         \\			</m>
//         \\		</w>
//         \\	</option>
//         ,
//         \\P= וְ/לֹ֣א	H3808
//     );
// }
