const std = @import("std");
const lex = @import("lex.zig");
const diag = @import("diag.zig");

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
    MismatchedArrayConstraintSize,
    ConstrainedDynamicArray,
};

pub const Datatype = enum {
    Byte,
    Short,
    Int,
    Long,
    Struct,
};

pub const QualType = struct {
    pos: lex.SourcePos,
    datatype: Datatype,
    isSigned: bool = false,
    isArray: bool = false,
    arraySizeKnown: bool = false,
    inferArraySize: bool = false,
    arraySize: union {
        ref: []const u8,
        size: usize,
    } = .{ .size = 0 },
    structName: ?[]const u8 = null,
};

pub const Constraint = struct {
    pos: lex.SourcePos,
    op: lex.Operator,
    val: union {
        str: []const u8,
        int: isize,
    },
};

pub const Field = struct {
    pos: lex.SourcePos,
    name: []const u8,
    typ: QualType,
    constraint: ?Constraint = null,
};

pub const Struct = struct {
    pos: lex.SourcePos,
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
                const field = try self.parseField(token.?.pos, s);
                try self.fields.append(field);
                return true;
            },
            else => {
                diag.err("Expected a field or directive, but found {?} instead.", .{token.?.data}, token.?.pos);
                return Error.ExpectedFieldOrDirective;
            },
        }
    }

    fn parseField(self: Self, pos: lex.SourcePos, name: []const u8) !Field {
        var qualtype = try self.parseQualType();

        const maybeOp = self.gettok();
        if (maybeOp == null) {
            return .{ .pos = pos, .name = name, .typ = qualtype };
        }
        const constraint = switch (maybeOp.?.data) {
            .Operator => |o| try self.parseConstraint(&qualtype, maybeOp.?.pos, o),
            else => {
                self.offset -= 1;
                return .{ .pos = pos, .name = name, .typ = qualtype };
            },
        };

        return .{ .pos = pos, .name = name, .typ = qualtype, .constraint = constraint };
    }

    fn parseQualType(self: Self) !QualType {
        const signedOverride = try self.parseSignednessModifier();

        var primTok = self.gettok();
        if (primTok == null) {
            diag.err("Expected a typename.", .{}, self.prevtok().pos);
            return Error.ExpectedTypename;
        }

        var qt = QualType{
            .pos = primTok.?.pos,
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
                    qt.inferArraySize = true;
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
                diag.err("Expected a typename or a struct name, but found {?} instead.", .{d}, primTok.?.pos);
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
                        diag.err("Multidimensional arrays are not supported.", .{}, mod.?.pos);
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
            diag.err("Expected a '(' to define array size.", .{}, mod.?.pos);
            return Error.ExpectedArraySize;
        }

        const extent = self.gettok();
        if (extent == null) {
            diag.errWithTip(
                "Expected a valid array size.",
                .{},
                "You may use an integer to define a static size, or use a string with a field's name to define a dynamic size.",
                .{},
                leftParen.?.pos,
            );
            return Error.ExpectedArraySize;
        }

        switch (extent.?.data) {
            .String => |s| {
                qualtype.arraySizeKnown = false;
                qualtype.arraySize = .{ .ref = s };
            },
            .Integer => |i| {
                if (i <= 1) {
                    diag.errWithTip(
                        "Array size must be at least 2.",
                        .{},
                        "An array of size 0 is invalid and an array of size 1 is pointless.",
                        .{},
                        extent.?.pos,
                    );
                    return Error.InvalidArraySize;
                }
                qualtype.arraySizeKnown = true;
                qualtype.arraySize = .{ .size = @intCast(i) };
            },
            else => |d| {
                diag.errWithTip(
                    "Expected a valid array size, but found {?} instead.",
                    .{d},
                    "You may use an integer to define a static size, or use a string with a field's name to define a dynamic size.",
                    .{},
                    extent.?.pos,
                );
                return Error.InvalidArraySize;
            },
        }

        const rightParen = self.gettok();
        if (rightParen == null) {
            diag.err("Expected a ')' to end array size definition.", .{}, extent.?.pos);
            return Error.ArraySizeNotClosed;
        }
    }

    fn parseSignednessModifier(self: Self) !?bool {
        const tok = self.gettok();
        if (tok == null) {
            diag.err("Expected a typename.", .{}, self.prevtok().pos);
            return Error.ExpectedSignedOrUnsigned;
        }

        switch (tok.?.data) {
            .Modifier => |m| return switch (m) {
                .Signed => true,
                .Unsigned => false,
                else => {
                    diag.errWithTip(
                        "The modifier {?} cannot appear here.",
                        .{m},
                        "Only `unsigned` and `signed` may be used before the typename.",
                        .{},
                        tok.?.pos,
                    );
                    return Error.ExpectedSignedOrUnsigned;
                },
            },
            else => {
                self.offset -= 1;
                return null;
            },
        }
    }

    fn parseConstraint(self: Self, qualtype: *QualType, pos: lex.SourcePos, op: lex.Operator) !Constraint {
        const value = self.gettok();
        if (value == null) {
            diag.errWithTip(
                "Expected a constraint value.",
                .{},
                "You may use an integer or a string for a byte array.",
                .{},
                self.prevtok().pos,
            );
            return Error.ExpectedConstraintValue;
        }

        if (qualtype.isArray) {
            if (op != lex.Operator.Equal) {
                diag.errWithTip(
                    "The constraint '{s}' cannot be used with arrays.",
                    .{op.name()},
                    "Only the '=' constraint may be used on (byte) arrays.",
                    .{},
                    value.?.pos,
                );
                return Error.ArrayComparativeConstraint;
            }
            if (qualtype.datatype != Datatype.Byte) {
                diag.errWithTip(
                    "Constraints cannot be applied to {?} arrays.",
                    .{qualtype.datatype},
                    "Only byte arrays can be constrained (to string values).",
                    .{},
                    value.?.pos,
                );
                return Error.ConstrainedArrayNotString;
            }

            const str = switch (value.?.data) {
                .String => |s| s,
                else => {
                    diag.err("Arrays can only be constrained to a string.", .{}, value.?.pos);
                    return Error.ConstrainedArrayNotString;
                },
            };

            if (qualtype.inferArraySize) {
                qualtype.arraySizeKnown = true;
                qualtype.arraySize.size = str.len;
            } else if (qualtype.arraySizeKnown) {
                if (qualtype.arraySize.size < str.len) {
                    diag.errWithTip(
                        "Array is too small for the constraint. ({d} < {d})",
                        .{ qualtype.arraySize.size, str.len },
                        "Use `bytes`, which infers its size from constraint values. ({d} here)",
                        .{str.len},
                        qualtype.pos,
                    );
                    return Error.MismatchedArrayConstraintSize;
                } else if (qualtype.arraySize.size > str.len) {
                    diag.warnWithTip(
                        "Array is larger than constraint. ({d} > {d})",
                        .{ qualtype.arraySize.size, str.len },
                        "Use `bytes`, which infers its size from constraint values. ({d} here)",
                        .{str.len},
                        qualtype.pos,
                    );
                } else {
                    diag.noteWithTip(
                        "Use `bytes` here.",
                        .{},
                        "`bytes` infers its size from constraint values. ({d} here)",
                        .{str.len},
                        qualtype.pos,
                    );
                }
            } else {
                diag.errWithTip(
                    "Cannot constrain dynamic arrays.",
                    .{},
                    "If you want to infer the array size, use `bytes`.",
                    .{},
                    qualtype.pos,
                );
                return Error.ConstrainedDynamicArray;
            }

            return .{ .pos = pos, .op = op, .val = .{ .str = str } };
        }

        switch (value.?.data) {
            .Integer => |i| return .{ .pos = pos, .op = op, .val = .{ .int = i } },
            else => {
                diag.err("{?} field can only be constrained to an integer.", .{qualtype.datatype}, value.?.pos);
                return Error.FieldConstraintNotInteger;
            },
        }
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
            diag.err("More than one Format directive.", .{}, null);
            return Error.MultipleNames;
        }

        const nameTok = self.gettok();
        if (nameTok == null) {
            diag.err("Expected string for file format name.", .{}, self.prevtok().pos);
            return Error.ExpectedNameString;
        }
        switch (nameTok.?.data) {
            .String => |s| self.name = s,
            else => |d| {
                diag.err("Expected string for file format name, but found {?} instead.", .{d}, nameTok.?.pos);
                return Error.ExpectedNameString;
            },
        }
    }

    fn parseNamespaceDirective(self: Self) !void {
        if (self.namespace != null) {
            diag.errWithTip("More than one Namespace directive.", .{}, "It is necessary to avoid name collisions in the generated code.", .{}, null);
            return Error.MultipleNamespaces;
        }

        const namespaceTok = self.gettok();
        if (namespaceTok == null) {
            diag.err("Expected string for namespace.", .{}, self.prevtok().pos);
            return Error.ExpectedNamespaceString;
        }
        switch (namespaceTok.?.data) {
            .String => |s| self.namespace = s,
            else => |d| {
                diag.err("Expected string for namespace, but got {?} instead.", .{d}, namespaceTok.?.pos);
                return Error.ExpectedNamespaceString;
            },
        }
    }

    fn parseStructDirective(self: Self) !void {
        const nameTok = self.gettok();
        if (nameTok == null) {
            diag.err("Expected string for struct name.", .{}, self.prevtok().pos);
            return Error.ExpectedStructName;
        }
        const name = switch (nameTok.?.data) {
            .String => |s| s,
            else => |d| {
                diag.err("Expected string for struct name, but got {?} instead.", .{d}, nameTok.?.pos);
                return Error.ExpectedStructName;
            },
        };

        const leftParen = self.gettok();
        if (leftParen == null) {
            diag.err("Expected '(' to begin struct field list.", .{}, self.prevtok().pos);
            return Error.ExpectedStructFieldList;
        }
        switch (leftParen.?.data) {
            .Punctuator => |p| {
                if (p != .LeftParen) {
                    diag.err("Expected '(' to begin struct field list, but found {?} insetead.", .{p}, leftParen.?.pos);
                    return Error.ExpectedStructFieldList;
                }
            },
            else => |d| {
                diag.err("Expected '(' to begin struct field list, but found {?} instead.", .{d}, leftParen.?.pos);
                return Error.ExpectedStructFieldList;
            },
        }

        var fields = std.ArrayList(Field).init(self.allocator);
        defer fields.deinit();
        while (true) {
            const token = self.gettok();
            if (token == null) {
                diag.err("Expected a field in structure.", .{}, self.prevtok().pos);
                return Error.ExpectedStructField;
            }
            const fieldName = switch (token.?.data) {
                .Punctuator => |p| {
                    if (p == .RightParen) {
                        break;
                    }
                    diag.err("Expected structure field name, but found {?} instead.", .{p}, token.?.pos);
                    return Error.ExpectedNameString;
                },
                .String => |s| s,
                else => |d| {
                    diag.err("Expected structure field name, but found {?} instead.", .{d}, token.?.pos);
                    return Error.ExpectedNameString;
                },
            };
            try fields.append(try self.parseField(token.?.pos, fieldName));
        }

        try self.structs.append(.{ .pos = nameTok.?.pos, .name = name, .fields = try fields.toOwnedSlice() });
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

    fn prevtok(self: Self) lex.Token {
        return self.tokens[self.offset - 2];
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
        diag.err("File format has no name.", .{}, null);
        return Error.NoName;
    }

    if (state.namespace == null) {
        diag.err("File format has no namespace.", .{}, null);
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
