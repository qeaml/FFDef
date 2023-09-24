const std = @import("std");
const common = @import("common.zig");
const parse = @import("../parse.zig");

pub fn write(fmt: parse.Format, out: anytype) !void {
    try out.print(
        \\#include"{s}.h"
        \\
    , .{fmt.namespace});

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
    try out.print("{s}_write(SDL_RWops *out, ", .{name});
    if (namespaced) {
        try out.print("{s}_", .{namespace});
    }
    _ = try out.write(" src) {\n int status;\n");

    for (fields, 0..) |field, idx| {
        try out.writeByte(' ');
        try writeField(namespace, field, idx, out);
    }

    try out.writeByte('}');
    try out.writeByte('\n');
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
                \\if(SDL_RWwrite(out, &src.{s}, 1, 1) != 1) {{
                \\  return -{d};
                \\ }}
                \\
            , .{ field.name, 0x100 + idx });
        },
        .Short => {
            try out.print(
                \\if(SDL_RWwrite(out, &src.{s}, 2, 1) != 1) {{
                \\  return -{d};
                \\ }}
                \\
            , .{ field.name, 0x100 + idx });
        },
        .Int => {
            try out.print(
                \\if(SDL_RWwrite(out, &src.{s}, 4, 1) != 1) {{
                \\  return -{d};
                \\ }}
                \\
            , .{ field.name, 0x100 + idx });
        },
        .Long => {
            try out.print(
                \\if(SDL_RWwrite(out, &src.{s}, 8, 1) != 1) {{
                \\  return -{d};
                \\ }}
                \\
            , .{ field.name, 0x100 + idx });
        },
        .Struct => {
            try out.print(
                \\if((status = {s}_{s}_write(out, src.{s})) < 0) {{
                \\  return status;
                \\ }}
                \\
            , .{ namespace, field.typ.structName.?, field.name });
        },
    }
}

fn writeStaticArrayField(namespace: []const u8, field: parse.Field, idx: usize, out: anytype) !void {
    switch (field.typ.datatype) {
        .Byte => {
            try out.print(
                \\if(SDL_RWwrite(out, &src.{s}, 1, {d}) != {d}) {{
                \\  return -{d};
                \\ }}
                \\
            , .{
                field.name,
                field.typ.arraySize.size,
                field.typ.arraySize.size,
                0x100 + idx,
            });
        },
        .Short => {
            try out.print(
                \\if(SDL_RWwrite(out, &src.{s}, 2, {d}) != {d}) {{
                \\  return -{d};
                \\ }}
                \\
            , .{
                field.name,
                field.typ.arraySize.size,
                field.typ.arraySize.size,
                0x100 + idx,
            });
        },
        .Int => {
            try out.print(
                \\if(SDL_RWwrite(out, &src.{s}, 4, {d}) != {d}) {{
                \\  return -{d};
                \\ }}
                \\
            , .{
                field.name,
                field.typ.arraySize.size,
                field.typ.arraySize.size,
                0x100 + idx,
            });
        },
        .Long => {
            try out.print(
                \\if(SDL_RWwrite(out, &src.{s}, 8, {d}) != {d}) {{
                \\  return -{d};
                \\ }}
                \\
            , .{
                field.name,
                field.typ.arraySize.size,
                field.typ.arraySize.size,
                0x100 + idx,
            });
        },
        .Struct => {
            for (0..field.typ.arraySize.size) |subidx| {
                try out.print(
                    \\if((status = {s}_{s}_write(out, src.{s}[{d}])) < 0) {{
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
                \\if(SDL_RWwrite(out, &src.{s}, 1, src.{s}) != src.{s}) {{
                \\  return -{d};
                \\ }}
                \\
            , .{
                field.name,
                field.typ.arraySize.ref,
                field.typ.arraySize.ref,
                0x100 + idx,
            });
        },
        .Short => {
            try out.print(
                \\if(SDL_RWwrite(out, &src.{s}, 2, src.{s}) != src.{s}) {{
                \\  return -{d};
                \\ }}
                \\
            , .{
                field.name,
                field.typ.arraySize.ref,
                field.typ.arraySize.ref,
                0x100 + idx,
            });
        },
        .Int => {
            try out.print(
                \\if(SDL_RWwrite(out, &src.{s}, 4, src.{s}) != src.{s}) {{
                \\  return -{d};
                \\ }}
                \\
            , .{
                field.name,
                field.typ.arraySize.ref,
                field.typ.arraySize.ref,
                0x100 + idx,
            });
        },
        .Long => {
            try out.print(
                \\if(SDL_RWwrite(out, &src.{s}, 8, src.{s}) != src.{s}) {{
                \\  return -{d};
                \\ }}
                \\
            , .{
                field.name,
                field.typ.arraySize.ref,
                field.typ.arraySize.ref,
                0x100 + idx,
            });
        },
        .Struct => {
            try out.print(
                \\for(size_t i = 0; i < src.{s}; i++) {{
                \\  if((status = {s}_{s}_write(out, src.{s}[i])) < 0) {{
                \\   return status;
                \\  }}
                \\ }}
                \\
            , .{
                field.typ.arraySize.ref,
                namespace,
                field.typ.structName.?,
                field.name,
            });
        },
    }
}
