/// https://docs.google.com/document/d/1wQ67vPIrNxvICy5QmSeromQUJmePml1nQxv7n1gJ8qw
const std = @import("std");

pub const Hebrew = Semitic(enum(u5) {
    qal,
    niphal,
    piel,
    pual,
    hiphil,
    hophal,
    hithpael,
    polel,
    polal,
    hithpolel,
    poel,
    poal,
    palel,
    pulal,
    qal_passive,
    pilpel,
    polpal,
    hithpalpel,
    nithpael,
    pealal,
    pilel,
    hothpaal,
    tiphil,
    hishtaphel,
    nithpalel,
    nithpoel,
    hithpoel,

    const mappings = comptimeMappings(@This(), .{
        .{ "q", .qal },
        .{ "N", .niphal },
        .{ "p", .piel },
        .{ "P", .pual },
        .{ "h", .hiphil },
        .{ "H", .hophal },
        .{ "t", .hithpael },
        .{ "o", .polel },
        .{ "O", .polal },
        .{ "r", .hithpolel },
        .{ "m", .poel },
        .{ "M", .poal },
        .{ "k", .palel },
        .{ "K", .pulal },
        .{ "Q", .qal_passive },
        .{ "l", .pilpel },
        .{ "L", .polpal },
        .{ "f", .hithpalpel },
        .{ "D", .nithpael },
        .{ "j", .pealal },
        .{ "i", .pilel },
        .{ "u", .hothpaal },
        .{ "c", .tiphil },
        .{ "v", .hishtaphel },
        .{ "w", .nithpalel },
        .{ "y", .nithpoel },
        .{ "z", .hithpoel },
    });
});

pub const Aramaic = Semitic(enum(u5) {
    peal,
    peil,
    hithpeel,
    pael,
    ithpaal,
    hithpaal,
    aphel,
    haphel,
    saphel,
    shaphel,
    hophal,
    ithpeel,
    hishtaphel,
    ishtaphel,
    hithaphel,
    polel,
    ithpoel,
    hithpolel,
    hithpalpel,
    hephal,
    tiphel,
    poel,
    palpel,
    ithpalpel,
    ithpolel,
    ittaphal,

    const mappings = comptimeMappings(@This(), .{
        .{ "q", .peal },
        .{ "Q", .peil },
        .{ "u", .hithpeel },
        .{ "p", .pael },
        .{ "P", .ithpaal },
        .{ "M", .hithpaal },
        .{ "a", .aphel },
        .{ "h", .haphel },
        .{ "s", .saphel },
        .{ "e", .shaphel },
        .{ "H", .hophal },
        .{ "i", .ithpeel },
        .{ "t", .hishtaphel },
        .{ "v", .ishtaphel },
        .{ "w", .hithaphel },
        .{ "o", .polel },
        .{ "z", .ithpoel },
        .{ "r", .hithpolel },
        .{ "f", .hithpalpel },
        .{ "b", .hephal },
        .{ "c", .tiphel },
        .{ "m", .poel },
        .{ "l", .palpel },
        .{ "L", .ithpalpel },
        .{ "O", .ithpolel },
        .{ "G", .ittaphal },
    });
});

pub const VerbGender = enum(u2) {
    not_applicable,
    male,
    female,
    common,

    const mappings = comptimeMappings(@This(), .{
        .{ "m",  .male },
        .{ "f",  .female },
        .{ "c",  .common },
    });
};

pub const Number = enum(u2) {
    not_applicable,
    dual,
    plural,
    singular,

    pub const mappings = comptimeMappings(@This(), .{
        .{ "d", .dual },
        .{ "p", .plural },
        .{ "s", .singular },
    });
};

pub const State = enum(u2) {
    not_applicable,
    absolute,
    construct,
    determined,

    pub const mappings = comptimeMappings(@This(), .{
        .{ "a", .absolute },
        .{ "c", .construct },
        .{ "d", .determined },
    });
};

pub const Person = enum(u2) {
    not_applicable,
    first,
    second,
    third,

    pub const mappings = comptimeMappings(@This(), .{
        .{ "1", .first },
        .{ "2", .second },
        .{ "3", .third },
    });
};

pub fn Semitic(comptime VerbStemType: type) type {
    return packed struct {
        tag: Tag = .unknown,
        value: Value = .{ .adverb = {} },

        pub const Tag = enum(u8) {
            unknown,
            adverb,
            conjunction,
            preposition,
            particle,
            adjective,
            noun,
            noun_proper,
            pronoun,
            suffix,
            verb_participle,
            verb_infinitive,
            verb_other,
        };
        pub const Value = packed union {
            adverb: void,
            conjunction: Conjunction,
            preposition: Preposition,
            particle: Particle,
            adjective: Adjective,
            noun: Noun,
            noun_proper: ProperNoun,
            pronoun: Pronoun,
            suffix: Suffix,
            verb_participle: VerbParticiple,
            verb_infinitive: VerbInfinitive,
            verb_other: VerbOther,
        };

        fn init(comptime tag: Tag, value: anytype) @This() {
            return .{ .tag = tag, .value = @unionInit(Value, @tagName(tag), value) };
        }

        pub fn parse(buf: []const u8) !@This() {
            var r = ByteReader{ .buffer = buf };
            return switch (r.next() orelse return error.SmallSemiticCode) {
                'A' => init(.adjective, try Adjective.parse(&r)),
                'C' => init(.conjunction, Conjunction{ .is_sequential = false }),
                'c' => init(.conjunction, Conjunction{ .is_sequential = true }),
                'D' => init(.adverb, {}),
                'N' => {
                    return switch (r.next() orelse return error.NounMissingForm) {
                        'p' => init(.noun_proper, try ProperNoun.parse(&r)),
                        else => {
                            r.pos -= 1;
                            return init(.noun, try Noun.parse(&r));
                        },
                    };
                },
                'P' => init(.pronoun, try Pronoun.parse(&r)),
                'R' => init(.preposition, try Preposition.parse(&r)),
                'S' => init(.suffix, try Suffix.parse(&r)),
                'T' => init(.particle, try Particle.parse(&r)),
                'V' => {
                    _ = r.next(); // stem
                   switch (r.next() orelse return error.MissingVerbForm) {
                       'r', 's' => {
                           r.pos -= 2;
                           return init(.verb_participle, try VerbParticiple.parse(&r));
                       },
                       'a', 'c' => {
                           r.pos -= 2;
                           return init(.verb_infinitive, try VerbInfinitive.parse(&r));
                       },
                       else => {
                           r.pos -= 2;
                           return init(.verb_other, try VerbOther.parse(&r));
                       }
                    }
                },
                else => return error.SemiticCode,
            };
        }

        pub fn write(self: @This(), writer: anytype) !void {
            switch (self.tag) {
                .unknown => {
                    try writer.writeByte('U');
                },
                .adjective => {
                    try writer.writeByte('A');
                    try self.value.adjective.write(writer);
                },
                .conjunction => try writer.writeByte(if (self.value.conjunction.is_sequential) 'c' else 'C'),
                .adverb => try writer.writeByte('D'),
                .noun => {
                    try writer.writeByte('N');
                    try self.value.noun.write(writer);
                },
                .noun_proper => {
                    try writer.writeAll("Np");
                    try self.value.noun_proper.write(writer);
                },
                .pronoun => {
                    try writer.writeByte('P');
                    try self.value.pronoun.write(writer);
                },
                .preposition => try writer.writeByte('R'),
                .suffix => {
                    try writer.writeByte('S');
                    try self.value.suffix.write(writer);
                },
                .particle => {
                    try writer.writeByte('P');
                    try Particle.mappings.write(self.value.particle, writer);
                },
                inline .verb_participle, .verb_infinitive, .verb_other => |t| {
                    try writer.writeByte('V');
                    const v = @field(self.value, @tagName(t));
                    try v.write(writer);
                },
            }
        }

        pub const VerbParticiple = packed struct {
            stem: VerbStemType,
            form: Form,
            gender: VerbGender = .not_applicable,
            number: Number = .not_applicable,
            state: State = .not_applicable,

            pub const Form = enum(u1) {
                active,
                passive,

                pub const mappings = comptimeMappings(@This(), .{
                    .{ "r", .active },
                    .{ "s", .passive },
                });
            };

            pub fn parse(r: *ByteReader) !@This() {
                var res = @This(){ .stem = undefined, .form = undefined };

                res.stem = try VerbStemType.mappings.parse(r.next() orelse return error.VerbMissingStem);
                res.form = try Form.mappings.parse(r.next() orelse return error.VerbMissingForm);
                res.gender = VerbGender.mappings.maybeParse(r, .not_applicable);
                res.number = Number.mappings.maybeParse(r, .not_applicable);
                res.state = State.mappings.maybeParse(r, .not_applicable);

                return res;
            }

            pub fn write(self: @This(), writer: anytype) !void {
                try VerbStemType.mappings.write(self.stem, writer);
                try Form.mappings.write(self.form, writer);
                try VerbGender.mappings.write(self.gender, writer);
                try Number.mappings.write(self.number, writer);
                try State.mappings.write(self.state, writer);
            }
        };

        pub const VerbInfinitive = packed struct {
            stem: VerbStemType,
            form: Form,
            state: State = .not_applicable,

            pub const Form = enum(u1) {
                absolute,
                construct,

                pub const mappings = comptimeMappings(@This(), .{
                    .{ "a", .absolute },
                    .{ "c", .construct },
                });
            };

            pub fn parse(r: *ByteReader) !@This() {
                var res = @This(){ .stem = undefined, .form = undefined };

                res.stem = try VerbStemType.mappings.parse(r.next() orelse return error.VerbMissingStem);
                res.form = try Form.mappings.parse(r.next() orelse return error.VerbMissingForm);
                res.state = State.mappings.maybeParse(r, .not_applicable);

                return res;
            }

            pub fn write(self: @This(), writer: anytype) !void {
                try VerbStemType.mappings.write(self.stem, writer);
                try Form.mappings.write(self.form, writer);
                try State.mappings.write(self.state, writer);
            }
        };

        pub const VerbOther = packed struct {
            stem: VerbStemType,
            form: Form,
            person: Person = .not_applicable,
            gender: VerbGender = .not_applicable,
            number: Number = .not_applicable,

            pub const Form = enum(u3) {
                imperfect,
                sequential_imperfect,
                conjunctive_imperfect,
                jussive,
                cohortive,
                perfect,
                sequential_perfect,
                imperative,

                pub const mappings = comptimeMappings(@This(), .{
                    .{ "i", .imperfect },
                    .{ "w", .sequential_imperfect },
                    .{ "u", .conjunctive_imperfect },
                    .{ "j", .jussive },
                    .{ "c", .cohortive },
                    .{ "p", .perfect },
                    .{ "q", .sequential_perfect },
                    .{ "v", .imperative },
                });
            };

            pub fn parse(r: *ByteReader) !@This() {
                var res = @This(){ .stem = undefined, .form = undefined };

                res.stem = try VerbStemType.mappings.parse(r.next() orelse return error.VerbMissingStem);
                res.form = try Form.mappings.parse(r.next() orelse return error.VerbMissingForm);
                res.person = Person.mappings.maybeParse(r, .not_applicable);
                res.gender = VerbGender.mappings.maybeParse(r, .not_applicable);
                res.number = Number.mappings.maybeParse(r, .not_applicable);

                return res;
            }

            pub fn write(self: @This(), writer: anytype) !void {
                try VerbStemType.mappings.write(self.stem, writer);
                try Form.mappings.write(self.form, writer);
                try Person.mappings.write(self.person, writer);
                try VerbGender.mappings.write(self.gender, writer);
                try Number.mappings.write(self.number, writer);
            }
        };
    };
}

pub const VerbAction = enum(u4) {
    /// qatal
    /// weqatal
    /// yiqtol
    imperfect,
    /// wayyiqtol
    cohortative,
    participle_active,
    participle_passive,
    infinitive_absolute,

    pub const mappings = comptimeMappings(@This(), .{
        .{ "h", .cohortative },
        .{ "r", .participle_active },
        .{ "s", .participle_passive },
        .{ "a", .infinitive_absolute },
    });
};

pub const Adjective = packed struct {
    type: Type,
    gender: Noun.Gender,
    number: Number,
    state: State,

    pub fn parse(b: *ByteReader) !@This() {
        var res: @This() = undefined;
        res.type = try Type.mappings.parse(b.next() orelse return error.MissingAdjectiveType);
        res.gender = try Noun.Gender.mappings.parse(b.next() orelse return error.MissingAdjectiveGender);
        res.number = try Number.mappings.parse(b.next() orelse return error.MissingAdjectiveNumber);
        res.state = try State.mappings.parse(b.next() orelse return error.MissingAdjectiveState);
        return res;
    }

    pub fn write(self: @This(), writer: anytype) !void {
        try Type.mappings.write(self.type, writer);
        try Noun.Gender.mappings.write(self.gender, writer);
        try Number.mappings.write(self.number, writer);
        try State.mappings.write(self.state, writer);
    }

    pub const Type = enum(u2) {
        adjective,
        cardinal_number,
        gentilic,
        ordinal_number,

        pub const mappings = comptimeMappings(@This(), .{
            .{ "a", .adjective },
            .{ "c", .cardinal_number },
            .{ "g", .gentilic },
            .{ "o", .ordinal_number },
        });
    };
};

pub const Noun = packed struct {
    type: Type,
    gender: Gender,
    number: Number = .not_applicable,
    state: State = .not_applicable,

    pub const Type = enum(u2) {
        common,
        gentilic,
        title,

        pub const mappings = comptimeMappings(@This(), .{
            .{ "c", .common },
            .{ "g", .gentilic },
            .{ "t", .title },
        });
    };

    pub const Gender = enum(u2) {
        not_applicable,
        male,
        female,
        both,

        pub const mappings = comptimeMappings(@This(), .{
            .{ "m", .male },
            .{ "f", .female },
            .{ "b", .both },
        });
    };

    pub fn parse(r: *ByteReader) !@This() {
        var res: Noun = .{
            .type = undefined,
            .gender = undefined,
        };
        res.type = try Type.mappings.parse(r.next() orelse return error.NounMissingType);
        res.gender = try Gender.mappings.parse(r.next() orelse return error.NounMissingGender);
        res.number = Number.mappings.parse(r.next() orelse return res) catch .not_applicable;
        res.state = try State.mappings.parse(r.next() orelse return res);

        return res;
    }

    pub fn write(self: @This(), writer: anytype) !void {
        try Type.mappings.write(self.type, writer);
        try Gender.mappings.write(self.gender, writer);
        try Number.mappings.write(self.number, writer);
        try State.mappings.write(self.state, writer);
    }
};

pub const ProperNoun = packed struct {
    gender: Gender,

    pub const Gender = enum(u2) {
        male,
        female,
        location,
        title,

        pub const mappings = comptimeMappings(@This(), .{
            .{ "m", .male },
            .{ "f", .female },
            .{ "l", .location },
            .{ "t", .title },
        });
    };

    pub fn parse(r: *ByteReader) !@This() {
        var res = @This(){ .gender = undefined };
        res.gender = try Gender.mappings.parse(r.next() orelse return error.ProperNounMissingGender);

        return res;
    }

    pub fn write(self: @This(), writer: anytype) !void {
        try Gender.mappings.write(self.gender, writer);
    }
};

pub const Pronoun = packed struct {
    type: Type,
    person: Person = .not_applicable,
    gender: Noun.Gender = .not_applicable,
    number: Number = .not_applicable,

    pub fn parse(r: *ByteReader) !@This() {
        var res = @This(){ .type = undefined };
        res.type = try Type.mappings.parse(r.next() orelse return error.PronounMissingType);
        res.person = Person.mappings.maybeParse(r, .not_applicable);
        res.gender = Noun.Gender.mappings.maybeParse(r, .not_applicable);
        res.number = try Number.mappings.parse(r.next() orelse return res);
        return res;
    }

    pub fn write(self: @This(), writer: anytype) !void {
        try Type.mappings.write(self.type, writer);
        try Person.mappings.write(self.person, writer);
        try Noun.Gender.mappings.write(self.gender, writer);
        try Number.mappings.write(self.number, writer);
    }

    pub const Type = enum(u3) {
        demonstrative,
        indefinite,
        interrogative,
        personal,
        relative,

        const mappings = comptimeMappings(@This(), .{
            .{ "d", .demonstrative },
            .{ "f", .indefinite },
            .{ "i", .interrogative },
            .{ "p", .personal },
            .{ "r", .relative },
        });
    };
};

pub const Suffix = packed struct {
    type: Type,
    person: Person = .not_applicable,
    gender: Noun.Gender = .not_applicable,
    number: Number = .not_applicable,

    pub fn parse(r: *ByteReader) !@This() {
        var res = @This(){ .type = undefined };
        res.type = try Type.mappings.parse(r.next() orelse return error.SuffixMissingType);
        res.person = Person.mappings.maybeParse(r, .not_applicable);
        res.gender = Noun.Gender.mappings.maybeParse(r, .not_applicable);
        res.number = try Number.mappings.parse(r.next() orelse return res);
        return res;
    }

    pub fn write(self: @This(), writer: anytype) !void {
        try Type.mappings.write(self.type, writer);
        try Person.mappings.write(self.person, writer);
        try Noun.Gender.mappings.write(self.gender, writer);
        try Number.mappings.write(self.number, writer);
    }

    pub const Type = enum(u3) {
        directional_he,
        paragogic_he,
        paragogic_nun,
        pronominal,

        pub const mappings = comptimeMappings(@This(), .{
            .{ "d", .directional_he },
            .{ "h", .paragogic_he },
            .{ "n", .paragogic_nun },
            .{ "p", .pronominal },
        });
    };
};

pub const Conjunction = packed struct { is_sequential: bool };

pub const Preposition = packed struct {
    is_definite: bool = false,

    pub fn parse(b: *ByteReader) !@This() {
        var res = @This(){};
        if (b.next()) |c| switch (c) {
            'd' => res.is_definite = true,
            else => return error.InvalidPrepositionSuffix,
        };
        return res;
    }

    pub fn write(self: @This(), writer: anytype) !void {
        if (self.is_definite) try writer.writeByte('d');
    }
};

pub const Particle = enum(u4) {
    affirmation,
    definite_article,
    exhortation,
    interrogative,
    interjection,
    demonstrative,
    negative,
    direct_object_marker,
    relative,
    conditional,

    pub fn parse(r: *ByteReader) !@This() {
        return try mappings.parse(r.next() orelse return error.MissingParticleType);
    }

    pub const mappings = comptimeMappings(@This(), .{
        .{ "a", .affirmation },
        .{ "d", .definite_article },
        .{ "e", .exhortation },
        .{ "i", .interrogative },
        .{ "j", .interjection },
        .{ "m", .demonstrative },
        .{ "n", .negative },
        .{ "o", .direct_object_marker },
        .{ "r", .relative },
        .{ "c", .conditional },
    });
};

const ByteReader = struct {
    buffer: []const u8,
    pos: usize = 0,

    pub fn next(self: *@This()) ?u8 {
        if (self.pos < self.buffer.len) {
            defer self.pos += 1;
            return self.buffer[self.pos];
        }

        return null;
    }
};

fn Mappings(comptime Enum: type) type {
    return struct {
        to_enum: std.StaticStringMap(Enum),
        to_string: std.EnumArray(Enum, []const u8),

        pub fn parse(self: @This(), c: u8) !Enum {
            if (self.to_enum.get(&[_]u8{ c })) |v| return v;
            // std.debug.print("{c} {s}\n", .{ c, @typeName(Enum) });
            return  error.MorphEnumMapping;
        }

        pub fn maybeParse(self: @This(), r: *ByteReader, default: Enum) Enum {
            if (r.next()) |v| {
                return self.parse(v) catch {
                    r.pos -= 1;
                    return default;
                };
            }
            return default;
        }

        pub fn write(self: @This(), e: Enum, writer: anytype) !void {
            try writer.writeAll(self.to_string.get(e));
        }
    };
}

fn comptimeMappings(comptime Enum: type, comptime kvs: anytype) Mappings(Enum) {
    var res = Mappings(Enum){
        .to_enum = std.StaticStringMap(Enum).initComptime(kvs),
        .to_string = std.EnumArray(Enum, []const u8).initUndefined(),
    };
    inline for (kvs) |kv| res.to_string.set(kv[1], kv[0]);
    return res;
}

fn testParse(comptime expected: anytype, buffer: []const u8) !void {
    var reader = ByteReader{ .buffer = buffer };
    const T = @TypeOf(expected);
    const actual = try T.parse(&reader);
    try std.testing.expectEqual(expected, actual);
}

test "Hebrew.Verb" {
    try testParse(Hebrew.VerbOther{
        .stem = .piel,
        .form = .cohortive,
        .gender = .common,
    }, "pcc");

    try testParse(ProperNoun{ .gender = .location }, "l");
    try testParse(Noun{ .type = .common, .gender = .male, .number = .singular, .state = .construct, }, "cmsc");
}
