books: Books,

pub const Books = std.AutoArrayHashMap(BookName, Book);

pub fn init(allocator: Allocator) @This() {
    return .{ .books = Books.init(allocator)};
}

pub fn deinit(self: *@This()) void {
    const allocator = self.books.allocator;
    var iter = self.books.iterator();
    while (iter.next()) |kv| kv.value_ptr.deinit(allocator);
    self.books.deinit();
}

pub const Book = struct {
    elements: []Element,

    pub fn writeXml(self: @This(), writer: anytype, name: BookName) !void {
        // xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        // xsi:noNamespaceSchemaLocation="shiporder.xsd"
        try writer.header("1.0", "UTF-8");
        try writer.start("book", &[_]KV{ .{ "id", @tagName(name) } });
        for (self.elements) |e| try e.writeXml(writer);
        try writer.end("book");
    }

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        for (self.elements) |e| e.deinit(allocator);
        allocator.free(self.elements);
    }
};

pub const Element = union(enum) {
    word: Word,
    quote: Quote,
    variant: Variant,
    punctuation: Punctuation,

    pub const Word = struct {
        ref: Reference,
        morphemes: []Morpheme,

        pub fn writeXml(self: @This(), writer: anytype) !void {
            var buf: [16]u8 = undefined;
            var stream = std.io.fixedBufferStream(&buf);
            try self.ref.write(stream.writer());

            try writer.start("w", &[_]KV{ .{ "id", stream.getWritten() } });
            for (self.morphemes) |m| try m.writeXml(writer);
            try writer.end("w");
        }

        pub const Reference = packed struct(u32) {
            book: BookName,
            chapter: u8,
            verse: u8,
            word: u8,

            pub fn write(self: @This(), writer: anytype) !void {
                try writer.print("{s}{d}:{d}#{d}", .{ @tagName(self.book), self.chapter, self.verse, self.word },);
            }
        };

        pub const Morpheme = struct {
            type: Type = .root,
            code: ?morphology.Code = null,
            strong: ?Strong = null,
            text: []const u8,

            pub const Type = enum {
                root,
                prefix,
                suffix,
            };

            pub const Strong = struct {
                n: u16,
                lang: @This().Lang,
                sense: u8,

                pub const Lang = enum { hebrew, aramaic, greek };

                pub fn parse(in: []const u8) !@This() {
                    if (in.len == 0) return error.StrongEmpty;
                    const lang: @This().Lang = switch (std.ascii.toLower(in[0])) {
                        'h' => .hebrew,
                        'a' => .aramaic,
                        'g' => .greek,
                        else => return error.StrongInvalidLang,
                    };
                    var i: usize = 1;
                    while (i < in.len and std.ascii.isDigit(in[i])) : (i += 1) {}
                    const n = try std.fmt.parseInt(u16, in[1..i], 10);
                    const sense = if (in.len == i + 1 and std.ascii.isAlphabetic(in[i])) in[i] else 0;

                    return .{  .n = n, .lang = lang, .sense = sense };
                }

                pub fn write(self: @This(), writer: anytype) !void {
                    try writer.writeByte(switch (self.lang) {
                        .hebrew => 'H',
                        .aramaic => 'A',
                        .greek => 'G',
                    });
                    try writer.print("{d:0>4}", .{ self.n });
                    if (self.sense != 0) try writer.writeByte(self.sense);
                }
            };

            pub fn writeXml(self: Morpheme, writer: anytype) !void {
                var buf1: [8]u8 = undefined;
                var stream1 = std.io.fixedBufferStream(&buf1);
                if (self.code) |c| try c.write(stream1.writer());

                var buf2: [8]u8 = undefined;
                var stream2 = std.io.fixedBufferStream(&buf2);
                if (self.strong) |s| try s.write(stream2.writer());

                try writer.start("m", &[_]KV{
                    .{ "type", @tagName(self.type) },
                    .{ "code", stream1.getWritten() },
                    .{ "strong", stream2.getWritten() },
                });
                try writer.text(self.text);
                try writer.end("m");
            }
        };

        pub fn deinit(self: @This(), allocator: Allocator) void {
            allocator.free(self.morphemes);
        }
    };

    pub const Quote = struct {
        by: []const u8,
        children: []Element,

        pub fn writeXml(self: @This(), writer: anytype) !void {
            try writer.start("q", &[_]KV{ .{ "by", self.by } });
            for (self.children) |c| try c.writeXml(writer);
            try writer.end("q");
        }

        pub fn deinit(self: @This(), allocator: Allocator) void {
            for (self.children) |c| c.deinit(allocator);
        }
    };

    pub const Variant = struct {
        options: []Option,

        pub const Option = struct {
            source_set: SourceSet,
            /// May not contain further variants. Enforced in `.normalize`.
            children: []Element,

            pub fn writeXml(self: @This(), writer: anytype) !void {
                var buf: [32]u8 = undefined;
                var stream = std.io.fixedBufferStream(&buf);
                try self.source_set.write(stream.writer());

                try writer.start("option", &[_]KV{
                    .{ "is_significant", if (self.source_set.is_significant) "true" else "false" },
                    .{ "source_set", stream.getWritten() },
                });
                for (self.children) |c| try c.writeXml(writer);
                try writer.end("option");
            }

            pub fn deinit(self: @This(), allocator: Allocator) void {
                for (self.children) |c| c.deinit(allocator);
                allocator.free(self.children);
            }

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

                pub fn write(self: @This(), writer: anytype) !void {
                    var n_sources: usize = 0;
                    inline for (std.meta.fields(@This())) |f| {
                        if (@field(self, f.name)) n_sources += 1;
                    }

                    var n_written: usize = 0;
                    inline for (std.meta.fields(@This())) |f| {
                        comptime if (std.mem.eql(u8, f.name, "is_significant")) continue;
                        if (@field(self, f.name)) {
                            try writer.writeAll(f.name);
                            n_written += 1;
                            if (n_written != n_sources - 1) try writer.writeByte(',');
                        }
                    }
                }
            };
        };

        pub fn writeXml(self: @This(), writer: anytype) !void {
            try writer.start("variant", null);
            for (self.options) |o| try o.writeXml(writer);
            try writer.end("variant");
        }

        pub fn deinit(self: @This(), allocator: Allocator) void {
            for (self.options) |o| o.deinit(allocator);
            allocator.free(self.options);
        }
    };

    pub const Punctuation = struct {
        text: []const u8,

        pub fn writeXml(self: @This(), writer: anytype) !void {
            try writer.start("p", null);
            try writer.text(self.text);
            try writer.end("p");
        }
    };

    pub fn deinit(self: @This(), allocator: Allocator) void {
        switch (self) {
            .word => |v| v.deinit(allocator),
            .quote => |v| v.deinit(allocator),
            .variant => |v| v.deinit(allocator),
            // .fragment => |v| v.deinit(allocator),
            .punctuation => {},
        }
    }

    pub fn writeXml(self: @This(), writer: anytype) (@TypeOf(writer.*).Error || error{NoSpaceLeft})!void {
        switch (self) {
            inline else => |e| try e.writeXml(writer),
        }
    }
};
/// Book, chapter, verse
pub const Bcv = struct {
    verse: u8,
    chapter: u8,
    book: BookName,

    pub fn lessThan(self: @This(), other: @This()) bool {
        const self_book = @intFromEnum(self.book);
        const other_book = @intFromEnum(self.book);
        return self_book < other_book or self.chapter < other.chapter or self.verse < other.verse;
    }

    pub fn toCv(self: @This()) Cv {
        return .{ .chapter = self.chapter, .verse = self.verse };
    }
};
/// Chapter, verse
pub const Cv = packed struct(u16) {
    verse: u8,
    chapter: u8,

    pub fn lessThan(self: @This(), other: @This()) bool {
        return self.chapter < other.chapter or self.verse < other.verse;
    }
};
/// Chapter, verse, word
pub const Cvw = packed struct(u24) {
    word: u8,
    verse: u8,
    chapter: u8,

    pub fn lessThan(self: @This(), other: @This()) bool {
        return self.chapter < other.chapter or self.verse < other.verse or self.word < other.word;
    }
};

pub const BookName = enum(u8) {
    gen,
    exo,
    lev,
    num,
    deu,
    jos,
    jdg,
    rut,
    @"1sa",
    @"2sa",
    @"1ki",
    @"2ki",
    @"1ch",
    @"2ch",
    ezr,
    neh,
    est,
    job,
    psa,
    pro,
    ecc,
    sng,
    isa,
    jer,
    lam,
    ezk,
    dan,
    hos,
    jol,
    amo,
    oba,
    jon,
    mic,
    nam,
    hab,
    zep,
    hag,
    zec,
    mal,
    mat,
    mrk,
    luk,
    jhn,
    act,
    rom,
    @"1co",
    @"2co",
    gal,
    eph,
    php,
    col,
    @"1th",
    @"2th",
    @"1ti",
    @"2ti",
    tit,
    phm,
    heb,
    jas,
    @"1pe",
    @"2pe",
    @"1jn",
    @"2jn",
    @"3jn",
    jud,
    rev,

    pub fn fromEnglish(name: []const u8) !@This() {
        var normalized: [32]u8 = undefined;
        if (name.len > normalized.len) return error.LongName;

        var normalized_len: usize = 0;
        for (name) |c| {
            if (std.ascii.isWhitespace(c)) continue;
            normalized[normalized_len] = std.ascii.toLower(c);
            normalized_len += 1;
        }
        const n = normalized[0..normalized_len];

        const startsWith = struct {
            fn startsWith(a: []const u8, b: []const u8) bool {
                return std.mem.startsWith(u8, a, b);
            }
        }.startsWith;
        const eql = struct {
            fn eql(a: []const u8, b: []const u8) bool {
                return std.mem.eql(u8, a, b);
            }
        }.eql;

        if (startsWith(n, "gen")) return .gen;
        if (startsWith(n, "exo")) return .exo;
        if (startsWith(n, "lev")) return .lev;
        if (startsWith(n, "num")) return .num;
        if (startsWith(n, "deu")) return .deu;
        if (startsWith(n, "jos")) return .jos;
        if (startsWith(n, "judg") or eql(n, "jdg")) return .jdg;
        if (startsWith(n, "rut")) return .rut;
        if (startsWith(n, "1sa") or eql(n, "samuel1") or eql(n, "samueli")) return .@"1sa";
        if (startsWith(n, "2sa") or eql(n, "samuel2") or eql(n, "samuelii")) return .@"2sa";
        if (startsWith(n, "1ki") or eql(n, "kings1") or eql(n, "kingsi") or startsWith(n, "1kg")) return .@"1ki";
        if (startsWith(n, "2ki") or eql(n, "kings2") or eql(n, "kingsii") or startsWith(n, "2kg")) return .@"2ki";
        if (startsWith(n, "1ch") or eql(n, "chronicles1") or eql(n, "chroniclesi")) return .@"1ch";
        if (startsWith(n, "2ch") or eql(n, "chronicles2") or eql(n, "chroniclesii")) return .@"2ch";
        if (startsWith(n, "ezr")) return .ezr;
        if (startsWith(n, "neh")) return .neh;
        if (startsWith(n, "est")) return .est;
        if (startsWith(n, "job")) return .job;
        if (startsWith(n, "ps")) return .psa;
        if (startsWith(n, "pr")) return .pro;
        if (startsWith(n, "ecc") or startsWith(n, "qoh")) return .ecc;
        if (startsWith(n, "song") or eql(n, "sng") or startsWith(n, "cant")) return .sng;
        if (startsWith(n, "isa")) return .isa;
        if (startsWith(n, "jer")) return .jer;
        if (startsWith(n, "lam")) return .lam;
        if (startsWith(n, "eze") or eql(n, "ezk")) return .ezk;
        if (startsWith(n, "dan")) return .dan;
        if (startsWith(n, "hos")) return .hos;
        if (startsWith(n, "joe") or eql(n, "jol")) return .jol;
        if (startsWith(n, "am")) return .amo;
        if (startsWith(n, "oba")) return .oba;
        if (startsWith(n, "jon")) return .jon;
        if (startsWith(n, "mic")) return .mic;
        if (startsWith(n, "na")) return .nam;
        if (startsWith(n, "hab")) return .hab;
        if (startsWith(n, "zep")) return .zep;
        if (startsWith(n, "hag")) return .hag;
        if (startsWith(n, "zec")) return .zec;
        if (startsWith(n, "mal")) return .mal;
        if (startsWith(n, "mat")) return .mat;
        if (startsWith(n, "mar") or eql(n, "mrk")) return .mrk;
        if (startsWith(n, "luk")) return .luk;
        if (startsWith(n, "joh") or eql(n, "jhn")) return .jhn;
        if (startsWith(n, "act")) return .act;
        if (startsWith(n, "rom")) return .rom;
        if (startsWith(n, "1co") or eql(n, "corinthians1") or eql(n, "corinthiansi")) return .@"1co";
        if (startsWith(n, "2co") or eql(n, "corinthians2") or eql(n, "corinthiansii")) return .@"2co";
        if (startsWith(n, "gal")) return .gal;
        if (startsWith(n, "eph")) return .eph;
        if (startsWith(n, "philip") or eql(n, "php")) return .php;
        if (startsWith(n, "col")) return .col;
        if (startsWith(n, "1th") or eql(n, "thessalonians1") or eql(n, "thessaloniansi")) return .@"1th";
        if (startsWith(n, "2th") or eql(n, "thessalonians2") or eql(n, "thessaloniansii")) return .@"2th";
        if (startsWith(n, "1ti") or eql(n, "timothy1") or eql(n, "timothyi")) return .@"1ti";
        if (startsWith(n, "2ti") or eql(n, "timothy2") or eql(n, "timothyii")) return .@"2ti";
        if (startsWith(n, "tit")) return .tit;
        if (startsWith(n, "phile") or eql(n, "phm") or eql(n, "phlm")) return .phm;
        if (startsWith(n, "heb")) return .heb;
        if (startsWith(n, "ja") or eql(n, "jas")) return .jas;
        if (startsWith(n, "1pe") or eql(n, "peter1") or eql(n, "peteri")) return .@"1pe";
        if (startsWith(n, "2pe") or eql(n, "peter2") or eql(n, "peterii")) return .@"2pe";
        if (startsWith(n, "1jo") or eql(n, "1jn") or eql(n, "john1") or eql(n, "johni")) return .@"1jn";
        if (startsWith(n, "2jo") or eql(n, "2jn") or eql(n, "john2") or eql(n, "johnii")) return .@"2jn";
        if (startsWith(n, "3jo") or eql(n, "3jn") or eql(n, "john3") or eql(n, "johniii")) return .@"3jn";
        if (startsWith(n, "jud")) return .jud; // must come after judges
        if (startsWith(n, "rev")) return .rev;

        // std.debug.print("invalid book name '{s}' (normalized to '{s}')\n", .{ name, n });
        return error.InvalidBookName;
    }

    pub fn isOld(self: @This()) bool {
        return !self.isNew();
    }

    pub fn isNew(self: @This()) bool {
        return @intFromEnum(self) > @intFromEnum(.mat);
    }

    pub fn nChapters(self: @This()) usize {
        return switch (self) {
            .gen => 50,
            .exo => 40,
            .lev => 27,
            .num => 36,
            .deu => 34,
            .jos => 24,
            .jdg => 21,
            .rut => 4,
            .@"1sa" => 31,
            .@"2sa" => 24,
            .@"1ki" => 22,
            .@"2ki" => 25,
            .@"1ch" => 29,
            .@"2ch" => 36,
            .ezr => 10,
            .neh => 13,
            .est => 10,
            .job => 42,
            .psa => 150,
            .pro => 31,
            .ecc => 12,
            .sng => 8,
            .isa => 66,
            .jer => 52,
            .lam => 5,
            .ezk => 48,
            .dan => 12,
            .hos => 14,
            .jol => 3,
            .amo => 9,
            .oba => 1,
            .jon => 4,
            .mic => 7,
            .nam => 3,
            .hab => 3,
            .zep => 3,
            .hag => 2,
            .zec => 14,
            .mal => 4,
            .mat => 28,
            .mrk => 16,
            .luk => 24,
            .jhn => 21,
            .act => 28,
            .rom => 16,
            .@"1co" => 16,
            .@"2co" => 13,
            .gal => 6,
            .eph => 6,
            .php => 4,
            .col => 4,
            .@"1th" => 5,
            .@"2th" => 3,
            .@"1ti" => 6,
            .@"2ti" => 4,
            .tit => 3,
            .phm => 1,
            .heb => 13,
            .jas => 5,
            .@"1pe" => 5,
            .@"2pe" => 3,
            .@"1jn" => 5,
            .@"2jn" => 1,
            .@"3jn" => 1,
            .jud => 1,
            .rev => 22,
        };
    }
};

test BookName {
    try std.testing.expectEqual(BookName.gen, try BookName.fromEnglish("Genesis"));
    try std.testing.expectEqual(BookName.@"1ch", try BookName.fromEnglish("1  Chronicles"));
}

test {
    _ = morphology;
}

const std = @import("std");
const KV = @import("./xml.zig").KV;
const morphology = @import("./morphology/mod.zig");
const Allocator = std.mem.Allocator;
const tab = '\t';
