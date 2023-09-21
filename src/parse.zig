const std = @import("std");
const lex = @import("lex.zig");

pub const Error = error{
    NoName, // no Format directive was found
    MultipleNames, // multiple Format directives were found
    ExpectedNameString, // expected string for Format directive
    NoNamespace, // no Namespace directive was found
    MultipleNamespaces, // multiple Namespace directives were found
    ExpectedNamespaceString, // expected string for Namespace directive
    ExpectedFieldOrDirective, // expected a field or a directive
    ExpectedTypename, // expected a type name
    ExpectedSignedOrUnsigned, // expected either 'signed' or 'unsigned'
    ExpectedConstraintValue, // expected a value after constraint operator
    FieldConstraintNotInteger, // expected an integer value for field constraint
    ArrayComparativeConstraint, // only '=' and '!=' constraints are allowed for array fields
    ConstrainedArrayNotString, // only byte arrays may be constrained
};

pub const Datatype = enum {
    Byte,
    Short,
    Int,
    Long,
};

pub const QualType = struct {
    datatype: Datatype,
    isSigned: bool = false,
    isArray: bool = false,
    arraySizeInferred: bool = false,
    arraySizeKnown: bool = false,
    arrayExtent: union {
        typ: Datatype,
        size: usize,
    } = .{ .size = 0 },
};

pub const Constraint = struct { op: lex.Operator, val: union {
    str: []const u8,
    int: isize,
} };

pub const Field = struct {
    name: []const u8,
    typ: QualType,
    constraint: ?Constraint = null,
};

pub const Format = struct {
    name: []const u8,
    namespace: []const u8,

    fields: []Field,

    allocator: std.mem.Allocator,

    pub fn deinit(self: *const Format) void {
        self.allocator.free(self.fields);
    }
};

const State = struct {
    tokens: []lex.Token,
    offset: usize = 0,

    name: ?[]const u8 = null,
    namespace: ?[]const u8 = null,

    fn new(tokens: []lex.Token) State {
        return .{ .tokens = tokens };
    }

    const Self = *@This();

    fn next(self: Self) !?Field {
        const token = self.gettok();
        if (token == null) {
            return null;
        }

        switch (token.?.data) {
            .Directive => |d| {
                try self.parseDirective(d);
                return null;
            },
            .String => |s| return self.parseField(s),
            else => return Error.ExpectedFieldOrDirective,
        }
    }

    fn parseField(self: Self, name: []const u8) !?Field {
        var qualtype = try self.parseQualType();

        const maybeOp = self.gettok();
        if (maybeOp == null) {
            return .{ .name = name, .typ = qualtype };
        }
        const constraint = switch (maybeOp.?.data) {
            .Operator => |o| try self.parseConstraint(&qualtype, o),
            else => {
                self.offset -= 1;
                return .{ .name = name, .typ = qualtype };
            },
        };

        return .{ .name = name, .typ = qualtype, .constraint = constraint };
    }

    fn parseQualType(self: Self) !QualType {
        const signedOverride = try self.parseSignednessModifier();

        var primTok = self.gettok();
        if (primTok == null) {
            return Error.ExpectedTypename;
        }

        var qt = QualType{
            .datatype = undefined,
        };
        switch (primTok.?.data) {
            .Typename => |t| switch (t) {
                .Byte => {
                    qt.datatype = .Byte;
                    qt.isSigned = signedOverride orelse false;
                },
                .Bytes => {
                    qt.datatype = .Byte;
                    qt.isSigned = signedOverride orelse false;
                    qt.isArray = true;
                    qt.arraySizeInferred = true;
                },
                .Char => {
                    qt.datatype = .Byte;
                    qt.isSigned = signedOverride orelse false;
                },
                .Word => {
                    qt.datatype = .Short;
                    qt.isSigned = signedOverride orelse false;
                },
                .Short => {
                    qt.datatype = .Short;
                    qt.isSigned = signedOverride orelse true;
                },
                .Dword => {
                    qt.datatype = .Int;
                    qt.isSigned = signedOverride orelse false;
                },
                .Int => {
                    qt.datatype = .Int;
                    qt.isSigned = signedOverride orelse true;
                },
                .Qword => {
                    qt.datatype = .Long;
                    qt.isSigned = signedOverride orelse false;
                },
                .Long => {
                    qt.datatype = .Long;
                    qt.isSigned = signedOverride orelse true;
                },
            },
            else => return Error.ExpectedTypename,
        }

        return qt;
    }

    fn parseSignednessModifier(self: Self) !?bool {
        const tok = self.gettok();
        if (tok == null) {
            return Error.ExpectedSignedOrUnsigned;
        }

        switch (tok.?.data) {
            .Modifier => |m| return switch (m) {
                .Signed => true,
                .Unsigned => false,
                else => return Error.ExpectedSignedOrUnsigned,
            },
            else => {
                self.offset -= 1;
                return null;
            },
        }
    }

    fn parseConstraint(self: Self, qualtype: *QualType, op: lex.Operator) !Constraint {
        const value = self.gettok();
        if (value == null) {
            return Error.ExpectedConstraintValue;
        }

        if (qualtype.isArray) {
            if (op != lex.Operator.Equal and op != lex.Operator.NotEqual) {
                return Error.ArrayComparativeConstraint;
            }
            if (qualtype.datatype != Datatype.Byte) {
                return Error.ConstrainedArrayNotString;
            }

            const str = switch (value.?.data) {
                .String => |s| s,
                else => return Error.ConstrainedArrayNotString,
            };

            if (qualtype.arraySizeInferred and op == lex.Operator.Equal) {
                qualtype.arraySizeKnown = true;
                qualtype.arrayExtent.size = str.len;
            }

            return .{ .op = op, .val = .{ .str = str } };
        }

        return switch (value.?.data) {
            .Integer => |i| .{ .op = op, .val = .{ .int = i } },
            else => Error.FieldConstraintNotInteger,
        };
    }

    fn parseDirective(self: Self, directive: lex.Directive) !void {
        switch (directive) {
            .Format => {
                if (self.name != null) {
                    return Error.MultipleNames;
                }

                const nameTok = self.gettok();
                if (nameTok == null) {
                    return Error.ExpectedNameString;
                }
                switch (nameTok.?.data) {
                    .String => |s| self.name = s,
                    else => return Error.ExpectedNameString,
                }
            },
            .Namespace => {
                if (self.namespace != null) {
                    return Error.MultipleNamespaces;
                }

                const namespaceTok = self.gettok();
                if (namespaceTok == null) {
                    return Error.ExpectedNamespaceString;
                }
                switch (namespaceTok.?.data) {
                    .String => |s| self.namespace = s,
                    else => return Error.ExpectedNamespaceString,
                }
            },
        }
    }

    fn has(self: Self) bool {
        return self.offset < self.tokens.len;
    }

    fn gettok(self: Self) ?lex.Token {
        if (self.offset >= self.tokens.len) {
            return null;
        }

        const token = self.tokens[self.offset];
        self.offset += 1;
        return token;
    }
};

pub fn all(allocator: std.mem.Allocator, filename: []const u8, source: []const u8) !Format {
    const tokens = try lex.all(allocator, filename, source);
    defer allocator.free(tokens);
    var state = State.new(tokens);
    var fields = std.ArrayList(Field).init(allocator);

    while (state.has()) {
        const field = try state.next();
        if (field == null) {
            continue;
        }
        try fields.append(field.?);
    }

    if (state.name == null) {
        return Error.NoName;
    }

    if (state.namespace == null) {
        return Error.NoNamespace;
    }

    return .{
        .name = state.name.?,
        .namespace = state.namespace.?,
        .fields = fields.items,
        .allocator = allocator,
    };
}

test "basic" {
    const format = try all(std.testing.allocator, "test", "Format \"test\" Namespace \"testfile\"");
    defer format.deinit();

    try std.testing.expectEqualStrings("test", format.name);
    try std.testing.expectEqualStrings("testfile", format.namespace);

    try std.testing.expectEqual(@as(usize, 0), format.fields.len);
}

test "magic" {
    const format = try all(std.testing.allocator, "test", @embedFile("tests/parse/magic.ff"));
    defer format.deinit();

    try std.testing.expectEqualStrings("test", format.name);
    try std.testing.expectEqualStrings("testfile", format.namespace);

    try std.testing.expectEqual(@as(usize, 1), format.fields.len);

    const magic = format.fields[0];
    try std.testing.expectEqualStrings("Magic", magic.name);
    try std.testing.expectEqual(Datatype.Byte, magic.typ.datatype);
    try std.testing.expect(magic.typ.isArray);
    try std.testing.expect(magic.typ.arraySizeKnown);
    try std.testing.expectEqual(@as(usize, 4), magic.typ.arrayExtent.size);
    try std.testing.expect(magic.constraint != null);
    try std.testing.expectEqual(lex.Operator.Equal, magic.constraint.?.op);
    try std.testing.expectEqualStrings("TEST", magic.constraint.?.val.str);
}

test "version" {
    const format = try all(std.testing.allocator, "test", @embedFile("tests/parse/version.ff"));
    defer format.deinit();

    try std.testing.expectEqualStrings("test v2", format.name);
    try std.testing.expectEqualStrings("test_v2", format.namespace);

    try std.testing.expectEqual(@as(usize, 2), format.fields.len);

    const magic = format.fields[0];
    try std.testing.expectEqualStrings("Magic", magic.name);
    try std.testing.expectEqual(Datatype.Byte, magic.typ.datatype);
    try std.testing.expect(magic.typ.isArray);
    try std.testing.expect(magic.typ.arraySizeKnown);
    try std.testing.expectEqual(@as(usize, 7), magic.typ.arrayExtent.size);
    try std.testing.expect(magic.constraint != null);
    try std.testing.expectEqual(lex.Operator.Equal, magic.constraint.?.op);
    try std.testing.expectEqualStrings("TESTFIL", magic.constraint.?.val.str);

    const version = format.fields[1];
    try std.testing.expectEqualStrings("Version", version.name);
    try std.testing.expectEqual(Datatype.Byte, version.typ.datatype);
    try std.testing.expect(!version.typ.isArray);
    try std.testing.expect(version.constraint != null);
    try std.testing.expectEqual(lex.Operator.Equal, version.constraint.?.op);
    try std.testing.expectEqual(@as(isize, 2), version.constraint.?.val.int);
}

test "ints" {
    const format = try all(std.testing.allocator, "test", @embedFile("tests/parse/ints.ff"));
    defer format.deinit();

    try std.testing.expectEqualStrings("test v3", format.name);
    try std.testing.expectEqualStrings("test_v3", format.namespace);

    try std.testing.expectEqual(@as(usize, 6), format.fields.len);

    const magic = format.fields[0];
    try std.testing.expectEqualStrings("Magic", magic.name);
    try std.testing.expectEqual(Datatype.Byte, magic.typ.datatype);
    try std.testing.expect(magic.typ.isArray);
    try std.testing.expect(magic.typ.arraySizeKnown);
    try std.testing.expectEqual(@as(usize, 7), magic.typ.arrayExtent.size);
    try std.testing.expect(magic.constraint != null);
    try std.testing.expectEqual(lex.Operator.Equal, magic.constraint.?.op);
    try std.testing.expectEqualStrings("TESTFIL", magic.constraint.?.val.str);

    const version = format.fields[1];
    try std.testing.expectEqualStrings("Version", version.name);
    try std.testing.expectEqual(Datatype.Byte, version.typ.datatype);
    try std.testing.expect(!version.typ.isArray);
    try std.testing.expect(version.constraint != null);
    try std.testing.expectEqual(lex.Operator.Equal, version.constraint.?.op);
    try std.testing.expectEqual(@as(isize, 3), version.constraint.?.val.int);

    const a = format.fields[2];
    try std.testing.expectEqualStrings("A", a.name);
    try std.testing.expect(!a.typ.isArray);
    try std.testing.expect(a.constraint == null);
    try std.testing.expectEqual(a.typ.datatype, .Byte);
    try std.testing.expect(a.typ.isSigned);

    const b = format.fields[3];
    try std.testing.expectEqualStrings("B", b.name);
    try std.testing.expect(!b.typ.isArray);
    try std.testing.expect(b.constraint == null);
    try std.testing.expectEqual(b.typ.datatype, .Short);
    try std.testing.expect(!b.typ.isSigned);

    const c = format.fields[4];
    try std.testing.expectEqualStrings("C", c.name);
    try std.testing.expect(!c.typ.isArray);
    try std.testing.expect(c.constraint == null);
    try std.testing.expectEqual(c.typ.datatype, .Int);
    try std.testing.expect(c.typ.isSigned);

    const d = format.fields[5];
    try std.testing.expectEqualStrings("D", d.name);
    try std.testing.expect(!d.typ.isArray);
    try std.testing.expect(d.constraint == null);
    try std.testing.expectEqual(d.typ.datatype, .Long);
    try std.testing.expect(!d.typ.isSigned);
}
