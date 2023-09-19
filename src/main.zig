const std = @import("std");
const lex = @import("lex.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const tokens = try lex.parseAll(allocator, "test", "\"pee poo\" >= ()");
    defer allocator.free(tokens);
}
