const std = @import("std");
const parse = @import("../parse.zig");
const version = @import("../version.zig").current;

pub fn write(fmt: parse.Format, out: anytype) !void {
    try out.print(
        \\#pragma once
        \\
        \\/*
        \\{s}.h
        \\----------
        \\{s} file format definitions
        \\Generated with FFDef v{d}.{d}.{d}
        \\*/
        \\
        \\#include<string.h>
        \\#include<stdlib.h>
        \\#include<SDL2/SDL_RWops.h>
        \\
    , .{ fmt.namespace, fmt.name, version.major, version.minor, version.patch });

    for (fmt.structs) |s| {
        try writeStruct(true, fmt.namespace, s.name, s.fields, out);
    }

    try writeStruct(false, fmt.namespace, fmt.namespace, fmt.fields, out);
}

fn writeStruct(comptime namespaced: bool, namespace: []const u8, name: []const u8, fields: []parse.Field, out: anytype) !void {
    _ = try out.write("typedef struct ");
    if (namespaced) {
        try out.print("{s}_", .{namespace});
    }
    try out.print("{s}_{{\n", .{name});

    for (fields) |f| {
        try out.writeByte(' ');
        try writeField(namespace, f, out);
    }

    try out.writeByte('}');
    if (namespaced) {
        try out.print("{s}_", .{namespace});
    }
    try out.print(
        \\{s};
        \\int 
    , .{name});
    if (namespaced) {
        try out.print("{s}_", .{namespace});
    }
    try out.print("{s}_read(SDL_RWops *src, ", .{name});
    if (namespaced) {
        try out.print("{s}_", .{namespace});
    }
    try out.print("{s} *out);\nint ", .{name});
    if (namespaced) {
        try out.print("{s}_", .{namespace});
    }
    try out.print("{s}_write(SDL_RWops *out, ", .{name});
    if (namespaced) {
        try out.print("{s}_", .{namespace});
    }
    try out.print("{s} src);\n", .{name});
    try writeNew(namespaced, namespace, name, out);
    try writeFree(namespaced, namespace, name, fields, out);
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

fn writeNew(comptime namespaced: bool, namespace: []const u8, name: []const u8, out: anytype) !void {
    _ = try out.write("inline ");
    if (namespaced) {
        try out.print("{s}_", .{namespace});
    }
    _ = try out.write(name);
    try out.writeByte(' ');
    if (namespaced) {
        try out.print("{s}_", .{namespace});
    }
    try out.print("{s}_new(void) {{\n ", .{name});

    if (namespaced) {
        try out.print("{s}_", .{namespace});
    }
    try out.print(
        \\{s} it;
        \\ memset(&it, 0, sizeof(it));
        \\ return it;
        \\}}
        \\
    , .{name});
}

fn writeFree(comptime namespaced: bool, namespace: []const u8, name: []const u8, fields: []parse.Field, out: anytype) !void {
    _ = try out.write("inline void ");
    if (namespaced) {
        try out.print("{s}_", .{namespace});
    }
    try out.print("{s}_free(", .{name});

    if (namespaced) {
        try out.print("{s}_", .{namespace});
    }
    try out.print("{s} *it) {{\n ", .{name});

    for (fields) |f| {
        try writeFreeField(namespace, f, out);
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
