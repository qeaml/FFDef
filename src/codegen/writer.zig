const std = @import("std");
const parse = @import("../parse.zig");
const version = @import("../version.zig").current;
const err = @import("error.zig");
const common = @import("common.zig");

pub fn write(fmt: parse.Format, out: anytype) !void {
    try out.print(
        \\// Generated with FFDef v{d}.{d}.{d}
        \\#include"{s}.h"
        \\
    , .{ version.major, version.minor, version.patch, fmt.namespace });

    for (fmt.structs, 0..) |s, i| {
        try writeStruct(true, fmt.namespace, s.name, s.fields, i + 1, out);
    }

    try writeStruct(false, fmt.namespace, fmt.namespace, fmt.fields, 0, out);
}

fn writeStruct(comptime namespaced: bool, namespace: []const u8, name: []const u8, fields: []parse.Field, structIdx: usize, out: anytype) !void {
    _ = try out.write("int ");
    if (namespaced) {
        try out.print("{s}_", .{namespace});
    }
    try out.print("{s}_write(SDL_RWops *out, ", .{name});
    if (namespaced) {
        try out.print("{s}_", .{namespace});
    }
    try out.print("{s} src) {{\n int status;\n", .{name});

    for (fields, 0..) |field, idx| {
        try writeField(namespace, field, structIdx, idx, out);
    }

    _ = try out.write(" return 0;\n}\n");
}

fn writeField(namespace: []const u8, field: parse.Field, structIdx: usize, idx: usize, out: anytype) !void {
    if (field.constraint) |cons| {
        if (cons.op == .Equal) {
            return writeConst(namespace, field, structIdx, idx, cons, out);
        }
    }
    return writeVar(namespace, field, structIdx, idx, out);
}

fn writeConst(namespace: []const u8, field: parse.Field, structIdx: usize, idx: usize, cons: parse.Constraint, out: anytype) !void {
    try out.writeByte(' ');
    try common.writeFieldDecl(namespace, field, out, true);

    if (field.typ.isArray) {
        try out.print(
            \\ if(SDL_RWwrite(out, {s}, 1, {d}) != {d}) {{
            \\  return {d};
            \\ }}
            \\
        , .{
            field.name,
            cons.val.str.len,
            cons.val.str.len,
            err.compose(.Write, structIdx, idx),
        });
        return;
    }

    switch (field.typ.datatype) {
        .Byte => {
            try out.print(
                \\ if(SDL_RWwrite(out, &{s}, 1, 1) != 1) {{
                \\  return {d};
                \\ }}
                \\
            , .{ field.name, err.compose(.Write, structIdx, idx) });
        },
        .Short => {
            try out.print(
                \\ if(SDL_RWwrite(out, &{s}, 2, 1) != 1) {{
                \\  return {d};
                \\ }}
                \\
            , .{ field.name, err.compose(.Write, structIdx, idx) });
        },
        .Int => {
            try out.print(
                \\ if(SDL_RWwrite(out, &{s}, 4, 1) != 1) {{
                \\  return {d};
                \\ }}
                \\
            , .{ field.name, err.compose(.Write, structIdx, idx) });
        },
        .Long => {
            try out.print(
                \\ if(SDL_RWwrite(out, &{s}, 8, 1) != 1) {{
                \\  return {d};
                \\ }}
                \\
            , .{ field.name, err.compose(.Write, structIdx, idx) });
        },
        .Struct => {
            try out.print(
                \\if((status = {s}_{s}_write(out, {s})) < 0) {{
                \\  return status;
                \\ }}
                \\
            , .{ namespace, field.typ.structName.?, field.name });
        },
    }
}

fn writeVar(namespace: []const u8, field: parse.Field, structIdx: usize, idx: usize, out: anytype) !void {
    if (field.typ.isArray) {
        if (field.typ.arraySizeKnown) {
            return writeVarStaticArray(namespace, field, structIdx, idx, out);
        }
        return writeVarDynArray(namespace, field, structIdx, idx, out);
    }

    switch (field.typ.datatype) {
        .Byte => {
            try out.print(
                \\ if(SDL_RWwrite(out, &src.{s}, 1, 1) != 1) {{
                \\  return {d};
                \\ }}
                \\
            , .{ field.name, err.compose(.Write, structIdx, idx) });
        },
        .Short => {
            try out.print(
                \\ if(SDL_RWwrite(out, &src.{s}, 2, 1) != 1) {{
                \\  return {d};
                \\ }}
                \\
            , .{ field.name, err.compose(.Write, structIdx, idx) });
        },
        .Int => {
            try out.print(
                \\ if(SDL_RWwrite(out, &src.{s}, 4, 1) != 1) {{
                \\  return {d};
                \\ }}
                \\
            , .{ field.name, err.compose(.Write, structIdx, idx) });
        },
        .Long => {
            try out.print(
                \\ if(SDL_RWwrite(out, &src.{s}, 8, 1) != 1) {{
                \\  return {d};
                \\ }}
                \\
            , .{ field.name, err.compose(.Write, structIdx, idx) });
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

fn writeVarStaticArray(namespace: []const u8, field: parse.Field, structIdx: usize, idx: usize, out: anytype) !void {
    switch (field.typ.datatype) {
        .Byte => {
            try out.print(
                \\ if(SDL_RWwrite(out, src.{s}, 1, {d}) != {d}) {{
                \\  return {d};
                \\ }}
                \\
            , .{
                field.name,
                field.typ.arraySize.size,
                field.typ.arraySize.size,
                err.compose(.Write, structIdx, idx),
            });
        },
        .Short => {
            try out.print(
                \\ if(SDL_RWwrite(out, src.{s}, 2, {d}) != {d}) {{
                \\  return {d};
                \\ }}
                \\
            , .{
                field.name,
                field.typ.arraySize.size,
                field.typ.arraySize.size,
                err.compose(.Write, structIdx, idx),
            });
        },
        .Int => {
            try out.print(
                \\ if(SDL_RWwrite(out, src.{s}, 4, {d}) != {d}) {{
                \\  return {d};
                \\ }}
                \\
            , .{
                field.name,
                field.typ.arraySize.size,
                field.typ.arraySize.size,
                err.compose(.Write, structIdx, idx),
            });
        },
        .Long => {
            try out.print(
                \\ if(SDL_RWwrite(out, src.{s}, 8, {d}) != {d}) {{
                \\  return {d};
                \\ }}
                \\
            , .{
                field.name,
                field.typ.arraySize.size,
                field.typ.arraySize.size,
                err.compose(.Write, structIdx, idx),
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

fn writeVarDynArray(namespace: []const u8, field: parse.Field, structIdx: usize, idx: usize, out: anytype) !void {
    // TODO: Do not read 0-sized arrays, set them to NULL.
    switch (field.typ.datatype) {
        .Byte => {
            try out.print(
                \\ if(SDL_RWwrite(out, src.{s}, 1, src.{s}) != src.{s}) {{
                \\  return {d};
                \\ }}
                \\
            , .{
                field.name,
                field.typ.arraySize.ref,
                field.typ.arraySize.ref,
                err.compose(.Write, structIdx, idx),
            });
        },
        .Short => {
            try out.print(
                \\ if(SDL_RWwrite(out, src.{s}, 2, src.{s}) != src.{s}) {{
                \\  return {d};
                \\ }}
                \\
            , .{
                field.name,
                field.typ.arraySize.ref,
                field.typ.arraySize.ref,
                err.compose(.Write, structIdx, idx),
            });
        },
        .Int => {
            try out.print(
                \\ if(SDL_RWwrite(out, src.{s}, 4, src.{s}) != src.{s}) {{
                \\  return {d};
                \\ }}
                \\
            , .{
                field.name,
                field.typ.arraySize.ref,
                field.typ.arraySize.ref,
                err.compose(.Write, structIdx, idx),
            });
        },
        .Long => {
            try out.print(
                \\ if(SDL_RWwrite(out, src.{s}, 8, src.{s}) != src.{s}) {{
                \\  return {d};
                \\ }}
                \\
            , .{
                field.name,
                field.typ.arraySize.ref,
                field.typ.arraySize.ref,
                err.compose(.Write, structIdx, idx),
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
