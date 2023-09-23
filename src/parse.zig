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
    ExpectedArraySize, // expected array size
    InvalidArraySize, // array size must be greater than 1
    ArraySizeNotClosed, // expected ')' to close array extent
    ArrayOfArrays, // array of arrays not yet supported
    ExpectedStructName, // expected name of struct
    ExpectedStructFieldList, // expected list of struct fields
    ExpectedStructField, // expected field in struct
};

pub const Datatype = enum {
    Byte,
    Short,
    Int,
    Long,
    Struct,
};

pub const QualType = struct {
    datatype: Datatype,
    isSigned: bool = false,
    isArray: bool = false,
    arraySizeKnown: bool = false,
    arraySize: union {
        ref: []const u8,
        size: usize,
    } = .{ .size = 0 },
    structName: ?[]const u8 = null,
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

pub const Struct = struct {
    name: []const u8,
    fields: []Field,
};

pub const Format = struct {
    name: []const u8,
    namespace: []const u8,

    fields: []Field,
    structs: []Struct,

    allocator: std.mem.Allocator,

    pub fn deinit(self: *const Format) void {
        self.allocator.free(self.fields);
        for (self.structs) |s| {
            self.allocator.free(s.fields);
        }
        self.allocator.free(self.structs);
    }
};

const State = struct {
    tokens: []lex.Token,
    offset: usize = 0,

    name: ?[]const u8 = null,
    namespace: ?[]const u8 = null,

    fields: std.ArrayList(Field),
    structs: std.ArrayList(Struct),

    allocator: std.mem.Allocator,

    fn new(tokens: []lex.Token, allocator: std.mem.Allocator) State {
        return .{
            .tokens = tokens,
            .fields = std.ArrayList(Field).init(allocator),
            .structs = std.ArrayList(Struct).init(allocator),
            .allocator = allocator,
        };
    }

    const Self = *@This();

    fn deinit(self: Self) void {
        self.fields.deinit();
        for (self.structs.items) |s| {
            self.allocator.free(s.fields);
        }
        self.structs.deinit();
    }

    fn next(self: Self) !bool {
        const token = self.gettok();
        if (token == null) {
            return false;
        }

        switch (token.?.data) {
            .Directive => |d| {
                try self.parseDirective(d);
                return true;
            },
            .String => |s| {
                const field = try self.parseField(s);
                try self.fields.append(field);
                return true;
            },
            else => return Error.ExpectedFieldOrDirective,
        }
    }

    fn parseField(self: Self, name: []const u8) !Field {
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
            .String => |s| {
                qt.datatype = .Struct;
                qt.structName = s;
            },
            else => |d| {
                std.debug.print("Invalid typename: {?}\n", .{d});
                return Error.ExpectedTypename;
            },
        }

        try self.parseArrayModifier(&qt);

        return qt;
    }

    fn parseArrayModifier(self: Self, qualtype: *QualType) !void {
        const mod = self.gettok();
        if (mod == null) {
            return;
        }

        switch (mod.?.data) {
            .Modifier => |m| switch (m) {
                .Array => {
                    if (qualtype.isArray) {
                        return Error.ArrayOfArrays;
                    }
                    qualtype.isArray = true;
                },
                else => {
                    self.offset -= 1;
                    return;
                },
            },
            else => {
                self.offset -= 1;
                return;
            },
        }

        const leftParen = self.gettok();
        if (leftParen == null) {
            return Error.ExpectedArraySize;
        }

        const extent = self.gettok();
        if (extent == null) {
            return Error.ExpectedArraySize;
        }

        switch (extent.?.data) {
            .String => |s| {
                qualtype.arraySizeKnown = false;
                qualtype.arraySize = .{ .ref = s };
            },
            .Integer => |i| {
                if (i <= 1) {
                    return Error.InvalidArraySize;
                }
                qualtype.arraySizeKnown = true;
                qualtype.arraySize = .{ .size = @intCast(i) };
            },
            else => |d| {
                std.debug.print("Invalid array size: {?}\n", .{d});
                return Error.InvalidArraySize;
            },
        }

        const rightParen = self.gettok();
        if (rightParen == null) {
            return Error.ArraySizeNotClosed;
        }
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

            if (!qualtype.arraySizeKnown and op == lex.Operator.Equal) {
                qualtype.arraySizeKnown = true;
                qualtype.arraySize.size = str.len;
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
            .Format => try self.parseFormatDirective(),
            .Namespace => try self.parseNamespaceDirective(),
            .Struct => try self.parseStructDirective(),
        }
    }

    fn parseFormatDirective(self: Self) !void {
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
    }

    fn parseNamespaceDirective(self: Self) !void {
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
    }

    fn parseStructDirective(self: Self) !void {
        const nameTok = self.gettok();
        if (nameTok == null) {
            return Error.ExpectedStructName;
        }
        const name = switch (nameTok.?.data) {
            .String => |s| s,
            else => return Error.ExpectedStructName,
        };

        const leftParen = self.gettok();
        if (leftParen == null) {
            return Error.ExpectedStructFieldList;
        }
        switch (leftParen.?.data) {
            .Punctuator => |p| {
                if (p != .LeftParen) {
                    return Error.ExpectedStructFieldList;
                }
            },
            else => return Error.ExpectedStructFieldList,
        }

        var fields = std.ArrayList(Field).init(self.allocator);
        defer fields.deinit();
        while (true) {
            const token = self.gettok();
            if (token == null) {
                return Error.ExpectedStructField;
            }
            const fieldName = switch (token.?.data) {
                .Punctuator => |p| {
                    if (p == .RightParen) {
                        break;
                    }
                    return Error.ExpectedNameString;
                },
                .String => |s| s,
                else => return Error.ExpectedNameString,
            };
            try fields.append(try self.parseField(fieldName));
        }

        try self.structs.append(.{ .name = name, .fields = try fields.toOwnedSlice() });
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
    var state = State.new(tokens, allocator);
    defer state.deinit();

    while (state.has()) {
        _ = try state.next();
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
        .fields = try state.fields.toOwnedSlice(),
        .structs = try state.structs.toOwnedSlice(),
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
    try std.testing.expectEqual(@as(usize, 4), magic.typ.arraySize.size);
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
    try std.testing.expectEqual(@as(usize, 7), magic.typ.arraySize.size);
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
    try std.testing.expectEqual(@as(usize, 7), magic.typ.arraySize.size);
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

test "arrays" {
    const format = try all(std.testing.allocator, "test", @embedFile("tests/parse/arrays.ff"));
    defer format.deinit();

    try std.testing.expectEqualStrings("test v4", format.name);
    try std.testing.expectEqualStrings("test_v4", format.namespace);

    try std.testing.expectEqual(@as(usize, 5), format.fields.len);

    const magic = format.fields[0];
    try std.testing.expectEqualStrings("Magic", magic.name);
    try std.testing.expectEqual(Datatype.Byte, magic.typ.datatype);
    try std.testing.expect(magic.typ.isArray);
    try std.testing.expect(magic.typ.arraySizeKnown);
    try std.testing.expectEqual(@as(usize, 7), magic.typ.arraySize.size);
    try std.testing.expect(magic.constraint != null);
    try std.testing.expectEqual(lex.Operator.Equal, magic.constraint.?.op);
    try std.testing.expectEqualStrings("TESTFIL", magic.constraint.?.val.str);

    const version = format.fields[1];
    try std.testing.expectEqualStrings("Version", version.name);
    try std.testing.expectEqual(Datatype.Byte, version.typ.datatype);
    try std.testing.expect(!version.typ.isArray);
    try std.testing.expect(version.constraint != null);
    try std.testing.expectEqual(lex.Operator.Equal, version.constraint.?.op);
    try std.testing.expectEqual(@as(isize, 4), version.constraint.?.val.int);

    const a = format.fields[2];
    try std.testing.expectEqualStrings("A", a.name);
    try std.testing.expect(!a.typ.isArray);
    try std.testing.expect(a.constraint == null);
    try std.testing.expectEqual(a.typ.datatype, .Byte);
    try std.testing.expect(!a.typ.isSigned);

    const b = format.fields[3];
    try std.testing.expectEqualStrings("B", b.name);
    try std.testing.expect(b.typ.isArray);
    try std.testing.expect(!b.typ.arraySizeKnown);
    try std.testing.expectEqualStrings("A", b.typ.arraySize.ref);
    try std.testing.expect(b.constraint == null);
    try std.testing.expectEqual(b.typ.datatype, .Short);
    try std.testing.expect(b.typ.isSigned);

    const c = format.fields[4];
    try std.testing.expectEqualStrings("C", c.name);
    try std.testing.expect(c.typ.isArray);
    try std.testing.expect(c.typ.arraySizeKnown);
    try std.testing.expectEqual(@as(usize, 10), c.typ.arraySize.size);
    try std.testing.expect(c.constraint == null);
    try std.testing.expectEqual(c.typ.datatype, .Int);
    try std.testing.expect(!c.typ.isSigned);
}

test "struct" {
    const format = try all(std.testing.allocator, "test", @embedFile("tests/parse/struct.ff"));
    defer format.deinit();

    try std.testing.expectEqualStrings("test v6", format.name);
    try std.testing.expectEqualStrings("test_v6", format.namespace);

    try std.testing.expectEqual(@as(usize, 4), format.fields.len);
    try std.testing.expectEqual(@as(usize, 2), format.structs.len);

    const magic = format.fields[0];
    try std.testing.expectEqualStrings("Magic", magic.name);
    try std.testing.expectEqual(Datatype.Byte, magic.typ.datatype);
    try std.testing.expect(magic.typ.isArray);
    try std.testing.expect(magic.typ.arraySizeKnown);
    try std.testing.expectEqual(@as(usize, 7), magic.typ.arraySize.size);
    try std.testing.expect(magic.constraint != null);
    try std.testing.expectEqual(lex.Operator.Equal, magic.constraint.?.op);
    try std.testing.expectEqualStrings("TESTFIL", magic.constraint.?.val.str);

    const version = format.fields[1];
    try std.testing.expectEqualStrings("Version", version.name);
    try std.testing.expectEqual(Datatype.Byte, version.typ.datatype);
    try std.testing.expect(!version.typ.isArray);
    try std.testing.expect(version.constraint != null);
    try std.testing.expectEqual(lex.Operator.Equal, version.constraint.?.op);
    try std.testing.expectEqual(@as(isize, 6), version.constraint.?.val.int);

    const string = format.structs[0];
    try std.testing.expectEqualStrings("String", string.name);
    try std.testing.expectEqual(@as(usize, 2), string.fields.len);

    const reqstring = format.structs[1];
    try std.testing.expectEqualStrings("RequiredString", reqstring.name);
    try std.testing.expectEqual(@as(usize, 2), reqstring.fields.len);

    const name = format.fields[2];
    try std.testing.expectEqualStrings("Name", name.name);
    try std.testing.expectEqual(Datatype.Struct, name.typ.datatype);
    try std.testing.expectEqualStrings("RequiredString", name.typ.structName.?);

    const realname = format.fields[3];
    try std.testing.expectEqualStrings("RealName", realname.name);
    try std.testing.expectEqual(Datatype.Struct, realname.typ.datatype);
    try std.testing.expectEqualStrings("String", realname.typ.structName.?);
}
