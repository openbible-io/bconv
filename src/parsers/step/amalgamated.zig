//! Parser for TAHOT and TAGNT.
//!
//! This is a weird TSV file with no consistent comment markers and duplicate header rows before
//! every verse. Variants are not always consistent and require some alignment with the main
//! variant.
//!
//! Original source files: https://github.com/STEPBible/STEPBible-Data
//! My fork: https://github.com/openbible-io/step
//!
//! The original source is a downstream goodwill fork of what's served on https://www.stepbible.org
//! Currently it's maintained by a single Tyndale employee. Despite all these shortcomings, it's
//! the best openly licensed amalgamated source for the Protestant canon.
const std = @import("std");
const Bible = @import("../../Bible.zig");
const Reference = @import("./Reference.zig");

const log = std.log.scoped(.step);
const Allocator = std.mem.Allocator;
const Morpheme = Bible.Morpheme;
const SourceSet = Bible.SourceSet;

pub fn parse(allocator: Allocator, fname: []const u8, out: *Bible) !void {
    var file = try std.fs.cwd().openFile(fname, .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    const reader = buf_reader.reader();

    var maybe_bom: [3]u8 = undefined;
    const bom_len = try reader.read(&maybe_bom);
    if (!std.mem.eql(u8, maybe_bom[0..bom_len], &[_]u8{ 0xef, 0xbb, 0xbf })) {
        buf_reader.start = 0;
    }

    var line = try std.ArrayList(u8).initCapacity(allocator, 4096);
    defer line.deinit();

    var parser = Parser.init(allocator, fname);
    defer parser.deinit();

    const writer = line.writer();
    while (reader.streamUntilDelimiter(writer, '\n', null)) {
        defer line.clearRetainingCapacity();
        _ = try parser.parseLine(line.items);
    } else |err| switch (err) {
        error.EndOfStream => {
            if (line.items.len > 0) _ = try parser.parseLine(line.items);
        },
        else => return err,
    }

    var parsed = try parser.bible_builder.toOwned();
    defer parsed.books.deinit();
    var iter = parsed.books.iterator();
    while (iter.next()) |kv| try out.books.put(kv.key_ptr.*, kv.value_ptr.*);
}

const Parser = struct {
    allocator: Allocator,
    bible_builder: Bible.Builder,
    builder: *Bible.Book.Builder = undefined,
    ref: Reference = undefined,
    line_no: usize = 0,
    /// logging
    fname: []const u8 = "",

    pub fn init(allocator: Allocator, fname: []const u8) @This() {
        return .{
            .allocator = allocator,
            .bible_builder = Bible.Builder.init(allocator),
            .fname = fname,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.bible_builder.deinit();
    }

    fn parseVariant(self: *@This(), buf: []const u8, is_spelling: bool) !void {
        // spelling buf: B= עֲבָדִֽ֑ים\׃ ¦ P= עֲבָדִ֑ים\׃
        // meaning buf:  K= ha/me.for.va.tzim (הַ/מְפֹרוָצִים) "<the>/ [had been] broken down" (H9009/H6555=HTd/Pp3mp) ¦ B= he/m.fe.ru.tzim (הֵ֣/מפְּרוּצִ֔ים) "<the>/ [had been] broken down" (H9009/H6555=HTd/Pp3mp)
        if (buf.len == 0) return;
        // cannot simply split on ¦ because 0xA6 is after the 0x7F unicode cutoff.
        // hebrew letters like צֵ contain 0xA6.
        var iter = try Utf8Iter.init(buf);
        var start: usize = 0;
        while (iter.it.i < buf.len) {
            iter.consumeAny(&[_]u21{ ' ', '¦', ';' });
            start = iter.it.i;

            const source_set_end = iter.findNextScalar('=') orelse return error.VariantMissingEqual;
            const source_set = try SourceSet.parse(buf[start..source_set_end]);
            // consume =
            iter.it.i += 1;

            const children = if (is_spelling) brk: {
                const text_end = iter.findNextAny(&[_]u21{ '¦' }) orelse buf.len;
                const text = std.mem.trim(u8, buf[source_set_end + 1..text_end], " ");
                if (text.len == 0) break;
                iter.consumeAny(&[_]u21{ ' ', '¦', ';' });

                break :brk try self.parseText(text);
            } else brk: {
                var paren_start = (iter.findNextScalar('(') orelse return error.VariantMissingLeftParen) + 1;
                var paren_end = iter.findNextScalar(')') orelse return error.VariantMissingRightParen;
                const text = buf[paren_start..paren_end];

                // strongs and grammar
                paren_start = (iter.findNextScalar('(') orelse return error.VariantMissingLeftParen2) + 1;
                const equal = iter.findNextScalar('=') orelse return error.VariantMissingStrongGrammarDelimiter;
                paren_end = iter.findNextScalar(')') orelse return error.VariantMissingRightParen2;
                const strong = buf[paren_start..equal];
                const grammar = buf[equal + 1..paren_end];

                break :brk try self.parseMorphemes(text, strong, grammar);
            };
            for (children) |*c| c.tags.source = source_set;
        }
    }

    fn parseVariants(
        self: *@This(),
        main: []Bible.Morpheme,
        meaning: []const u8,
        spelling: []const u8,
    ) !void {
        // not ideal, but better than having to make a temporary separate arraylist
        const has_variants = meaning.len > 0 or spelling.len > 0;
        if (!has_variants) return;

        if (main.len == 0) {
            const empty_morph = Morpheme{ .tags = .{
                .source = self.ref.source,
                .variant = .start
            }};
            try self.builder.morphemes.append(empty_morph);
        } else {
            main[0].tags.variant = .start;
        }

        self.parseVariant(meaning, false) catch |e| {
            self.warn("{} for meaning {s}", .{ e, meaning });
        };
        self.parseVariant(spelling, true) catch |e| {
            self.warn("{} for spelling {s}", .{ e, spelling });
        };

        self.builder.morphemes.items[self.builder.morphemes.items.len - 1].tags.variant = .end;
    }

    fn parseText(self: *@This(), text: []const u8) ![]Morpheme {
        const start = self.builder.morphemes.items.len;

        var morph_iter = std.mem.splitAny(u8, text, "/\\");
        var starts_word = true;
        // strange loop to get index of split to check for punctuation
        while (morph_iter.peek()) |token| : (_ = morph_iter.next()) {
            const tok = std.mem.trim(u8, token, &std.ascii.whitespace);
            const pooled = try self.builder.pool.getOrPut(tok);

            // \ indicates punctuation, expect for ~10 places where
            // `a/־/c` is incorrectly written instead of `a/\־/c`
            const text_i = morph_iter.index.?;
            const is_punctuation = text_i > 0 and (text[text_i - 1] == '\\' or std.mem.eql(u8, tok, "־"));

            if (tok.len == 0) {
                // a token length of 0 means the start of a new word
                // (ie `//` or `/ /` or `\ \פ`)
                starts_word = true;
                continue;
            }
            try self.builder.morphemes.append(Morpheme{
                .tags = .{
                    .source = self.ref.source,
                     // correct type will later be set from {Strong} OR if variant from alignment
                    .type = if (is_punctuation) .punctuation else  .root,
                },
                .text = pooled,
            });
            // std.debug.print("{s} {}\n", .{ tok, starts_word });
            if (starts_word) self.builder.n_words += 1;
            starts_word = false;
        }

        return self.builder.morphemes.items[start..];
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
    ) ![]Morpheme {
        // Only the first grammar includes the language...
        const lang: Morpheme.Lang = if (grammars.len < 1)
           .unknown
        else
            switch (grammars[0]) {
                'H' => .hebrew,
                'A' => .aramaic,
                'G' => .greek,
                else => |c| {
                    self.warn("unknown morph language {c}", .{ c });
                    return error.GrammarInvalidLang;
                }
            };
        const grammars_trimmed = if (lang == .unknown) grammars else grammars[1..];

        const res = try self.parseText(texts);

        var strong_iter = std.mem.splitAny(u8, strongs, "/\\");
        var grammar_iter = std.mem.splitAny(u8, grammars_trimmed, "/\\");

        var seen_root = false;
        for (res) |*m| {
            while (strong_iter.next()) |strong| {
                const trimmed = std.mem.trim(u8, strong, " ");
                if (trimmed.len == 0) {
                    seen_root = false;
                    continue; // probably a `//` word boundary
                }

                var stream = std.io.fixedBufferStream(trimmed);
                var reader = stream.reader();

                const first = try reader.readByte();
                const is_root = first == '{' or res.len == 1;
                seen_root = seen_root or is_root;
                if (m.tags.type != .punctuation) {
                    m.tags.type = if (is_root) .root else if (seen_root) .suffix else .prefix;
                }
                m.tags.lang = switch (if (first == '{') try reader.readByte() else first) {
                    'H' => switch (lang) {
                        .unknown, .hebrew, .aramaic => .hebrew,
                        else => {
                            self.err("grammar lang is {s} but strong lang is hebrew", .{ @tagName(lang) });
                            return error.InvalidStrongLang;
                        }
                    },
                    'G' => switch (lang) {
                        .unknown, .greek => .greek,
                        else => {
                            self.err("grammar lang is {s} but strong lang is greek", .{ @tagName(lang) });
                            return error.InvalidStrongLang;
                        },
                        },
                    else => |c| {
                        self.err("invalid strong lang {c}", .{ c });
                        return error.InvalidStrongLang;
                    },
                };
                var strong_n: [4]u8 = undefined;
                _ = try reader.readAll(&strong_n);
                m.strong_n = try std.fmt.parseInt(u16, &strong_n, 10);
                m.strong_sense = reader.readByte() catch 0;
                if (m.strong_sense == '}') m.strong_sense = 0;
                break;
            }
            const text = self.builder.pool.get(m.text);
            if (m.strong_n == 0) self.warn("{s} missing strong", .{ text });

            // punctuation does not have grammar
            if (m.tags.type == .punctuation) continue;
            while (grammar_iter.next()) |grammar| {
                const trimmed = std.mem.trim(u8, grammar, " ");
                if (trimmed.len == 0) continue; // probably a `//` word boundary

                m.grammar = switch (lang) {
                    .unknown => return error.MorphCodeMissingLang,
                    .greek => return error.MorphCodeMissingLang,
                    .hebrew => .{ .hebrew = try Morpheme.Hebrew.parse(trimmed) },
                    .aramaic => .{ .aramaic = try Morpheme.Aramaic.parse(trimmed) },
                };
                break;
            }
            if (m.grammar.isNull()) self.warn("{s} missing grammar", .{ text });
        }

        return res;
    }

    fn parseLine2(self: *@This(), line: []const u8) ![]Morpheme {
        if (line.len == 0 or line[0] == '#') return &[_]Morpheme{};
        var fields = std.mem.splitScalar(u8, line, '\t');
        // NRSV(Heb) Ref & type
        const ref_type = fields.first();

        self.ref = Reference.parse(ref_type) catch return &[_]Morpheme{};
        self.builder = try self.bible_builder.getBook(self.ref.book, SourceSet{ .leningrad = true });

        const texts = fields.next() orelse return error.MissingFieldText;
        _ = fields.next() orelse return error.MissingFieldTransliteration;
        _ = fields.next() orelse return error.MissingFieldTranslation;
        const strongs = fields.next() orelse return error.MissingFieldStrong;
        const grammars = fields.next() orelse return error.MissingFieldGrammar;
        const meaning_variants = fields.next() orelse return error.MissingFieldMeaningVariant;
        const spelling_variants = fields.next() orelse return error.MissingFieldSpellingVariant;
        // _ = fields.next() orelse return error.MissingFieldRootStrong; // Root dStrong+Instance
        // _ = fields.next() orelse return error.MissingFieldAltStrong; // alt Strongs+Instance
        // _ = fields.next() orelse return error.MissingFieldConjoin; // conjoin word
        // _ = fields.next() orelse return error.MissingFieldExpanded; // expanded Strong tags

        const res = try self.parseMorphemes(texts, strongs, grammars);
        var has_root = res.len == 0;
        for (res) |m| {
            if (m.tags.type == .root) {
                has_root = true;
                break;
            }
        }
        if (!has_root) {
            self.warn("missing root", .{});
        }

        try self.parseVariants(res, meaning_variants, spelling_variants);

        return res;
    }

    pub fn parseLine(self: *@This(), line: []const u8) ![]Morpheme {
        self.line_no += 1;
        return self.parseLine2(line) catch |e| {
            std.debug.print("{s}:{d} {}:\n", .{ self.fname, self.line_no, e });
            std.debug.print("{s}\n", .{ line });
            return e;
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

fn testParse(line: []const u8, expected: []const Morpheme) !void {
    const allocator = std.testing.allocator;
    var parser = Parser.init(allocator, "buffer");
    defer parser.deinit();

    const actual = try parser.parseLine(line);
    // TODO: implement `expectEqualSlices` with untagged union support
    // OR use std.MultiArrayList
    for (expected, actual) |a, b| {
        try std.testing.expectEqual(a.tags, b.tags);
        try std.testing.expectEqual(a.strong_n, b.strong_n);
        try std.testing.expectEqual(a.strong_sense, b.strong_sense);
    }
}

test "prefix/suffix" {
    try testParse(
        \\Ecc.2.19#11=L	וְ/שֶׁ/חָכַ֖מְתִּי	ve./she./cha.Kham.ti	and/ that/ I worked skillfully	H9002/H9007/{H2449}	HC/Tr/Vqp1cs			H2449			H9002=ו=and/H9007=ש=which/{H2449=חָכַם=be wise}
        ,
        &[_]Morpheme{
            Morpheme{
                .tags = .{
                    .source = SourceSet{ .leningrad = true },
                    .type = .prefix,
                    .lang = .hebrew,
                },
                .text = 1,
                .strong_n = 9002,
            },
            Morpheme{
                .tags = .{
                    .source = SourceSet{ .leningrad = true },
                    .type = .prefix,
                    .lang = .hebrew,
                },
                .text = 2,
                .strong_n = 9007,
            },
            Morpheme{
                .tags = .{
                    .source = SourceSet{ .leningrad = true },
                    .type = .root,
                    .lang = .hebrew,
                },
                .text = 3,
                .strong_n = 2449,
            },
        }
    );
}

// test "variant" {
//     try testParse(
//         \\Ecc.4.8#15=Q(K)	עֵינ֖/וֹ	ei.na/v	eye/ his	{H5869A}/H9023	HNcfsc/Sp3ms	K= ei.na/v (עֵינָי/ו) "eyes/ his" (H5869A/H9023=HNcbdc/Sp3ms)	L= עֵינ֖י/וֹ ¦ ;	H5869A			{H5869A=עַ֫יִן=: eye»eye:1_eye}/H9023=Ps3m=his
//         ,
//         &[_]Morpheme{
//             Morpheme{
//                 .source = SourceSet{ .qere = true },
//                 .tags = .{ .variant = .start, .type = .root },
//                 .text = 1,
//                 .strong = .{ .lang = .hebrew, .n = 5869, .sense = 'a' },
//                 .code = try Bible.Morpheme.Code.parse("HNcfsc"),
//             },
//             Morpheme{
//                 .source = SourceSet{ .qere = true },
//                 .tags = .{ .type = .suffix },
//                 .text = 2,
//                 .strong = .{ .lang = .hebrew, .n = 5869, .sense = 'a' },
//                 .code = try Bible.Morpheme.Code.parse("HNcfsc"),
//             },
//         }
//     );
// }
