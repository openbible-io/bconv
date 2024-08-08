underlying: std.io.AnyReader,
string_buf: [std.math.maxInt(StringLen)]u8 = undefined,
next_tag: ?Tag = null,

pub fn readInt(self: *@This(), comptime T: type) !T {
    return self.underlying.readInt(T, .little);
}

pub fn readEnum(self: *@This(), comptime T: type) !T {
    return self.underlying.readEnum(T, .little);
}

pub fn readString(self: *@This()) ![]u8 {
    const len = try self.readInt(StringLen);
    const actual = try self.underlying.readAll(self.string_buf[0..len]);
    if (actual != len) return error.UnderRead;
    return self.string_buf[0..len];
}

/// Reads packed struct
pub fn readStruct(self: *@This(), comptime T: type) !T {
    const IntType = @typeInfo(T).Struct.backing_integer.?;
    const int = try self.readInt(IntType);
    return @bitCast(int);
}

pub fn readTag(self: *@This()) !?Tag {
    if (self.next_tag) |n| {
        self.next_tag = null;
        return n;
    }
    return self.readEnum(Tag) catch |e| switch (e) {
        error.EndOfStream => return null,
        else => return e,
    };
}

pub fn next(self: *@This()) !?Element {
    return if (try self.readTag()) |tag|  switch (tag) {
        .word => {
            const ref = try self.readStruct(Word.Reference);
            return .{ .word = WordIter{ .ref = ref, .reader = self } };
        },
        .morpheme,
        .variant,
        .option,
        .punctuation,
        .end, => unreachable
    } else null;
}

pub const Element = union(enum) {
    word: WordIter,
};

pub const WordIter = struct {
    ref: Word.Reference,
    reader: *Reader,

    pub fn next(self: *@This()) !?Morpheme {
        if (try self.reader.readTag()) |t| switch (t) {
            .morpheme => {},
            else => {
                self.reader.next_tag = t;
                return null;
            },
        } else return null;

        var res: Morpheme = undefined;
        res.type  = try self.reader.readEnum(Morpheme.Type);
        res.strong =  try self.reader.readStruct(Morpheme.Strong);
        res.text = try self.reader.readString();
        return res;
    }
};

const std = @import("std");
const mod = @import("../mod.zig");
const Word = mod.Word;
const Tag = mod.Tag;
const  Morpheme = mod.Morpheme;
const Reader = @This();
const StringLen = u8;
