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

pub const Type = enum(u8) { Write, Read, Constriant };

pub fn compose(typ: Type, structIdx: u8, fieldIdx: u8) i32 {
    return -(typ | (structIdx << 8) | (fieldIdx << 16));
}
