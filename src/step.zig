const std = @import("std");
const Bible = @import("./Bible.zig");

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

fn parseLine(allocator: Allocator, line: []const u8, line_no: usize, out: *Bible) !void {
    _ = .{ allocator, out };

    var split = std.mem.splitScalar(u8, line, '\t');
    // NRSV(Heb) Ref & type
    const ref_type = split.first();
    const ref = Reference.parse(ref_type) catch return;
    const v0: u6 = @bitCast(ref.variants[0]);
    std.debug.assert(v0 != 0 or std.mem.indexOfScalar(u8, ref_type, '(') == null);
    _ = .{ line_no };

    const hebrew = split.next() orelse return error.MissingField;
    var morphemes = std.mem.splitScalar(u8, hebrew, '/');
    while (morphemes.next()) |m| {
        _ = m;
    }

    _ = split.next() orelse return error.MissingField; // transliteration
    _ = split.next() orelse return error.MissingField; // translation
    _ = split.next() orelse return error.MissingField; // dStrongs
    _ = split.next() orelse return error.MissingField; // grammar
    _ = split.next() orelse return error.MissingField; // meaning
    _ = split.next() orelse return error.MissingField; // meaning variant
    _ = split.next() orelse return error.MissingField; // spelling variant
    _ = split.next() orelse return error.MissingField; // Root dStrong+Instance
    _ = split.next() orelse return error.MissingField; // alt Strongs+Instance
    _ = split.next() orelse return error.MissingField; // conjoin word
    _ = split.next() orelse return error.MissingField; // expanded Strong tags
}

pub fn parseTxt(allocator: Allocator, fname: []const u8, out: *Bible) !void {
    var file = try std.fs.cwd().openFile(fname, .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    const reader = buf_reader.reader();

    var line = try std.ArrayList(u8).initCapacity(allocator, 4096);
    defer line.deinit();

    const writer = line.writer();
    var line_no: usize = 0;
    while (reader.streamUntilDelimiter(writer, '\n', null)) {
        defer line.clearRetainingCapacity();
        line_no += 1;

        try parseLine(allocator, line.items, line_no, out);
    } else |err| switch (err) {
        error.EndOfStream => { // end of file
            if (line.items.len > 0) {
                line_no += 1;
                try parseLine(allocator, line.items, line_no, out);
            }
        },
        else => return err, // Propagate error
    }
}
