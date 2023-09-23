const std = @import("std");
const parse = @import("parse.zig");
const codegen = @import("codegen.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Provide a filename", .{});
        return;
    }

    var root = std.fs.cwd();
    if (args.len >= 3) {
        root.makeDir(args[2]) catch {};
        root = try root.openDir(args[2], .{});
    }

    const filename = args[1];
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();
    const source = try file.reader().readAllAlloc(allocator, 102400);
    defer allocator.free(source);

    const format = try parse.all(allocator, filename, source);
    var header = std.ArrayList(u8).init(allocator);
    defer header.deinit();
    var reader = std.ArrayList(u8).init(allocator);
    defer reader.deinit();
    var writer = std.ArrayList(u8).init(allocator);
    defer writer.deinit();

    try codegen.write(format, header.writer(), reader.writer(), writer.writer());

    var headerName = std.ArrayList(u8).fromOwnedSlice(allocator, try allocator.dupe(u8, format.namespace));
    try headerName.appendSlice(".h");
    defer headerName.deinit();
    const headerFile = try root.createFile(headerName.items, .{});
    try headerFile.writer().writeAll(header.items);

    var readerName = std.ArrayList(u8).fromOwnedSlice(allocator, try allocator.dupe(u8, format.namespace));
    try readerName.appendSlice("_reader.c");
    defer readerName.deinit();
    const readerFile = try root.createFile(readerName.items, .{});
    try readerFile.writer().writeAll(reader.items);

    var writerName = std.ArrayList(u8).fromOwnedSlice(allocator, try allocator.dupe(u8, format.namespace));
    try writerName.appendSlice("_writer.c");
    defer writerName.deinit();
    const writerFile = try root.createFile(writerName.items, .{});
    try writerFile.writer().writeAll(writer.items);
}
