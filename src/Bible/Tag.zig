pub const Tag = enum(u8) {
    word,
    morpheme,
    variant,
    option,
    punctuation,
    end,

    pub fn fromType(comptime T: type) @This() {
        if (T == mod.Word) return .word;
        if (T == mod.Morpheme) return .morpheme;
        // if (T == mod.Variant) return .variant;
        // if (T == mod.Option) return .option;

        unreachable;
    }
};

const mod = @import("./mod.zig");
