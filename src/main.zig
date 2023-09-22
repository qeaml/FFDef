const std = @import("std");
const parse = @import("parse.zig");
const codegen = @import("codegen.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer allocator.free(args);

    if (args.len < 2) {
        std.debug.print("Provide a filename", .{});
        return;
    }

    const filename = args[1];
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();
    const source = try file.reader().readAllAlloc(allocator, 102400);
    defer allocator.free(source);

    const format = try parse.all(allocator, filename, source);
    const header = std.ArrayList(u8).init(allocator);
    defer header.deinit();
    const reader = std.ArrayList(u8).init(allocator);
    defer reader.deinit();
    const writer = std.ArrayList(u8).init(allocator);
    defer writer.deinit();

    try codegen.write(format, std.io.getStdOut().writer(), std.io.getStdOut().writer(), std.io.getStdOut().writer());
}
