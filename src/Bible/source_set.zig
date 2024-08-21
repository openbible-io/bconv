const std = @import("std");

pub const SourceSet = packed struct(u15) {
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
    const Int = @typeInfo(@This()).Struct.backing_integer.?;

    pub fn parse(str: []const u8) !@This() {
        var res = @This(){};
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
                ' ',
                '\t',
                '/',
                => {},
                else => {
                    std.debug.print("unknown source {c}\n", .{c});
                    return error.InvalidSource;
                },
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
            if (@field(self, f.name)) {
                try writer.writeAll(f.name);
                if (n_written != n_sources - 1) try writer.writeByte(',');
                n_written += 1;
            }
        }
    }

    pub fn isNull(self: @This()) bool {
        return @as(Int, @bitCast(self)) == 0;
    }

    pub fn eql(self: @This(), other: @This()) bool {
        return @as(Int, @bitCast(self)) == @as(Int, @bitCast(other));
    }
};
