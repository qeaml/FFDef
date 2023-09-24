const std = @import("std");
const common = @import("common.zig");
const parse = @import("../parse.zig");

pub fn write(fmt: parse.Format, out: anytype) !void {
    try out.print(
        \\#pragma once
        \\
        \\/*
        \\{s}.h
        \\----------
        \\{s} file format definitions
        \\*/
        \\
        \\#include<string.h>
        \\#include<stdlib.h>
        \\
    , .{ fmt.namespace, fmt.name });

    for (fmt.structs) |s| {
        try writeStruct(s.fields, fmt.namespace, fmt.namespace, s.name, out);
    }
    try writeStruct(fmt.fields, fmt.namespace, null, fmt.namespace, out);
}

fn writeStruct(fields: []parse.Field, outer_namespace: []const u8, inner_namespace: ?[]const u8, name: []const u8, out: anytype) !void {
    _ = try out.write("typedef struct ");
    if (inner_namespace) |ns| {
        try out.print("{s}_", .{ns});
    }
    try out.print("{s}_{{\n", .{name});

    for (fields) |f| {
        try out.writeByte(' ');
        try writeField(outer_namespace, f, out);
    }

    try out.writeByte('}');
    if (inner_namespace) |ns| {
        try out.print("{s}_", .{ns});
    }
    try out.print(
        \\{s};
        \\int 
    , .{name});
    if (inner_namespace) |ns| {
        try out.print("{s}_", .{ns});
    }
    try out.print("{s}_read(SDL_RWops *src, ", .{name});
    if (inner_namespace) |ns| {
        try out.print("{s}_", .{ns});
    }
    try out.print("{s} *out);\nint ", .{name});
    if (inner_namespace) |ns| {
        try out.print("{s}_", .{ns});
    }
    try out.print("{s}_write(SDL_RWops *out, ", .{name});
    if (inner_namespace) |ns| {
        try out.print("{s}_", .{ns});
    }
    try out.print("{s} src);\n", .{name});
    try writeNew(inner_namespace, name, out);
    try writeFree(outer_namespace, inner_namespace, name, fields, out);
}

fn writeField(namespace: []const u8, f: parse.Field, out: anytype) !void {
    switch (f.typ.datatype) {
        .Byte => try out.print("{s}signed char ", .{if (f.typ.isSigned) "" else "un"}),
        .Short => try out.print("{s}signed short ", .{if (f.typ.isSigned) "" else "un"}),
        .Int => try out.print("{s}signed int ", .{if (f.typ.isSigned) "" else "un"}),
        .Long => try out.print("{s}signed long long ", .{if (f.typ.isSigned) "" else "un"}),
        .Struct => try out.print("{s}_{s} ", .{ namespace, f.typ.structName.? }),
    }

    if (f.typ.isArray and !f.typ.arraySizeKnown) {
        try out.writeByte('*');
    }

    _ = try out.write(f.name);

    if (f.typ.isArray and f.typ.arraySizeKnown) {
        try out.print("[{d}]", .{f.typ.arraySize.size});
    }

    try out.writeByte(';');
    try out.writeByte('\n');
}

fn writeNew(namespace: ?[]const u8, name: []const u8, out: anytype) !void {
    _ = try out.write("inline ");
    if (namespace) |ns| {
        try out.print("{s}_", .{ns});
    }
    _ = try out.write(name);
    try out.writeByte(' ');
    if (namespace) |ns| {
        try out.print("{s}_", .{ns});
    }
    try out.print("{s}_new(void) {{\n ", .{name});

    if (namespace) |ns| {
        try out.print("{s}_", .{ns});
    }
    try out.print(
        \\{s} it;
        \\ memset(&it, 0, sizeof(it));
        \\ return it;
        \\}}
        \\
    , .{name});
}

fn writeFree(outer_namespace: []const u8, inner_namespace: ?[]const u8, name: []const u8, fields: []parse.Field, out: anytype) !void {
    _ = try out.write("inline void ");
    if (inner_namespace) |ns| {
        try out.print("{s}_", .{ns});
    }
    try out.print("{s}_free(", .{name});

    if (inner_namespace) |ns| {
        try out.print("{s}_", .{ns});
    }
    try out.print("{s} *it) {{\n ", .{name});

    for (fields) |f| {
        try writeFreeField(outer_namespace, f, out);
    }

    _ = try out.write("memset(it, 0, sizeof(*it));\n}\n");
}

fn writeFreeField(namespace: []const u8, f: parse.Field, out: anytype) !void {
    if (f.typ.isArray and !f.typ.arraySizeKnown) {
        try writeFreeDynArray(namespace, f, out);
    }
    if (!f.typ.isArray and f.typ.datatype == .Struct) {
        try out.print("{s}_{s}_free(&it->{s});\n ", .{ namespace, f.typ.structName.?, f.name });
    }
}

fn writeFreeDynArray(namespace: []const u8, f: parse.Field, out: anytype) !void {
    try out.print(
        \\if(it->{s} != NULL) {{
        \\  
    , .{f.name});

    if (f.typ.datatype == .Struct) {
        try out.print(
            \\for(size_t i = 0; i < it->{s}; i++) {{
            \\   
        , .{f.typ.arraySize.ref});
        try out.print("{s}_{s}_free(&it->{s}[i]);\n  }}\n  ", .{
            namespace,
            f.typ.structName.?,
            f.name,
        });
    }
    try out.print("free(it->{s});\n }}\n ", .{f.name});
}
