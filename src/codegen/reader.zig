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

fn writeStruct(comptime namespaced: bool, namespace: []const u8, name: []const u8, fields: []parse.Field, idx: usize, out: anytype) !void {
    _ = try out.write("int ");
    if (namespaced) {
        try out.print("{s}_", .{namespace});
    }
    try out.print("{s}_read(SDL_RWops *src, ", .{name});
    if (namespaced) {
        try out.print("{s}_", .{namespace});
    }
    try out.print("{s} *out) {{\n int status;\n", .{name});

    for (fields, 0..) |field, i| {
        try writeField(namespace, field, idx, i, out);
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
                \\ if(SDL_RWread(src, &out->{s}, 1, 1) != 1) {{
                \\  return {d};
                \\ }}
                \\
            , .{ field.name, err.compose(.Read, structIdx, idx) });
        },
        .Short => {
            try out.print(
                \\ if(SDL_RWread(src, &out->{s}, 2, 1) != 1) {{
                \\  return {d};
                \\ }}
                \\
            , .{ field.name, err.compose(.Read, structIdx, idx) });
        },
        .Int => {
            try out.print(
                \\ if(SDL_RWread(src, &out->{s}, 4, 1) != 1) {{
                \\  return {d};
                \\ }}
                \\
            , .{ field.name, err.compose(.Read, structIdx, idx) });
        },
        .Long => {
            try out.print(
                \\ if(SDL_RWread(src, &out->{s}, 8, 1) != 1) {{
                \\  return {d};
                \\ }}
                \\
            , .{ field.name, err.compose(.Read, structIdx, idx) });
        },
        .Struct => {
            try out.print(
                \\ if((status = {s}_{s}_read(src, &out->{s})) < 0) {{
                \\  return status;
                \\ }}
                \\
            , .{ namespace, field.typ.metaName.?, field.name });
        },
    }

    if (field.constraint) |c| {
        try writeVarConstraint(c, field, structIdx, idx, out);
    }
}

fn writeConst(namespace: []const u8, field: parse.Field, structIdx: usize, idx: usize, cons: parse.Constraint, out: anytype) !void {
    try out.writeByte(' ');
    try common.writeFieldDecl(namespace, field, out, false);

    if (field.typ.isArray) {
        return writeConstArray(namespace, field, structIdx, idx, cons, out);
    }

    switch (field.typ.datatype) {
        .Byte => try out.print(
            \\ if(SDL_RWread(src, &{s}, 1, 1) != 1) {{
            \\  return {d};
            \\ }}
            \\
        , .{ field.name, err.compose(.Read, structIdx, idx) }),
        .Short => try out.print(
            \\ if(SDL_RWread(src, &{s}, 2, 1) != 1) {{
            \\  return {d};
            \\ }}
            \\
        , .{ field.name, err.compose(.Read, structIdx, idx) }),
        .Int => try out.print(
            \\ if(SDL_RWread(src, &{s}, 4, 1) != 1) {{
            \\  return {d};
            \\ }}
            \\
        , .{ field.name, err.compose(.Read, structIdx, idx) }),
        .Long => try out.print(
            \\ if(SDL_RWread(src, &{s}, 8, 1) != 1) {{
            \\  return {d};
            \\ }}
            \\
        , .{ field.name, err.compose(.Read, structIdx, idx) }),
        .Struct => {
            try out.print(
                \\ if((status = {s}_{s}_read(src, &{s})) < 0) {{
                \\  return status;
                \\ }}
                \\
            , .{ namespace, field.typ.metaName.?, field.name });
        },
    }

    try out.print(
        \\ if({s} != {d}) {{
        \\  return {d};
        \\ }}
        \\
    , .{ field.name, cons.val.int, err.compose(.Constraint, structIdx, idx) });
}

fn writeVarStaticArray(namespace: []const u8, field: parse.Field, structIdx: usize, idx: usize, out: anytype) !void {
    switch (field.typ.datatype) {
        .Byte => {
            try out.print(
                \\ if(SDL_RWread(src, &out->{s}, 1, {d}) != {d}) {{
                \\  return {d};
                \\ }}
                \\
            , .{
                field.name,
                field.typ.arraySize.size,
                field.typ.arraySize.size,
                err.compose(.Read, structIdx, idx),
            });
        },
        .Short => {
            try out.print(
                \\ if(SDL_RWread(src, &out->{s}, 2, {d}) != {d}) {{
                \\  return {d};
                \\ }}
                \\
            , .{
                field.name,
                field.typ.arraySize.size,
                field.typ.arraySize.size,
                err.compose(.Read, structIdx, idx),
            });
        },
        .Int => {
            try out.print(
                \\ if(SDL_RWread(src, &out->{s}, 4, {d}) != {d}) {{
                \\  return {d};
                \\ }}
                \\
            , .{
                field.name,
                field.typ.arraySize.size,
                field.typ.arraySize.size,
                err.compose(.Read, structIdx, idx),
            });
        },
        .Long => {
            try out.print(
                \\ if(SDL_RWread(src, &out->{s}, 8, {d}) != {d}) {{
                \\  return {d};
                \\ }}
                \\
            , .{
                field.name,
                field.typ.arraySize.size,
                field.typ.arraySize.size,
                err.compose(.Read, structIdx, idx),
            });
        },
        .Struct => {
            for (0..field.typ.arraySize.size) |subidx| {
                try out.print(
                    \\ if((status = {s}_{s}_read(src, &out->{s}[{d}])) < 0) {{
                    \\  return status;
                    \\ }}
                    \\
                , .{ namespace, field.typ.metaName.?, field.name, subidx });
            }
        },
    }
}

fn writeVarDynArray(namespace: []const u8, field: parse.Field, structIdx: usize, idx: usize, out: anytype) !void {
    // TODO: Do not write 0-sized arrays, they may be NULL
    switch (field.typ.datatype) {
        .Byte => {
            try out.print(
                \\ out->{s} = calloc(1, out->{s}+1);
                \\ if(SDL_RWread(src, out->{s}, 1, out->{s}) != out->{s}) {{
                \\  return {d};
                \\ }}
                \\
            , .{
                field.name,
                field.typ.arraySize.ref,
                field.name,
                field.typ.arraySize.ref,
                field.typ.arraySize.ref,
                err.compose(.Read, structIdx, idx),
            });
        },
        .Short => {
            try out.print(
                \\ out->{s} = calloc(2, out->{s}+1);
                \\ if(SDL_RWread(src, out->{s}, 2, out->{s}) != out->{s}) {{
                \\  return {d};
                \\ }}
                \\
            , .{
                field.name,
                field.typ.arraySize.ref,
                field.name,
                field.typ.arraySize.ref,
                field.typ.arraySize.ref,
                err.compose(.Read, structIdx, idx),
            });
        },
        .Int => {
            try out.print(
                \\ out->{s} = calloc(4, out->{s}+1);
                \\ if(SDL_RWread(src, out->{s}, 4, out->{s}) != out->{s}) {{
                \\  return {d};
                \\ }}
                \\
            , .{
                field.name,
                field.typ.arraySize.ref,
                field.name,
                field.typ.arraySize.ref,
                field.typ.arraySize.ref,
                err.compose(.Read, structIdx, idx),
            });
        },
        .Long => {
            try out.print(
                \\ out->{s} = calloc(8, out->{s}+1);
                \\ if(SDL_RWread(src, out->{s}, 8, out->{s}) != out->{s}) {{
                \\  return {d};
                \\ }}
                \\
            , .{
                field.name,
                field.typ.arraySize.ref,
                field.name,
                field.typ.arraySize.ref,
                field.typ.arraySize.ref,
                err.compose(.Read, structIdx, idx),
            });
        },
        .Struct => {
            try out.print(
                \\ out->{s} = calloc(sizeof({s}_{s}), out->{s}+1);
                \\ for(size_t i = 0; i < out->{s}; i++) {{
                \\  if((status = {s}_{s}_read(src, &out->{s}[i])) < 0) {{
                \\   return status;
                \\  }}
                \\ }}
                \\
            , .{
                field.name,
                namespace,
                field.typ.metaName.?,
                field.typ.arraySize.ref,
                field.typ.arraySize.ref,
                namespace,
                field.typ.metaName.?,
                field.name,
            });
        },
    }
}

fn writeVarConstraint(cons: parse.Constraint, field: parse.Field, structIdx: usize, idx: usize, out: anytype) !void {
    switch (cons.op) {
        .Equal => try out.print(
            \\ if(out->{s} != {d}) {{
            \\  return {d};
            \\ }}
            \\
        , .{ field.name, cons.val.int, err.compose(.Constraint, structIdx, idx) }),
        .GreaterEqual => try out.print(
            \\ if(out->{s} < {d}) {{
            \\  return {d};
            \\ }}
            \\
        , .{ field.name, cons.val.int, err.compose(.Constraint, structIdx, idx) }),
        .LesserEqual => try out.print(
            \\ if(out->{s} > {d}) {{
            \\  return {d};
            \\ }}
            \\
        , .{ field.name, cons.val.int, err.compose(.Constraint, structIdx, idx) }),
        .NotEqual => try out.print(
            \\ if(out->{s} == {d}) {{
            \\  return {d};
            \\ }}
            \\
        , .{ field.name, cons.val.int, err.compose(.Constraint, structIdx, idx) }),
        .Greater => try out.print(
            \\ if(out->{s} <= {d}) {{
            \\  return {d};
            \\ }}
            \\
        , .{ field.name, cons.val.int, err.compose(.Constraint, structIdx, idx) }),
        .Lesser => try out.print(
            \\ if(out->{s} >= {d}) {{
            \\  return {d};
            \\ }}
            \\
        , .{ field.name, cons.val.int, err.compose(.Constraint, structIdx, idx) }),
    }
}

fn writeConstArray(namespace: []const u8, field: parse.Field, structIdx: usize, idx: usize, cons: parse.Constraint, out: anytype) !void {
    _ = namespace;
    try out.print(
        \\ if(SDL_RWread(src, &{s}, 1, {d}) != {d}) {{
        \\  return {d};
        \\ }}
        \\
    , .{
        field.name,
        cons.val.str.len,
        cons.val.str.len,
        err.compose(.Read, structIdx, idx),
    });

    for (cons.val.str, 0..) |c, i| {
        try out.print(
            \\ if({s}[{d}] != '{c}') {{
            \\  return {d};
            \\ }}
            \\
        , .{ field.name, i, c, err.compose(.Constraint, structIdx, idx) });
    }
}
