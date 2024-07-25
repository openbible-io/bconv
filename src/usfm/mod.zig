const std = @import("std");
const Parser = @import("./Parser.zig");
const Lexer = @import("./Lexer.zig");
const HtmlFormatter = @import("./element.zig").HtmlFormatter;
const ErrorContext = @import("./error.zig").ErrorContext;
const Element = Parser.Element;
const log = std.log.scoped(.usfm);

pub fn fmtLowerImpl(
    bytes: []const u8,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = fmt;
    _ = options;
    for (bytes) |c| try writer.writeByte(std.ascii.toLower(c));
}

fn fmtLower(bytes: []const u8) std.fmt.Formatter(fmtLowerImpl) {
    return .{ .data = bytes };
}

pub fn writeHtml(allocator: std.mem.Allocator, outdir: []const u8, fname: []const u8) !void {
    var file = try std.fs.cwd().openFile(fname, .{});
    defer file.close();

    const usfm = try file.readToEndAlloc(allocator, 1 << 31);

    var parser = Parser.init(allocator, usfm);
    defer parser.deinit();

    var book: ?[]const u8 = null;
    var outfile: ?std.fs.File = null;
    defer if (outfile) |o| o.close();

    const error_context = ErrorContext{
        .buffer_name = fname,
        .buffer = usfm,
        .stderr = std.io.getStdErr(),
    };
    var n_chapters: usize = 0;

    const doc = try parser.document();
    defer doc.deinit(allocator);
    try parser.errors.print(error_context, null);

    var formatter = HtmlFormatter{};

    for (doc.root.node.children) |ele| {
        // We only care about books + chapters
        switch (ele) {
            .node => |n| switch (n.tag) {
                .id => {
                    var split = std.mem.splitAny(u8, n.children[0].text, Lexer.whitespace);
                    formatter.book = split.first();
                    book = formatter.book;
                },
                .c => {
                    if (book == null) {
                        log.err("missing book id before chapter {s}", .{n.children[0].text});
                        return error.MissingBookId;
                    }
                    if (n.children.len == 0 or n.children[0] != .text) {
                        log.err("chapter missing text node at position 0", .{});
                        return error.InvalidChapterNumber;
                    }
                    const chapter = std.fmt.parseInt(u8, n.children[0].text, 10) catch {
                        log.err("could not parse chapter number {s}", .{n.children[0].text});
                        return error.InvalidChapterNumber;
                    };
                    const outname = try std.fmt.allocPrint(allocator, "{1s}{0c}{2s}{0c}{3d:0>3}.html", .{
                        std.fs.path.sep,
                        outdir,
                        fmtLower(book.?),
                        chapter,
                    });
                    defer allocator.free(outname);
                    try std.fs.cwd().makePath(std.fs.path.dirname(outname).?);
                    if (outfile) |o| o.close();
                    outfile = try std.fs.cwd().createFile(outname, .{});
                    n_chapters += 1;
                    formatter.chapter = chapter;
                    formatter.id = 0;
                },
                else => {},
            },
            .text => {},
        }
        if (outfile) |f| try formatter.fmt(f.writer(), ele);
    }

    if (n_chapters > 0) {
        std.debug.print("{s} -> {s}{c}{s}/{{001..{d:0>3}}}.html\n", .{
            fname,
            outdir,
            std.fs.path.sep,
            fmtLower(book.?),
            n_chapters,
        });
    } else {
        if (book == null) {
            log.err("missing book id in file {s}", .{fname});
            return error.MissingBookId;
        }
        const outname = try std.fmt.allocPrint(allocator, "{s}{c}{s}.html", .{
            outdir,
            std.fs.path.sep,
            fmtLower(book.?),
        });
        defer allocator.free(outname);
        try std.fs.cwd().makePath(std.fs.path.dirname(outname).?);
        const of = try std.fs.cwd().createFile(outname, .{});
        try formatter.fmt(of.writer(), doc.root);

        std.debug.print("{s} -> {s}\n", .{ fname, outname });
    }
}

test {
    _ = @import("./Lexer.zig");
    _ = @import("./Parser.zig");
}
