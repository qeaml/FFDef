const parse = @import("../parse.zig");

pub fn writeFieldDecl(namespace: []const u8, f: parse.Field, out: anytype, comptime withValue: bool) !void {
    switch (f.typ.datatype) {
        .Byte => try out.print("{s}signed char ", .{if (f.typ.isSigned) "" else "un"}),
        .Short => try out.print("{s}signed short ", .{if (f.typ.isSigned) "" else "un"}),
        .Int => try out.print("{s}signed int ", .{if (f.typ.isSigned) "" else "un"}),
        .Long => try out.print("{s}signed long long ", .{if (f.typ.isSigned) "" else "un"}),
        .Meta => try out.print("{s}_{s} ", .{ namespace, f.typ.metaName.? }),
    }

    if (f.typ.isArray and !f.typ.arraySizeKnown) {
        try out.writeByte('*');
    }

    _ = try out.write(f.name);

    if (f.typ.isArray and f.typ.arraySizeKnown) {
        try out.print("[{d}]", .{f.typ.arraySize.size});
    }

    const isConst = if (f.constraint) |cons| cons.op == .Equal else false;
    if (withValue and isConst) {
        try writeFieldInit(f, f.constraint.?, out);
    }
    try out.writeByte(';');
    try out.writeByte('\n');
}

fn writeFieldInit(f: parse.Field, cons: parse.Constraint, out: anytype) !void {
    _ = try out.write(" = ");
    if (f.typ.isArray) {
        try out.print("\"{s}\"", .{cons.val.str});
    } else {
        try out.print("{d}", .{cons.val.int});
    }
}
