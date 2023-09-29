const std = @import("std");
const lex = @import("lex.zig");

pub fn note(comptime msgFmt: []const u8, msgArg: anytype, location: ?lex.SourcePos) void {
    show(.cyan, " note", msgFmt, msgArg, null, .{}, location);
}

pub fn noteWithTip(comptime msgFmt: []const u8, msgArg: anytype, comptime tipFmt: []const u8, tipArg: anytype, location: ?lex.SourcePos) void {
    show(.cyan, " note", msgFmt, msgArg, tipFmt, tipArg, location);
}

pub fn warn(comptime msgFmt: []const u8, msgArg: anytype, location: ?lex.SourcePos) void {
    show(.yellow, " warn", msgFmt, msgArg, null, .{}, location);
}

pub fn warnWithTip(comptime msgFmt: []const u8, msgArg: anytype, comptime tipFmt: []const u8, tipArg: anytype, location: ?lex.SourcePos) void {
    show(.yellow, " warn", msgFmt, msgArg, tipFmt, tipArg, location);
}

pub fn err(comptime msgFmt: []const u8, msgArg: anytype, location: ?lex.SourcePos) void {
    show(.red, "error", msgFmt, msgArg, null, .{}, location);
}

pub fn errWithTip(comptime msgFmt: []const u8, msgArg: anytype, comptime tipFmt: []const u8, tipArg: anytype, location: ?lex.SourcePos) void {
    show(.red, "error", msgFmt, msgArg, tipFmt, tipArg, location);
}

fn show(
    comptime color: std.io.tty.Color,
    comptime level: []const u8,
    comptime msgFmt: []const u8,
    msgArg: anytype,
    comptime tipFmt: ?[]const u8,
    tipArg: anytype,
    location: ?lex.SourcePos,
) void {
    const stderr = std.io.getStdErr();
    const writer = stderr.writer();
    std.debug.getStderrMutex().lock();
    defer std.debug.getStderrMutex().unlock();

    nosuspend writer.writeByte('\n') catch return;

    head(color, false, level, stderr);
    nosuspend writer.print(msgFmt ++ "\n", msgArg) catch return;

    if (tipFmt) |format| {
        head(color, true, level, stderr);
        nosuspend writer.print("Tip: " ++ format ++ "\n", tipArg) catch return;
    }

    if (location) |loc| {
        head(color, true, level, stderr);
        nosuspend writer.print("At: {s}:{d}:{d}\n", .{ loc.filename, loc.line, loc.col }) catch return;
    }
}

fn head(comptime color: std.io.tty.Color, comptime onlyPad: bool, comptime level: []const u8, file: std.fs.File) void {
    const tty = std.io.tty.detectConfig(file);
    const writer = file.writer();

    tty.setColor(file, color) catch {};
    if (onlyPad) {
        inline for (0..level.len + 2) |_| {
            nosuspend writer.writeByte(' ') catch return;
        }
    } else {
        nosuspend _ = writer.write(" " ++ level ++ " ") catch return;
    }
    _ = nosuspend writer.write("| ") catch return;
    tty.setColor(file, .reset) catch {};
}
