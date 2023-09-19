const std = @import("std");

pub const Error = error{
    IllegalCharacter, // illegal character
    ExpectedLesserEqual, // expected '<=', found invalid operator instead
    ExpectedGreaterEqual, // expected '>=', found invalid operator instead
    ExpectedNotEqual, // expected '!=', found invalid operator instead
    UnterminatedString, // unterminated string literal
    UnknownDirective, // unknown directive
    UnknownTypename, // unknown typename
};

pub const Punctuator = enum { LeftParen, RightParen };

pub const Operator = enum {
    Equal,
    GreaterEqual,
    LesserEqual,
    NotEqual,
    Greater,
    Lesser,
};

pub const Directive = enum { Format, Namespace };

pub const Typename = enum {
    Byte,
    Bytes,
    Char,
    Word,
    Short,
    Dword,
    Int,
    Qword,
    Long,
};

pub const Modifier = enum {
    Signed,
    Unsigned,
    Array,
};

pub const SourcePos = struct {
    filename: []const u8,
    line: usize = 1,
    col: usize = 0,
};

pub const Token = struct {
    const Kind = enum {
        Punctuator,
        Operator,
        Directive,
        Typename,
        Modifier,
        String,
        Integer,
    };

    const Data = union(Kind) {
        Punctuator: Punctuator,
        Operator: Operator,
        Directive: Directive,
        Typename: Typename,
        Modifier: Modifier,
        String: []const u8,
        Integer: isize,

        fn eql(self: Data, other: Data) bool {
            if (std.meta.activeTag(self) != std.meta.activeTag(other)) {
                return false;
            }

            return switch (self) {
                .Punctuator => |p| p == other.Punctuator,
                .Operator => |o| o == other.Operator,
                .Directive => |d| d == other.Directive,
                .Modifier => |m| m == other.Modifier,
                .Typename => |t| t == other.Typename,
                .String => |s| std.mem.eql(u8, s, other.String),
                .Integer => |i| i == other.Integer,
            };
        }
    };

    pos: SourcePos,
    data: Data,
};

pub fn all(allocator: std.mem.Allocator, filename: []const u8, source: []const u8) ![]Token {
    var state = State.new(filename, source);
    var tokens = std.ArrayList(Token).init(allocator);

    while (true) {
        const maybeToken = try state.next();
        if (maybeToken) |token| {
            try tokens.append(token);
        } else {
            break;
        }
    }

    return tokens.items;
}

const State = struct {
    source: []const u8,
    offset: usize = 0,
    pos: SourcePos,
    prevPos: SourcePos,

    const Self = *@This();

    fn new(filename: []const u8, source: []const u8) State {
        return .{ .source = source, .pos = .{ .filename = filename }, .prevPos = .{ .filename = filename } };
    }

    fn next(self: Self) !?Token {
        const notAtEOF = self.ignoreSpaceAndComments();
        if (!notAtEOF) {
            return null;
        }

        const c = self.getc();
        if (c == null) {
            return null;
        }

        const pos = self.pos;
        switch (c.?) {
            '(' => return .{ .pos = pos, .data = .{ .Punctuator = .LeftParen } },
            ')' => return .{ .pos = pos, .data = .{ .Punctuator = .RightParen } },
            '=' => return .{ .pos = pos, .data = .{ .Operator = .Equal } },
            '<' => {
                const c2 = self.getc();
                if (c2 == null) {
                    return .{ .pos = pos, .data = .{ .Operator = .Lesser } };
                }
                if (c2.? == '=') {
                    return .{ .pos = pos, .data = .{ .Operator = .LesserEqual } };
                }
                self.ungetc();
                return .{ .pos = pos, .data = .{ .Operator = .Lesser } };
            },
            '>' => {
                const c2 = self.getc();
                if (c2 == null) {
                    return .{ .pos = pos, .data = .{ .Operator = .Greater } };
                }
                if (c2.? == '=') {
                    return .{ .pos = pos, .data = .{ .Operator = .GreaterEqual } };
                }
                self.ungetc();
                return .{ .pos = pos, .data = .{ .Operator = .Greater } };
            },
            '!' => {
                const c2 = self.getc();
                if (c2 == null) {
                    return Error.ExpectedNotEqual;
                }
                if (c2.? == '=') {
                    return .{ .pos = pos, .data = .{ .Operator = .NotEqual } };
                }
                return Error.ExpectedNotEqual;
            },
            '"', '\'', '`' => return try self.parseString(pos, c.?),
            '0'...'9' => return try self.parseInteger(pos),
            'a'...'z', 'A'...'Z' => return try self.parseIdent(pos),
            else => return Error.IllegalCharacter,
        }
    }

    fn parseString(self: Self, pos: SourcePos, quote: u8) !Token {
        const startOff = self.offset;

        while (true) {
            const c = self.getc();
            if (c == quote) {
                break;
            }
            if (c == null) {
                return Error.UnterminatedString;
            }
        }

        return .{ .pos = pos, .data = .{ .String = self.source[startOff .. self.offset - 1] } };
    }

    fn parseInteger(self: Self, pos: SourcePos) !Token {
        const startOff = self.offset - 1;

        while (true) {
            const c = self.getc();
            if (c == null) {
                break;
            }
            switch (c.?) {
                '0'...'9', '_' => continue,
                else => {
                    self.ungetc();
                    break;
                },
            }
        }

        const raw = self.source[startOff..self.offset];
        const int = try std.fmt.parseInt(isize, raw, 10);
        return .{ .pos = pos, .data = .{ .Integer = int } };
    }

    fn parseIdent(self: Self, pos: SourcePos) !Token {
        const startOff = self.offset - 1;

        while (true) {
            const c = self.getc();
            if (c == null) {
                break;
            }
            switch (c.?) {
                'a'...'z', 'A'...'Z' => continue,
                else => {
                    self.ungetc();
                    break;
                },
            }
        }

        const ident = self.source[startOff..self.offset];
        if (std.mem.eql(u8, ident, "Format")) {
            return .{ .pos = pos, .data = .{ .Directive = .Format } };
        }
        if (std.mem.eql(u8, ident, "Namespace")) {
            return .{ .pos = pos, .data = .{ .Directive = .Namespace } };
        }
        if (std.mem.eql(u8, ident, "byte")) {
            return .{ .pos = pos, .data = .{ .Typename = .Byte } };
        }
        if (std.mem.eql(u8, ident, "bytes")) {
            return .{ .pos = pos, .data = .{ .Typename = .Bytes } };
        }
        if (std.mem.eql(u8, ident, "char")) {
            return .{ .pos = pos, .data = .{ .Typename = .Char } };
        }
        if (std.mem.eql(u8, ident, "word")) {
            return .{ .pos = pos, .data = .{ .Typename = .Word } };
        }
        if (std.mem.eql(u8, ident, "short")) {
            return .{ .pos = pos, .data = .{ .Typename = .Short } };
        }
        if (std.mem.eql(u8, ident, "dword")) {
            return .{ .pos = pos, .data = .{ .Typename = .Dword } };
        }
        if (std.mem.eql(u8, ident, "int")) {
            return .{ .pos = pos, .data = .{ .Typename = .Int } };
        }
        if (std.mem.eql(u8, ident, "qword")) {
            return .{ .pos = pos, .data = .{ .Typename = .Qword } };
        }
        if (std.mem.eql(u8, ident, "long")) {
            return .{ .pos = pos, .data = .{ .Typename = .Long } };
        }
        if (std.mem.eql(u8, ident, "signed")) {
            return .{ .pos = pos, .data = .{ .Modifier = .Signed } };
        }
        if (std.mem.eql(u8, ident, "unsigned")) {
            return .{ .pos = pos, .data = .{ .Modifier = .Unsigned } };
        }
        if (std.mem.eql(u8, ident, "array")) {
            return .{ .pos = pos, .data = .{ .Modifier = .Array } };
        }
        return Error.UnknownDirective;
    }

    fn ignoreSpaceAndComments(self: Self) bool {
        while (true) {
            const c = self.getc();
            if (c == null) {
                return true;
            }

            if (isSpace(c.?)) {
                if (!self.ignoreSpace()) {
                    return false;
                }
                continue;
            }

            if (c.? == '#') {
                if (!self.ignoreComment()) {
                    return false;
                }
                continue;
            }

            self.ungetc();
            return true;
        }
    }

    fn ignoreSpace(self: Self) bool {
        while (true) {
            const c = self.getc();
            if (c == null) {
                return false;
            }
            if (!isSpace(c.?)) {
                self.ungetc();
                return true;
            }
        }
    }

    fn ignoreComment(self: Self) bool {
        while (true) {
            const c = self.getc();
            if (c == null) {
                return false;
            }
            if (c.? == '\n') {
                return true;
            }
        }
    }

    fn isSpace(c: u8) bool {
        return c == ' ' or c == '\t' or c == '\n' or c == '\r';
    }

    fn getc(self: Self) ?u8 {
        if (self.offset >= self.source.len) {
            return null;
        }

        self.prevPos = self.pos;
        if (self.offset >= 1) {
            const pc = self.source[self.offset - 1];
            if (pc == '\n') {
                self.pos.line += 1;
                self.pos.col = 0;
            }
        }
        self.pos.col += 1;

        const c = self.source[self.offset];
        self.offset += 1;
        return c;
    }

    fn ungetc(self: Self) void {
        self.offset -= 1;
        self.pos = self.prevPos;
    }
};

test "whitespace" {
    var state = State.new("test", "\t   \t  \n \n \r\n   \t \t\r");
    const token = try state.next();
    try std.testing.expectEqual(@as(?Token, null), token);
}

test "comment" {
    var state = State.new("test", "\t   \t# this is a comment  \n \n # also comment \r\n   \t \t\r");
    const token = try state.next();
    try std.testing.expectEqual(@as(?Token, null), token);
}

test "string" {
    var state = State.new("test", "\t \"pee and poo\"");

    const token = try state.next();

    try std.testing.expect(token != null);
    switch (token.?.data) {
        .String => |s| {
            try std.testing.expectEqualStrings("pee and poo", s);
        },
        else => return error.UnexpectedTestResult,
    }
}

test "punctuators" {
    var state = State.new("test", " ( ) ");

    {
        const token = try state.next();
        try std.testing.expect(token != null);
        switch (token.?.data) {
            .Punctuator => |p| {
                try std.testing.expectEqual(Punctuator.LeftParen, p);
            },
            else => return error.UnexpectedTestResult,
        }
    }

    {
        const token = try state.next();
        try std.testing.expect(token != null);
        switch (token.?.data) {
            .Punctuator => |p| {
                try std.testing.expectEqual(Punctuator.RightParen, p);
            },
            else => return error.UnexpectedTestResult,
        }
    }
}

test "operators" {
    var state = State.new("test", " = >= <= != > < ");

    {
        const token = try state.next();
        try std.testing.expect(token != null);
        switch (token.?.data) {
            .Operator => |o| {
                try std.testing.expectEqual(Operator.Equal, o);
            },
            else => return error.UnexpectedTestResult,
        }
    }

    {
        const token = try state.next();
        try std.testing.expect(token != null);
        switch (token.?.data) {
            .Operator => |o| {
                try std.testing.expectEqual(Operator.GreaterEqual, o);
            },
            else => return error.UnexpectedTestResult,
        }
    }

    {
        const token = try state.next();
        try std.testing.expect(token != null);
        switch (token.?.data) {
            .Operator => |o| {
                try std.testing.expectEqual(Operator.LesserEqual, o);
            },
            else => return error.UnexpectedTestResult,
        }
    }

    {
        const token = try state.next();
        try std.testing.expect(token != null);
        switch (token.?.data) {
            .Operator => |o| {
                try std.testing.expectEqual(Operator.NotEqual, o);
            },
            else => return error.UnexpectedTestResult,
        }
    }

    {
        const token = try state.next();
        try std.testing.expect(token != null);
        switch (token.?.data) {
            .Operator => |o| {
                try std.testing.expectEqual(Operator.Greater, o);
            },
            else => return error.UnexpectedTestResult,
        }
    }

    {
        const token = try state.next();
        try std.testing.expect(token != null);
        switch (token.?.data) {
            .Operator => |o| {
                try std.testing.expectEqual(Operator.Lesser, o);
            },
            else => return error.UnexpectedTestResult,
        }
    }
}

test "directives" {
    var state = State.new("test", " Format Namespace ");

    {
        const token = try state.next();
        try std.testing.expect(token != null);
        switch (token.?.data) {
            .Directive => |d| {
                try std.testing.expectEqual(Directive.Format, d);
            },
            else => return error.UnexpectedTestResult,
        }
    }

    {
        const token = try state.next();
        try std.testing.expect(token != null);
        switch (token.?.data) {
            .Directive => |d| {
                try std.testing.expectEqual(Directive.Namespace, d);
            },
            else => return error.UnexpectedTestResult,
        }
    }
}

test "typenames" {
    var state = State.new("test", " byte bytes char   word short   dword int   qword long");

    {
        const token = try state.next();
        try std.testing.expect(token != null);
        switch (token.?.data) {
            .Typename => |t| {
                try std.testing.expectEqual(Typename.Byte, t);
            },
            else => return error.UnexpectedTestResult,
        }
    }

    {
        const token = try state.next();
        try std.testing.expect(token != null);
        switch (token.?.data) {
            .Typename => |t| {
                try std.testing.expectEqual(Typename.Bytes, t);
            },
            else => return error.UnexpectedTestResult,
        }
    }

    {
        const token = try state.next();
        try std.testing.expect(token != null);
        switch (token.?.data) {
            .Typename => |t| {
                try std.testing.expectEqual(Typename.Char, t);
            },
            else => return error.UnexpectedTestResult,
        }
    }

    {
        const token = try state.next();
        try std.testing.expect(token != null);
        switch (token.?.data) {
            .Typename => |t| {
                try std.testing.expectEqual(Typename.Word, t);
            },
            else => return error.UnexpectedTestResult,
        }
    }

    {
        const token = try state.next();
        try std.testing.expect(token != null);
        switch (token.?.data) {
            .Typename => |t| {
                try std.testing.expectEqual(Typename.Short, t);
            },
            else => return error.UnexpectedTestResult,
        }
    }

    {
        const token = try state.next();
        try std.testing.expect(token != null);
        switch (token.?.data) {
            .Typename => |t| {
                try std.testing.expectEqual(Typename.Dword, t);
            },
            else => return error.UnexpectedTestResult,
        }
    }

    {
        const token = try state.next();
        try std.testing.expect(token != null);
        switch (token.?.data) {
            .Typename => |t| {
                try std.testing.expectEqual(Typename.Int, t);
            },
            else => return error.UnexpectedTestResult,
        }
    }

    {
        const token = try state.next();
        try std.testing.expect(token != null);
        switch (token.?.data) {
            .Typename => |t| {
                try std.testing.expectEqual(Typename.Qword, t);
            },
            else => return error.UnexpectedTestResult,
        }
    }

    {
        const token = try state.next();
        try std.testing.expect(token != null);
        switch (token.?.data) {
            .Typename => |t| {
                try std.testing.expectEqual(Typename.Long, t);
            },
            else => return error.UnexpectedTestResult,
        }
    }
}

test "modifiers" {
    var state = State.new("test", "  unsigned signed  array  ");

    {
        const token = try state.next();
        try std.testing.expect(token != null);
        switch (token.?.data) {
            .Modifier => |m| {
                try std.testing.expectEqual(Modifier.Unsigned, m);
            },
            else => return error.UnexpectedTestResult,
        }
    }

    {
        const token = try state.next();
        try std.testing.expect(token != null);
        switch (token.?.data) {
            .Modifier => |m| {
                try std.testing.expectEqual(Modifier.Signed, m);
            },
            else => return error.UnexpectedTestResult,
        }
    }

    {
        const token = try state.next();
        try std.testing.expect(token != null);
        switch (token.?.data) {
            .Modifier => |m| {
                try std.testing.expectEqual(Modifier.Array, m);
            },
            else => return error.UnexpectedTestResult,
        }
    }
}

test "integers" {
    var state = State.new("test", "\t 123 3_2_1 100_000_000");

    {
        const token = try state.next();
        try std.testing.expect(token != null);
        switch (token.?.data) {
            .Integer => |i| {
                try std.testing.expectEqual(@as(isize, 123), i);
            },
            else => return error.UnexpectedTestResult,
        }
    }

    {
        const token = try state.next();
        try std.testing.expect(token != null);
        switch (token.?.data) {
            .Integer => |i| {
                try std.testing.expectEqual(@as(isize, 3_2_1), i);
            },
            else => return error.UnexpectedTestResult,
        }
    }

    {
        const token = try state.next();
        try std.testing.expect(token != null);
        switch (token.?.data) {
            .Integer => |i| {
                try std.testing.expectEqual(@as(isize, 100_000_000), i);
            },
            else => return error.UnexpectedTestResult,
        }
    }
}

test "mix" {
    var state = State.new("test", @embedFile("tests/lex.ff"));
    const tokens = [_]Token.Data{
        .{ .Directive = .Format },
        .{ .String = "nwge mesh" },
        .{ .Directive = .Namespace },
        .{ .String = "nwge_mesh" },
        .{ .String = "Magic" },
        .{ .Typename = .Bytes },
        .{ .Operator = .Equal },
        .{ .String = "NWGEMSH" },
    };
    for (tokens) |data| {
        const token = try state.next();
        try std.testing.expect(token != null);
        try std.testing.expect(token.?.data.eql(data));
    }
}
