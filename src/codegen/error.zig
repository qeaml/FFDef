const std = @import("std");
const parse = @import("../parse.zig");
const version = @import("../version.zig").current;

pub fn write(fmt: parse.Format, out: anytype) !void {
    for (fmt.structs) |s| {
        try writeStruct(s.name, s.fields, out);
    }

    try writeStruct(fmt.namespace, fmt.fields, out);

    try out.print(
        \\const char **struct_fields[] = {{
        \\ {s}_fields,
        \\
    , .{fmt.namespace});

    for (fmt.structs) |s| {
        try out.print(" {s}_fields,\n", .{s.name});
    }

    try out.print(
        \\}};
        \\const char *struct_names[] = {{
        \\ "{s}",
        \\
    , .{fmt.namespace});

    for (fmt.structs) |s| {
        try out.print(" \"{s}\",\n", .{s.name});
    }

    _ = try out.write("};\n");

    try out.print(@embedFile("formaterror.c"), .{fmt.namespace});
}

fn writeStruct(name: []const u8, fields: []parse.Field, out: anytype) !void {
    try out.print("const char *{s}_fields[] = {{\n", .{name});
    for (fields) |f| {
        try out.print(" \"{s}\",\n", .{f.name});
    }
    _ = try out.write("};\n");
}

pub const Type = enum(u8) { Write = 0, Read = 1, Constraint = 2 };

pub fn compose(typ: Type, structIdx: usize, fieldIdx: usize) i32 {
    const typeMask = @as(i32, @intFromEnum(typ));
    const structMask = @as(i32, @intCast((structIdx & 0xFF) << 8));
    const fieldMask = @as(i32, @intCast((fieldIdx & 0xFF) << 16));
    return -(typeMask | structMask | fieldMask);
}
