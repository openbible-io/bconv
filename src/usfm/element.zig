const std = @import("std");
const Tag = @import("./tag.zig").Tag;
const whitespace = @import("./Lexer.zig").whitespace;

pub const Element = union(enum) {
    node: Node,
    text: []const u8,

    pub const Node = struct {
        pub const Attribute = struct {
            key: []const u8,
            value: []const u8,
        };

        tag: Tag,
        attributes: []const Attribute = &.{},
        children: []const Element = &.{},

        const Self = @This();

        pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
            allocator.free(self.attributes);
            for (self.children) |c| c.deinit(allocator);
            allocator.free(self.children);
        }

        pub fn getAttribute(self: Self, name: []const u8) ?[]const u8 {
            for (self.attributes) |a| {
                if (std.mem.eql(u8, a.key, name)) return a.value;
            }
            return null;
        }
    };

    pub fn deinit(self: Element, allocator: std.mem.Allocator) void {
        switch (self) {
            .node => |n| n.deinit(allocator),
            .text => {},
        }
    }
};

pub const HtmlFormatter = struct {
    // These fields are for generating ids for footnotes.
    book: []const u8 = "",
    chapter: usize = 0,
    id: usize = 0,

    pub fn fmt(self: *HtmlFormatter, w: anytype, ele: Element) (@TypeOf(w).Error || Error)!void {
        return switch (ele) {
            .node => |n| try self.fmtNode(w, n),
            .text => |t| try self.fmtText(w, t),
        };
    }

    fn fmtText(self: *HtmlFormatter, w: anytype, text: []const u8) !void {
        _ = self;
        var last_space = false;
        for (text) |c| {
            const is_whitespace = std.mem.indexOfScalar(u8, whitespace, c) != null;
            defer last_space = is_whitespace;
            if (is_whitespace and last_space) continue;

            if (is_whitespace) {
                try w.writeByte(' ');
            } else switch (c) {
                '&' => try w.writeAll("&amp;"),
                '<' => try w.writeAll("&lt;"),
                '>' => try w.writeAll("&gt;"),
                else => |c2| try w.writeByte(c2),
            }
        }
    }

    const Error = error{
        InvalidHeadingLevel,
        InvalidQLevel,
    };

    fn fmtNode(self: *HtmlFormatter, w: anytype, node: Element.Node) !void {
        var class: ?[]const u8 = null;
        var tag: ?[]const u8 = null;
        switch (node.tag) {
            .p => tag = "p",
            .v => tag = "sup",
            .w, .root => {},
            .f, .fe => {
                if (node.children.len < 2) return;

                try w.print("<sup class=\"{s}\"><button popovertarget=\"{s}{d}_{d}\">", .{ @tagName(node.tag), self.book, self.chapter, self.id });
                try self.fmt(w, node.children[0]);
                try w.print("</button></sup><div popover id=\"{s}{d}_{d}\">", .{ self.book, self.chapter, self.id });

                for (node.children[1..]) |c| try self.fmt(w, c);

                try w.writeAll("</div>");

                self.id += 1;
                return;
            },
            .c => return,
            inline .mt, .mte, .imt, .imte, .s, .ms => |lvl, t| {
                switch (lvl) {
                    0, 1 => tag = "h1",
                    2 => tag = "h2",
                    3 => tag = "h3",
                    4 => tag = "h4",
                    5 => tag = "h5",
                    6 => tag = "h6",
                    else => return error.InvalidHeadingLevel,
                }
                if (t != .s) class = @tagName(t);
            },
            .q => |lvl| {
                tag = "p";
                class = switch (lvl) {
                    0, 1 => "q1",
                    2 => "q2",
                    3 => "q3",
                    4 => "q4",
                    5 => "q5",
                    6 => "q6",
                    else => return error.InvalidQLevel,
                };
            },
            .sr, .mr, .r, .rq, .d, .sp, .sd => return,
            .em => tag = "em",
            .bd => tag = "b",
            .it => tag = "i",
            .sup => {
                tag = "sup";
                class = "sup";
            },
            .b => {
                try w.writeAll("<br>");
                return;
            },
            else => |t| {
                class = @tagName(t);
                if (t.isIdentification()) {
                    return;
                } else if (t.isParagraph()) {
                    tag = "p";
                } else if (t.isInline() or node.tag.isCharacter()) {
                    tag = "span";
                } else if (t.isMilestoneStart() and node.getAttribute("x-strong") != null) {
                    tag = "span";
                    class = null;
                }
            },
        }

        if (tag) |t| {
            if (std.mem.eql(u8, t, "p") and node.children.len == 0) return;

            try w.print("<{s}", .{t});
            if (class) |c| try w.print(" class=\"{s}\"", .{c});

            if (node.getAttribute("x-strong")) |v| try w.print(" data-strongs=\"{s}\"", .{v});
            try w.writeAll(">");
        }

        for (node.children) |c| try self.fmt(w, c);

        if (tag) |t| {
            try w.print("</{s}>", .{t});
            if (node.tag.isParagraph()) try w.writeByte('\n');
        }
    }
};
