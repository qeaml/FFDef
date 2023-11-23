const std = @import("std");
const parse = @import("../parse.zig");
const version = @import("../version.zig").current;

pub fn write(fmt: parse.Format, out: anytype) !void {
    for (fmt.structs) |s| {
        try writeStruct(fmt.namespace, s.name, s.fields, out);
    }

    try writeStruct(null, fmt.namespace, fmt.fields, out);

    try out.print(
        \\const char **{s}_struct_fields[] = {{
        \\ {s}_fields,
        \\
    , .{ fmt.namespace, fmt.namespace });

    for (fmt.structs) |s| {
        try out.print(" {s}_{s}_fields,\n", .{ fmt.namespace, s.name });
    }

    try out.print(
        \\}};
        \\const char *{s}_struct_names[] = {{
        \\ "{s}",
        \\
    , .{ fmt.namespace, fmt.namespace });

    for (fmt.structs) |s| {
        try out.print(" \"{s}\",\n", .{s.name});
    }

    _ = try out.write("};\n");

    try out.print(@embedFile("formaterror.c"), .{
        fmt.namespace, fmt.namespace, fmt.namespace,
        fmt.namespace, fmt.namespace, fmt.namespace,
        fmt.namespace, fmt.namespace,
    });
}

fn writeStruct(namespace: ?[]const u8, name: []const u8, fields: []parse.Field, out: anytype) !void {
    _ = try out.write("const char *");
    if (namespace) |ns| {
        try out.print("{s}_", .{ns});
    }
    try out.print("{s}_fields[] = {{\n", .{name});
    for (fields) |f| {
        try out.print(" \"{s}\",\n", .{f.name});
    }
    _ = try out.write("};\n");
}

pub const Type = enum(u8) { Write = 0, Read = 1, Constraint = 2 };

pub fn compose(typ: Type, structIdx: usize, fieldIdx: usize) i32 {
    const typeMask = @as(i32, @intFromEnum(typ) + 1);
    const structMask = @as(i32, @intCast((structIdx & 0xFF) << 8));
    const fieldMask = @as(i32, @intCast((fieldIdx & 0xFF) << 16));
    return -(typeMask | structMask | fieldMask);
}
