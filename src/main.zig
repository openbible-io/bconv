const std = @import("std");
const simargs = @import("simargs");
const Bible = @import("./bible.zig").Bible;
const parsers = @import("./parsers/mod.zig");
const exporters = @import("./exporters/mod.zig");
const StringPool = @import("./StringPool.zig");

pub const std_options = .{
    .log_level = .warn,
};
const Allocator = std.mem.Allocator;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    // var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // defer arena.deinit();
    // var gpa = std.heap.ThreadSafeAllocator{ .child_allocator = arena.allocator() };
    const allocator = gpa.allocator();

    var opt = try simargs.parse(allocator, struct {
        output_dir: []const u8 = "dist",
        help: bool = false,

        pub const __shorts__ = .{
            .output_dir = .o,
            .help = .h,
        };
    }, "[file]", null);
    defer opt.deinit();

    StringPool.global = StringPool.init(allocator);
    defer StringPool.global.deinit();

    var thread_pool: std.Thread.Pool = undefined;
    try thread_pool.init(.{ .allocator = allocator });
    defer thread_pool.deinit();
    var wg = std.Thread.WaitGroup{};

    var bible = Bible.init(allocator);
    defer bible.deinit();

    for (opt.positional_args.items) |fname| {
        thread_pool.spawnWg(&wg, parseBible, .{ allocator,  fname, &bible });
    }
    thread_pool.waitAndWork(&wg);
    wg.reset();

    try std.fs.cwd().makePath(opt.args.output_dir);
    var outdir = try std.fs.cwd().openDir(opt.args.output_dir, .{});
    defer outdir.close();

    var iter = bible.books.iterator();
    while (iter.next()) |kv| {
        thread_pool.spawnWg(&wg, writeFile, .{ allocator, outdir, kv.key_ptr.*, kv.value_ptr.* });
    }
    thread_pool.waitAndWork(&wg);
}

fn parseBible(allocator: Allocator, fname: []const u8, out: *Bible) void {
    parsers.step.amalgamated.parse(allocator, fname, out) catch |e| {
        std.debug.print("Error parsing {s}: {}\n", .{ fname, e });
        std.process.exit(1);
    };
}

fn writeFile2(allocator: Allocator, outdir: std.fs.Dir, key: Bible.BookName, val: Bible.Book) !void {
    const fname = try std.fmt.allocPrint(allocator, "{s}.xml", .{ @tagName(key) });
    defer allocator.free(fname);

    const file = try outdir.createFile(fname, .{});
    defer file.close();
    try exporters.xml.writeBook(val, key, file.writer());
    var writer: xml.Writer(std.fs.File.Writer) = .{ .w = file.writer() };
    try val.writeXml(&writer, key);
}

fn writeFile(allocator: Allocator, outdir: std.fs.Dir, key: Bible.BookName, val: Bible.Book) void {
    writeFile2(allocator, outdir, key, val) catch |e| {
        std.debug.print("Error writing {s}: {}\n", .{ @tagName(key), e });
        std.process.exit(2);
    };
}

test {
    _ = Bible;
    _ = parsers;
}
