const std = @import("std");
const parse = @import("parse.zig");

const writeHeader = @import("codegen/header.zig").write;
const writeReader = @import("codegen/reader.zig").write;
const writeWriter = @import("codegen/writer.zig").write;
const writeError = @import("codegen/error.zig").write;

pub fn write(fmt: parse.Format, header: anytype, reader: anytype, writer: anytype, err: anytype) !void {
    try writeHeader(fmt, header);
    try writeReader(fmt, reader);
    try writeWriter(fmt, writer);
    try writeError(fmt, err);
}
