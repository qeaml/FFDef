const std = @import("std");
const parse = @import("../parse.zig");
const version = @import("../version.zig").current;

pub fn write(fmt: parse.Format, out: anytype) !void {
    try out.print(
        \\// Generated with FFDef v{d}.{d}.{d}
        \\#include"{s}.h"
        \\
    , .{ version.major, version.minor, version.patch, fmt.namespace });

    for (fmt.structs) |s| {
        try writeStruct(true, fmt.namespace, s.name, s.fields, out);
    }

    try writeStruct(false, fmt.namespace, fmt.namespace, fmt.fields, out);
}

fn writeStruct(comptime namespaced: bool, namespace: []const u8, name: []const u8, fields: []parse.Field, out: anytype) !void {
    _ = try out.write("int ");
    if (namespaced) {
        try out.print("{s}_", .{namespace});
    }
    try out.print("{s}_read(SDL_RWops *src, ", .{name});
    if (namespaced) {
        try out.print("{s}_", .{namespace});
    }
    try out.print("{s} *out) {{\n int status;\n", .{name});

    for (fields, 0..) |field, idx| {
        try out.writeByte(' ');
        try writeField(namespace, field, idx, out);
    }

    _ = try out.write(" return 0;\n}\n");
}

fn writeField(namespace: []const u8, field: parse.Field, idx: usize, out: anytype) !void {
    if (field.typ.isArray) {
        if (field.typ.arraySizeKnown) {
            try writeStaticArrayField(namespace, field, idx, out);
            return;
        }
        try writeDynArrayField(namespace, field, idx, out);
        return;
    }

    switch (field.typ.datatype) {
        .Byte => {
            try out.print(
                \\if(SDL_RWread(src, &out->{s}, 1, 1) != 1) {{
                \\  return -{d};
                \\ }}
                \\
            , .{ field.name, 0x200 + idx });
        },
        .Short => {
            try out.print(
                \\if(SDL_RWread(src, &out->{s}, 2, 1) != 1) {{
                \\  return -{d};
                \\ }}
                \\
            , .{ field.name, 0x200 + idx });
        },
        .Int => {
            try out.print(
                \\if(SDL_RWread(src, &out->{s}, 4, 1) != 1) {{
                \\  return -{d};
                \\ }}
                \\
            , .{ field.name, 0x200 + idx });
        },
        .Long => {
            try out.print(
                \\if(SDL_RWread(src, &out->{s}, 8, 1) != 1) {{
                \\  return -{d};
                \\ }}
                \\
            , .{ field.name, 0x200 + idx });
        },
        .Struct => {
            try out.print(
                \\if((status = {s}_{s}_read(src, &out->{s})) < 0) {{
                \\  return status;
                \\ }}
                \\
            , .{ namespace, field.typ.structName.?, field.name });
        },
    }
    // TODO: Validate constraints
    // TODO: Do not store fields with = constraint
}

fn writeStaticArrayField(namespace: []const u8, field: parse.Field, idx: usize, out: anytype) !void {
    switch (field.typ.datatype) {
        .Byte => {
            try out.print(
                \\if(SDL_RWread(src, &out->{s}, 1, {d}) != {d}) {{
                \\  return -{d};
                \\ }}
                \\
            , .{
                field.name,
                field.typ.arraySize.size,
                field.typ.arraySize.size,
                0x200 + idx,
            });
        },
        .Short => {
            try out.print(
                \\if(SDL_RWread(src, &out->{s}, 2, {d}) != {d}) {{
                \\  return -{d};
                \\ }}
                \\
            , .{
                field.name,
                field.typ.arraySize.size,
                field.typ.arraySize.size,
                0x200 + idx,
            });
        },
        .Int => {
            try out.print(
                \\if(SDL_RWread(src, &out->{s}, 4, {d}) != {d}) {{
                \\  return -{d};
                \\ }}
                \\
            , .{
                field.name,
                field.typ.arraySize.size,
                field.typ.arraySize.size,
                0x200 + idx,
            });
        },
        .Long => {
            try out.print(
                \\if(SDL_RWread(src, &out->{s}, 8, {d}) != {d}) {{
                \\  return -{d};
                \\ }}
                \\
            , .{
                field.name,
                field.typ.arraySize.size,
                field.typ.arraySize.size,
                0x200 + idx,
            });
        },
        .Struct => {
            for (0..field.typ.arraySize.size) |subidx| {
                try out.print(
                    \\if((status = {s}_{s}_read(src, &out->{s}[{d}])) < 0) {{
                    \\  return status;
                    \\ }}
                    \\ 
                , .{ namespace, field.typ.structName.?, field.name, subidx });
            }
        },
    }
}

fn writeDynArrayField(namespace: []const u8, field: parse.Field, idx: usize, out: anytype) !void {
    switch (field.typ.datatype) {
        .Byte => {
            try out.print(
                \\out->{s} = calloc(1, out->{s}+1);
                \\ if(SDL_RWread(src, out->{s}, 1, out->{s}) != out->{s}) {{
                \\  return -{d};
                \\ }}
                \\
            , .{
                field.name,
                field.typ.arraySize.ref,
                field.name,
                field.typ.arraySize.ref,
                field.typ.arraySize.ref,
                0x200 + idx,
            });
        },
        .Short => {
            try out.print(
                \\out->{s} = calloc(2, out->{s}+1);
                \\ if(SDL_RWread(src, out->{s}, 2, out->{s}) != out->{s}) {{
                \\  return -{d};
                \\ }}
                \\
            , .{
                field.name,
                field.typ.arraySize.ref,
                field.name,
                field.typ.arraySize.ref,
                field.typ.arraySize.ref,
                0x200 + idx,
            });
        },
        .Int => {
            try out.print(
                \\out->{s} = calloc(4, out->{s}+1);
                \\ if(SDL_RWread(src, out->{s}, 4, out->{s}) != out->{s}) {{
                \\  return -{d};
                \\ }}
                \\
            , .{
                field.name,
                field.typ.arraySize.ref,
                field.name,
                field.typ.arraySize.ref,
                field.typ.arraySize.ref,
                0x200 + idx,
            });
        },
        .Long => {
            try out.print(
                \\out->{s} = calloc(8, out->{s}+1);
                \\ if(SDL_RWread(src, out->{s}, 8, out->{s}) != out->{s}) {{
                \\  return -{d};
                \\ }}
                \\
            , .{
                field.name,
                field.typ.arraySize.ref,
                field.name,
                field.typ.arraySize.ref,
                field.typ.arraySize.ref,
                0x200 + idx,
            });
        },
        .Struct => {
            try out.print(
                \\out->{s} = calloc(sizeof({s}_{s}), out->{s}+1);
                \\ for(size_t i = 0; i < out->{s}; i++) {{
                \\  if((status = {s}_{s}_read(src, &out->{s}[i])) < 0) {{
                \\   return status;
                \\  }}
                \\ }}
                \\
            , .{
                field.name,
                namespace,
                field.typ.structName.?,
                field.typ.arraySize.ref,
                field.typ.arraySize.ref,
                namespace,
                field.typ.structName.?,
                field.name,
            });
        },
    }
}
