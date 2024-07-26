const std = @import("std");
const simargs = @import("simargs");
const usfm = @import("./usfm/mod.zig");
const step = @import("./step.zig");
const models = @import("./bible.zig");

const Bible = models.Bible;
pub const std_options = .{
    .log_level = .warn,
};
const Allocator = std.mem.Allocator;

pub fn writeXml(bible: Bible, writer: anytype) @TypeOf(writer).Error!void {
    std.io.Writer
}

fn parseBible(allocator: Allocator, fname: []const u8, out: *Bible) void {
    step.parseTxt(allocator, fname, out) catch |e| {
        std.debug.print("Error parsing {s}: {}\n", .{ fname, e });
        std.process.exit(1);
    };
}

pub fn main() !void {
    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // defer std.debug.assert(gpa.deinit() == .ok);
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var gpa = std.heap.ThreadSafeAllocator{ .child_allocator = arena.allocator() };
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

    var thread_pool: std.Thread.Pool = undefined;
    try thread_pool.init(.{ .allocator = allocator });
    defer thread_pool.deinit();
    var wg = std.Thread.WaitGroup{};

    var bible = Bible{};
    defer bible.deinit(allocator);

    for (opt.positional_args.items) |fname| {
        thread_pool.spawnWg(&wg, parseBible, .{ allocator, fname, &bible });
    }
    thread_pool.waitAndWork(&wg);
    wg.reset();

    try std.fs.cwd().makePath(opt.args.output_dir);
    var outdir = try std.fs.cwd().openDir(opt.args.output_dir, .{});
    defer outdir.close();

    var iter = bible.books.iterator();
    while (iter.next()) |kv| {
        if (kv.value.len == 0) continue;

        const fname = try std.fmt.allocPrint(
            allocator,
            "{s}{c}{s}.xml",
            .{ opt.args.output_dir, std.fs.path.sep, @tagName(kv.key) },
        );
        defer allocator.free(fname);

        const file = try outdir.createFile(fname, .{});
        defer file.close();

        try bible.writeXml(file.writer());
    }
}

test {
    _ = Bible;
    // _ = usfm;
}
