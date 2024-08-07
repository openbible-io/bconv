const Bible = @import("../bible.zig").Bible;
const xml = @import("zig-xml");

const fmtAttributeContent = xml.fmtAttributeContent;
const fmtElementContent = xml.fmtElementContent;

pub fn Writer(comptime Underlying: type) type {
    return struct {
        w: Underlying,
        depth: usize = 0,
        tab: []const u8 = "\t",

        pub const Error = Underlying.Error;

        pub fn header(self: *@This(), version: []const u8, encoding: []const u8) !void {
            try self.w.print(
                "<?xml version=\"{}\" encoding=\"{}\"?>",
                .{ fmtAttributeContent(version), fmtAttributeContent(encoding) },
            );
        }

        pub fn start(self: *@This(), tag: []const u8, attributes: ?[]const KV) !void {
            try self.w.writeByte('\n');
            try self.w.writeBytesNTimes(self.tab, self.depth);
            try self.w.print("<{s}", .{ tag });
            if (attributes) |as| {
                try self.w.writeByte(' ');
                for (as, 0..) |kv, i| {
                    try self.w.print("{s}=\"{s}\"", .{ kv[0], fmtAttributeContent(kv[1]) });
                    if (i != as.len - 1) try self.w.writeByte(' ');
                }
            }
            try self.w.writeByte('>');
            self.depth += 1;
        }

        pub fn text(self: *@This(), str: []const u8) !void {
            try self.w.writeByte('\n');
            try self.w.writeBytesNTimes(self.tab, self.depth);
            try self.w.print("{s}", .{ fmtElementContent(str) });
        }

        pub fn end(self: *@This(), tag: []const u8) !void {
            try self.w.writeByte('\n');
            self.depth -= 1;
            try self.w.writeBytesNTimes(self.tab, self.depth);
            try self.w.print("</{s}>", .{ tag });
        }
    };
}
pub const KV = [2][]const u8;

pub fn writeBook(book: Bible.Book, name: Bible.Book.Name, writer: anytype) !void {
}

pub fn write(bible: Bible, writer: anytype) !void {
}
