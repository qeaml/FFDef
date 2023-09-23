const std = @import("std");
const common = @import("common.zig");
const parse = @import("../parse.zig");

pub fn write(fmt: parse.Format, out: anytype) !void {
    for (fmt.structs) |s| {
        try writeStruct(s.fields, fmt.namespace, fmt.namespace, s.name, out);
    }
    try writeStruct(fmt.fields, fmt.namespace, null, fmt.namespace, out);
}

// TODO this