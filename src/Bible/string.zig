const std = @import("std");
const Offset = @import("./Book.zig").Offset;

pub const String = extern struct {
    meta: packed struct(u8) {
        len: u7,
        is_ptr: bool,
    },
    data_or_offset: [7]u8,

    pub fn slice(self: @This(), buf: []const u8) []const u8 {
        if (self.meta.is_ptr) {
            const offset = std.mem.readInt(Offset, self.data_or_offset, .little);
            return buf[offset..][0..self.len];
        }

        return self.data_or_offset[0..self.len];
    }
};
