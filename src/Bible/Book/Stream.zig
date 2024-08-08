stream: std.io.FixedBufferStream([]u8),

pub fn init(buf: []u8) @This() {
    return .{ .stream = std.io.fixedBufferStream(buf) };
}

pub fn readInt(self: *@This(), comptime T: type) !T {
    return self.stream.reader().readInt(T, .little);
}

pub fn readEnum(self: *@This(), comptime T: type) !T {
    return self.stream.reader().readEnum(T, .little);
}

pub fn readIntPtr(self: *@This(), comptime T: type) !*align(1) T {
    defer self.stream.pos += @sizeOf(T);
    return @ptrCast(self.stream.buffer.ptr + self.stream.pos);
}

pub fn readEnumPtr(self: *@This(), comptime T: type) !*align(1) T {
    defer self.stream.pos += @sizeOf(T);
    return @ptrCast(self.stream.buffer.ptr + self.stream.pos);
}

pub fn readString(self: *@This()) ![]u8 {
    const len = try self.readInt(StringLen);
    defer self.stream.pos += len;
    return self.stream.buffer[self.stream.pos..][0..len];
}

/// Reads packed struct
pub fn readStruct(self: *@This(), comptime T: type) !T {
    const IntType = @typeInfo(T).Struct.backing_integer.?;
    const int = try self.readInt(IntType);
    return @bitCast(int);
}

/// Reads packed struct
pub fn readStructPtr(self: *@This(), comptime T: type) !*align(1) T {
    const IntType = @typeInfo(T).Struct.backing_integer.?;
    defer self.stream.pos += @sizeOf(IntType);
    return @ptrCast(self.stream.buffer.ptr + self.stream.pos);
}

pub fn readTag(self: *@This()) !?Tag {
    return self.readEnum(Tag) catch |e| switch (e) {
        error.EndOfStream => return null,
        else => return e,
    };
}

pub fn next(self: *@This()) !?Element {
    return if (try self.readTag()) |tag|  switch (tag) {
        .word => {
            const ref = try self.readStructPtr(Word.Reference);
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
    ref: *align(1) Word.Reference,
    reader: *Reader,

    pub fn next(self: *@This()) !?MorphemePtr {
        if (try self.reader.readTag()) |t| switch (t) {
            .morpheme => {},
            else => {
                self.reader.stream.pos -= 1;
                return null;
            },
        } else return null;

        var res: MorphemePtr = undefined;
        res.type  = try self.reader.readEnumPtr(Morpheme.Type);
        res.strong =  try self.reader.readStructPtr(Morpheme.Strong);
        res.text = try self.reader.readString();
        return res;
    }

    const MorphemePtr = struct {
        type: *align(1) Morpheme.Type,
        strong: *align(1) Morpheme.Strong,
        // code: Code = 0,
        text: []u8,
    };
};

const std = @import("std");
const mod = @import("../mod.zig");
const Word = mod.Word;
const Tag = mod.Tag;
const  Morpheme = mod.Morpheme;
const Reader = @This();
const StringLen = u8;
