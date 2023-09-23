const std = @import("std");
const parse = @import("parse.zig");

const headerImpl = @import("codegen/header.zig");
const readerImpl = @import("codegen/reader.zig");
const writerImpl = @import("codegen/writer.zig");

pub fn write(fmt: parse.Format, header: anytype, reader: anytype, writer: anytype) !void {
    try headerImpl.write(fmt, header);
    try readerImpl.write(fmt, reader);
    try writerImpl.write(fmt, writer);
}
