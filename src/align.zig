const std = @import("std");

pub fn eql(a: anytype, b: @TypeOf(a)) bool {
    return switch (@TypeOf(a)) {
        .Type, .Void, .NoReturn, .Undefined, .Null, .ErrorUnion, .ErrorSet, .Opaque,
        .Frame,
        .AnyFrame,
 => true,
        .Vector, .Fn => unreachable,
        .Pointer => |p| switch (p.size) {
            .One, .Many, .C => return a == b,
            .Slice => {
                if (a.len != b.len) return false;
                if (a.ptr == b.ptr) return true;
                for (a, b) |e1, e2| {
                    if (!eql(e1, e2)) return false;
                }
                return true;
            },
        },
        .Array => |ai| std.mem.eql(ai.child, a, b),
        .Struct => |s| {
            if (s.backing_integer) |T| {
                const av: T  = @intCast(a);
                const bv: T  = @intCast(a);
                return av == bv;
            }
            for (s.fields) |f| {
                if (!eql(@field(a, f.name), @field(b, f.name))) return false;
            }
            return true;
        },
        .Optional => {
            if (a) |av| {
                if (b) |bv| return eql(av, bv);
                return false;
            }
            return b != null;
        },
        .Union => {
            if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
            switch (a) {
                inline else => |av, tag| {
                    return eql(av, @field(b, @tagName(tag)));
                }
            }
        },
        inline .ComptimeFloat, .ComptimeInt, .Bool, .Int, .Float, .Enum, .EnumLiteral => a == b,
    };
}
