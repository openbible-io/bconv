const std = @import("std");
pub const Morpheme = @import("./Morpheme.zig");
pub const Book = @import("./Book.zig");
pub const Builder = @import("./Builder.zig");
pub const SourceSet = @import("./source_set.zig").SourceSet;
pub const Word = @import("./Word.zig");
pub const Tag = @import("./Tag.zig").Tag;

const Allocator = std.mem.Allocator;

test {
    std.testing.refAllDecls(@This());
}
