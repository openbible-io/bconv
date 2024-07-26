const xml = @import("zig-xml");

const fmtAttributeContent = xml.fmtAttributeContent;
const fmtElementContent = xml.fmtElementContent;

pub fn Writer(comptime Underlying: type) type {
    return struct {
        w: Underlying,
        depth: usize = 0,
        tab: []const u8 = "\t",

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
                for (as) |kv| {
                    try self.w.print("{s}=\"{s}\"", .{ kv[0], fmtAttributeContent(kv[1]) });
                }
            }
            try self.w.writeBytesNTimes(self.tab, self.depth);
            try self.w.writeByte('>');
            self.depth += 1;
        }

        pub fn text(self: *@This(), str: []const u8) !void {
            try self.w.writeByte('\n');
            try self.w.writeBytesNTimes(self.tab, self.depth + 1);
            try self.w.print("{s}", .{ fmtElementContent(str) });
        }

        pub fn end(self: *@This(), tag: []const u8) !void {
            try self.w.writeByte('\n');
            try self.w.writeBytesNTimes(self.tab, self.depth);
            try self.w.print("</{s}>", .{ tag });
            self.depth -= 1;
        }
    };
}

pub const KV = [2][]const u8;
