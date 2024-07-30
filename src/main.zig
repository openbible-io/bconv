const std = @import("std");
const simargs = @import("simargs");
const usfm = @import("./usfm/mod.zig");
const step = @import("./step.zig");
const Bible = @import("./Bible.zig");
const xml = @import("./xml.zig");
const string_pools = @import("./StringPools.zig");

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

    string_pools.global = string_pools.StringPools.init(allocator);
    defer string_pools.global.deinit();

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
    step.parseTxt(allocator, fname, out) catch |e| {
        std.debug.print("Error parsing {s}: {}\n", .{ fname, e });
        std.process.exit(1);
    };
}

fn writeFile2(allocator: Allocator, outdir: std.fs.Dir, key: Bible.BookName, val: Bible.Book) !void {
    const fname = try std.fmt.allocPrint(allocator, "{s}.xml", .{ @tagName(key) });
    defer allocator.free(fname);

    const file = try outdir.createFile(fname, .{});
    defer file.close();
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
    _ = step;
    _ = string_pools;
    // _ = usfm;
}
