const std = @import("std");
const parse = @import("parse.zig");
const codegen = @import("codegen.zig");
const diag = @import("diag.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        diag.errWithTip(
            "Provide a path to file format definition file.",
            .{},
            "These files usually have a .ff extension.",
            .{},
            null,
        );
        return;
    }

    const filename = args[1];
    const file = std.fs.cwd().openFile(filename, .{}) catch |e| {
        diag.err("Could not open file '{s}': {?}", .{ filename, e }, null);
        return;
    };
    defer file.close();

    var root = std.fs.cwd();
    if (args.len >= 3) {
        root.makeDir(args[2]) catch {};
        root = try root.openDir(args[2], .{});
    } else {
        if (std.fs.path.dirname(filename)) |path| {
            root = try root.openDir(path, .{});
        }
    }

    const source = file.reader().readAllAlloc(allocator, 102400) catch |e| {
        diag.err("Could not read file '{s}': {?}", .{ filename, e }, null);
        return;
    };
    defer allocator.free(source);

    const format = parse.all(allocator, filename, source) catch |e| {
        diag.err("Could not parse {s} due to error: {?}.", .{ filename, e }, null);
        return;
    };
    var header = std.ArrayList(u8).init(allocator);
    defer header.deinit();
    var reader = std.ArrayList(u8).init(allocator);
    defer reader.deinit();
    var writer = std.ArrayList(u8).init(allocator);
    defer writer.deinit();
    var err = std.ArrayList(u8).init(allocator);
    defer err.deinit();

    codegen.write(format, header.writer(), reader.writer(), writer.writer(), err.writer()) catch |e| {
        diag.err("Could not generate implementation for {s} due to error: {?}.", .{ filename, e }, null);
        return;
    };

    writeHeader: {
        var headerName = std.ArrayList(u8).fromOwnedSlice(allocator, try allocator.dupe(u8, format.namespace));
        try headerName.appendSlice(".h");
        defer headerName.deinit();
        const headerFile = root.createFile(headerName.items, .{}) catch |e| {
            std.log.err("Could not create header file '{s}': {?}", .{ headerName.items, e });
            break :writeHeader;
        };
        headerFile.writer().writeAll(header.items) catch |e| {
            std.log.err("Could not write to header file '{s}': {?}", .{ headerName.items, e });
        };
    }

    writeReader: {
        var readerName = std.ArrayList(u8).fromOwnedSlice(allocator, try allocator.dupe(u8, format.namespace));
        try readerName.appendSlice("_reader.c");
        defer readerName.deinit();
        const readerFile = root.createFile(readerName.items, .{}) catch |e| {
            std.log.err("Could not create reader implementation file '{s}': {?}", .{ readerName.items, e });
            break :writeReader;
        };
        readerFile.writer().writeAll(reader.items) catch |e| {
            std.log.err("Could not write to reader implementation file '{s}': {?}", .{ readerName.items, e });
        };
    }

    writeWriter: {
        var writerName = std.ArrayList(u8).fromOwnedSlice(allocator, try allocator.dupe(u8, format.namespace));
        try writerName.appendSlice("_writer.c");
        defer writerName.deinit();
        const writerFile = root.createFile(writerName.items, .{}) catch |e| {
            std.log.err("Could not create writer implementation file '{s}': {?}", .{ writerName.items, e });
            break :writeWriter;
        };
        writerFile.writer().writeAll(writer.items) catch |e| {
            std.log.err("Could not write to writer implementation file '{s}': {?}", .{ writerName.items, e });
        };
    }
    writeError: {
        var errorName = std.ArrayList(u8).fromOwnedSlice(allocator, try allocator.dupe(u8, format.namespace));
        try errorName.appendSlice("_error.c");
        defer errorName.deinit();
        const errorFile = root.createFile(errorName.items, .{}) catch |e| {
            std.log.err("Could not create error implementation file '{s}': {?}", .{ errorName.items, e });
            break :writeError;
        };
        errorFile.writer().writeAll(err.items) catch |e| {
            std.log.err("Could not write to error implementation file '{s}': {?}", .{ errorName.items, e });
        };
    }
}
