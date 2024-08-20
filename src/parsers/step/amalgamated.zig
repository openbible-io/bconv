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
        try parser.parseLine(line.items);
    } else |err| switch (err) {
        error.EndOfStream => {
            if (line.items.len > 0) try parser.parseLine(line.items);
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

    // fn parseVariant(
    //     self: *@This(),
    //     buf: []const u8,
    //     is_spelling: bool,
    //     acc: *std.ArrayList(Variant.Option),
    // ) !void {
    //     // spelling buf: B= עֲבָדִֽ֑ים\׃ ¦ P= עֲבָדִ֑ים\׃
    //     // meaning buf:  K= ha/me.for.va.tzim (הַ/מְפֹרוָצִים) "<the>/ [had been] broken down" (H9009/H6555=HTd/Pp3mp) ¦ B= he/m.fe.ru.tzim (הֵ֣/מפְּרוּצִ֔ים) "<the>/ [had been] broken down" (H9009/H6555=HTd/Pp3mp)
    //     if (buf.len == 0) return;
    //     // cannot simply split on ¦ because 0xA6 is after the 0x7F unicode cutoff.
    //     // hebrew letters like צֵ contain 0xA6.
    //     var iter = try Utf8Iter.init(buf);
    //     var start: usize = 0;
    //     while (iter.it.i < buf.len) {
    //         iter.consumeAny(&[_]u21{ ' ', '¦', ';' });
    //         start = iter.it.i;
    //
    //         const source_set_end = iter.findNextScalar('=') orelse return error.VariantMissingEqual;
    //         var source_set = try SourceSet.parse(buf[start..source_set_end]);
    //         source_set.is_significant = !is_spelling;
    //         // consume =
    //         iter.it.i += 1;
    //
    //         const children = if (is_spelling) brk: {
    //             const text_end = iter.findNextAny(&[_]u21{ '¦' }) orelse buf.len;
    //             const text = std.mem.trim(u8, buf[source_set_end + 1..text_end], " ");
    //             if (text.len == 0) break;
    //             iter.consumeAny(&[_]u21{ ' ', '¦', ';' });
    //
    //             break :brk try self.parseText(text);
    //         } else brk: {
    //             var paren_start = (iter.findNextScalar('(') orelse return error.VariantMissingLeftParen) + 1;
    //             var paren_end = iter.findNextScalar(')') orelse return error.VariantMissingRightParen;
    //             const text = buf[paren_start..paren_end];
    //
    //             // strongs and grammar
    //             paren_start = (iter.findNextScalar('(') orelse return error.VariantMissingLeftParen2) + 1;
    //             const equal = iter.findNextScalar('=') orelse return error.VariantMissingStrongGrammarDelimiter;
    //             paren_end = iter.findNextScalar(')') orelse return error.VariantMissingRightParen2;
    //             const strong = buf[paren_start..equal];
    //             const grammar = buf[equal + 1..paren_end];
    //
    //             const res = try self.parseFields(text, strong, grammar, "", "");
    //
    //             break :brk res;
    //         };
    //
    //         if (children.len > 0) try acc.append(.{ .source_set = source_set, .children = children });
    //     }
    // }

    fn parseVariants(
        self: *@This(),
        main: []Bible.Morpheme,
        meaning: []const u8,
        spelling: []const u8,
    ) !void {
        _ = .{ self, main, meaning, spelling };
        // const allocator = self.allocator;
        // self.parseVariant(meaning, false, &options) catch |e| {
        //     self.warn("{} for meaning {s}", .{ e, meaning });
        // };
        // self.parseVariant(spelling, true, &options) catch |e| {
        //     self.warn("{} for spelling {s}", .{ e, spelling });
        // };

        // try alignVariants(&options);
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
                .source = self.ref.source,
                .text = pooled,
                .flags = .{
                    .starts_word = starts_word,
                     // if not punctuation, correct type will be set from {Strong}
                     // OR if variant from alignment
                    .type = if (is_punctuation) .punctuation else  .root,
                },
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

    fn parseMorphemes(
        self: *@This(),
        texts: []const u8,
        strongs: []const u8,
        grammars: []const u8,
    ) ![]Morpheme {
        const lang: ?Morpheme.Lang = if (grammars.len < 1)
           null
        else
            switch (grammars[0]) {
                'H' => .hebrew,
                'A' => .aramaic,
                'G' => .greek,
                else => |c| {
                    std.debug.print("unknown morph language {c}\n", .{ c });
                    return error.MorphInvalidLang;
                }
            };
        const grammars_trimmed = if (lang == null) grammars else grammars[1..];

        const res = try self.parseText(texts);

        var strong_iter = std.mem.splitAny(u8, strongs, "/\\");
        var grammar_iter = std.mem.splitAny(u8, grammars_trimmed, "/\\");

        for (res) |*m| {
            var seen_root = false;
            const text = self.builder.pool.get(m.text).?;
            while (strong_iter.next()) |strong| {
                const trimmed = std.mem.trim(u8, strong, " ");
                if (trimmed.len == 0) continue; // probably a `//` word boundary

                const left_brace = trimmed[0] == '{';
                const is_root = left_brace or res.len == 1;
                seen_root = is_root;
                if (m.flags.type != .punctuation) {
                    m.flags.type = if (is_root) .root else if (seen_root) .suffix else .prefix;
                }
                m.strong = try Bible.Morpheme.Strong.parse(trimmed[if (left_brace) 1 else 0..]);
                break;
            }
            if (m.strong.isNull()) {
                self.warn("{s} ({s}) missing strong", .{ text, @tagName(m.flags.type) });
            }

            // punctuation does not have grammar
            if (m.flags.type == .punctuation) continue;
            while (grammar_iter.next()) |grammar| {
                const trimmed = std.mem.trim(u8, grammar, " ");
                if (trimmed.len == 0) continue; // probably a `//` word boundary

                if (lang == null) return error.MorphCodeMissingLang;
                m.code = switch (lang.?) {
                    .greek => return error.MorphCodeMissingLang,
                    .hebrew => .{ .tag = .hebrew, .value = .{ .hebrew = try Morpheme.Hebrew.parse(trimmed) } },
                    .aramaic => .{ .tag = .aramaic, .value = .{ .aramaic = try Morpheme.Aramaic.parse(trimmed) } },
                };
                break;
            }
            if (m.code.isNull()) {
                self.warn("{s} ({s}) missing grammar", .{ text, @tagName(m.flags.type) });
            }
        }

        return res;
    }

    fn parseLine2(self: *@This(), line: []const u8) !void {
        if (line.len == 0 or line[0] == '#') return;
        var fields = std.mem.splitScalar(u8, line, '\t');
        // NRSV(Heb) Ref & type
        const ref_type = fields.first();

        self.ref = Reference.parse(ref_type) catch return;
        self.builder = try self.bible_builder.getBook(self.ref.book);
        self.builder.source = SourceSet{ .leningrad = true };

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

        const morphs = try self.parseMorphemes(texts, strongs, grammars);
        try self.parseVariants(morphs, meaning_variants, spelling_variants);
    }

    pub fn parseLine(self: *@This(), line: []const u8) !void {
        self.line_no += 1;
        self.parseLine2(line) catch |e| {
            std.debug.print("{s}:{d} {}:\n", .{ self.fname, self.line_no, e });
            std.debug.print("{s}\n", .{ line });
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
